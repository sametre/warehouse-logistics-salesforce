public with sharing class WarehouseReceivingService {
    public class ReceivingException extends Exception {}

    public class ReceivingResult {
        @AuraEnabled public Id receivingTaskId;
        @AuraEnabled public Id putawayTaskId;
        @AuraEnabled public Id inventoryId;
        @AuraEnabled public Decimal acceptedQuantity;
        @AuraEnabled public Decimal damagedQuantity;
        @AuraEnabled public String shipmentStatus;
    }

    public static ReceivingResult receiveLine(
        Id shipmentLineId,
        Id receivingBinId,
        Decimal receivedQuantity,
        Decimal damagedQuantity,
        String notes
    ) {
        if (shipmentLineId == null || receivingBinId == null) {
            throw new ReceivingException('Shipment line and receiving bin are required.');
        }
        if (receivedQuantity == null || receivedQuantity <= 0) {
            throw new ReceivingException('Received quantity must be greater than zero.');
        }

        Decimal safeDamaged = damagedQuantity == null ? 0 : damagedQuantity;
        if (safeDamaged < 0 || safeDamaged > receivedQuantity) {
            throw new ReceivingException('Damaged quantity must be between zero and the received quantity.');
        }

        Inbound_Shipment_Line__c line = [
            SELECT Id, Name, Product__c, Expected_Quantity__c, Received_Quantity__c, Damaged_Quantity__c,
                   Inbound_Shipment__c, Inbound_Shipment__r.Name, Inbound_Shipment__r.Status__c,
                   Inbound_Shipment__r.Warehouse__c
            FROM Inbound_Shipment_Line__c
            WHERE Id = :shipmentLineId
            WITH USER_MODE
            LIMIT 1
            FOR UPDATE
        ];

        if (line.Inbound_Shipment__r.Status__c == 'Closed' || line.Inbound_Shipment__r.Status__c == 'Cancelled') {
            throw new ReceivingException('Closed or cancelled shipments cannot be received.');
        }

        Bin_Location__c receivingBin = [
            SELECT Id, Warehouse__c, Is_Active__c, Bin_Type__c
            FROM Bin_Location__c
            WHERE Id = :receivingBinId
            WITH USER_MODE
            LIMIT 1
        ];
        if (!receivingBin.Is_Active__c || receivingBin.Warehouse__c != line.Inbound_Shipment__r.Warehouse__c) {
            throw new ReceivingException('Receiving bin must be active and belong to the shipment warehouse.');
        }
        if (receivingBin.Bin_Type__c != 'Receiving' && receivingBin.Bin_Type__c != 'Staging') {
            throw new ReceivingException('Select a Receiving or Staging bin for inbound stock.');
        }

        Decimal alreadyReceived = line.Received_Quantity__c == null ? 0 : line.Received_Quantity__c;
        Decimal expected = line.Expected_Quantity__c == null ? 0 : line.Expected_Quantity__c;
        if (alreadyReceived + receivedQuantity > expected) {
            throw new ReceivingException('Received quantity would exceed the expected shipment quantity.');
        }

        Decimal acceptedQuantity = receivedQuantity - safeDamaged;
        Inventory__c inventory;
        if (acceptedQuantity > 0) {
            inventory = WarehouseInventoryService.receiveIntoBin(
                line.Product__c,
                receivingBinId,
                acceptedQuantity,
                line.Inbound_Shipment__r.Name,
                notes
            );
        }

        line.Received_Quantity__c = alreadyReceived + receivedQuantity;
        line.Damaged_Quantity__c = (line.Damaged_Quantity__c == null ? 0 : line.Damaged_Quantity__c) + safeDamaged;
        Database.update(line, AccessLevel.USER_MODE);

        Receiving_Task__c receivingTask = new Receiving_Task__c(
            Inbound_Shipment__c = line.Inbound_Shipment__c,
            Inbound_Shipment_Line__c = line.Id,
            Product__c = line.Product__c,
            Warehouse__c = line.Inbound_Shipment__r.Warehouse__c,
            Receiving_Bin__c = receivingBinId,
            Expected_Quantity__c = expected,
            Received_Quantity__c = receivedQuantity,
            Damaged_Quantity__c = safeDamaged,
            Status__c = safeDamaged > 0 ? 'Exception' : 'Completed',
            Assigned_To__c = UserInfo.getUserId(),
            Received_At__c = System.now(),
            Notes__c = notes
        );
        Database.insert(receivingTask, AccessLevel.USER_MODE);

        Putaway_Task__c putawayTask;
        if (acceptedQuantity > 0) {
            Id suggestedBinId = suggestPutawayBin(line.Inbound_Shipment__r.Warehouse__c, receivingBinId);
            putawayTask = new Putaway_Task__c(
                Receiving_Task__c = receivingTask.Id,
                Inbound_Shipment__c = line.Inbound_Shipment__c,
                Product__c = line.Product__c,
                Warehouse__c = line.Inbound_Shipment__r.Warehouse__c,
                Source_Bin__c = receivingBinId,
                Suggested_Bin__c = suggestedBinId,
                Quantity__c = acceptedQuantity,
                Status__c = 'Open',
                Assigned_To__c = UserInfo.getUserId()
            );
            Database.insert(putawayTask, AccessLevel.USER_MODE);
        }

        if (safeDamaged > 0 && inventory != null) {
            WarehouseInventoryService.recordDamage(
                inventory.Id,
                safeDamaged,
                line.Inbound_Shipment__r.Name,
                'Damaged during receiving. ' + (String.isBlank(notes) ? '' : notes)
            );
        }

        String shipmentStatus = updateShipmentReceivingStatus(line.Inbound_Shipment__c);

        ReceivingResult result = new ReceivingResult();
        result.receivingTaskId = receivingTask.Id;
        result.putawayTaskId = putawayTask == null ? null : putawayTask.Id;
        result.inventoryId = inventory == null ? null : inventory.Id;
        result.acceptedQuantity = acceptedQuantity;
        result.damagedQuantity = safeDamaged;
        result.shipmentStatus = shipmentStatus;
        return result;
    }

    private static Id suggestPutawayBin(Id warehouseId, Id sourceBinId) {
        List<Bin_Location__c> bins = [
            SELECT Id
            FROM Bin_Location__c
            WHERE Warehouse__c = :warehouseId
              AND Is_Active__c = true
              AND Id != :sourceBinId
              AND Bin_Type__c IN ('Storage', 'Picking')
            WITH USER_MODE
            ORDER BY Bin_Type__c, Bin_Code__c
            LIMIT 1
        ];
        return bins.isEmpty() ? null : bins[0].Id;
    }

    private static String updateShipmentReceivingStatus(Id shipmentId) {
        List<Inbound_Shipment_Line__c> lines = [
            SELECT Expected_Quantity__c, Received_Quantity__c
            FROM Inbound_Shipment_Line__c
            WHERE Inbound_Shipment__c = :shipmentId
            WITH USER_MODE
        ];

        Boolean allReceived = !lines.isEmpty();
        for (Inbound_Shipment_Line__c item : lines) {
            Decimal expected = item.Expected_Quantity__c == null ? 0 : item.Expected_Quantity__c;
            Decimal received = item.Received_Quantity__c == null ? 0 : item.Received_Quantity__c;
            if (received < expected) {
                allReceived = false;
                break;
            }
        }

        String newStatus = allReceived ? 'Received' : 'Receiving';
        Inbound_Shipment__c shipment = new Inbound_Shipment__c(Id = shipmentId, Status__c = newStatus);
        Database.update(shipment, AccessLevel.USER_MODE);
        return newStatus;
    }
}
