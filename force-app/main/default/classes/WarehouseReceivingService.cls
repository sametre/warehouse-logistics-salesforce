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

        WarehouseTransactionManager.Scope transactionScope = WarehouseTransactionManager.begin();
        try {
            Inbound_Shipment_Line__c line = WarehouseInboundSelector.selectShipmentLineForUpdate(shipmentLineId);
            if (line == null) {
                throw new ReceivingException('Shipment line could not be found or accessed.');
            }
            if (line.Inbound_Shipment__r.Status__c == 'Closed' || line.Inbound_Shipment__r.Status__c == 'Cancelled') {
                throw new ReceivingException('Closed or cancelled shipments cannot be received.');
            }

            Bin_Location__c receivingBin = WarehouseInboundSelector.selectBin(receivingBinId);
            if (receivingBin == null) {
                throw new ReceivingException('Receiving bin could not be found or accessed.');
            }
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
                Id suggestedBinId = WarehouseInboundSelector.selectSuggestedPutawayBin(
                    line.Inbound_Shipment__r.Warehouse__c,
                    receivingBinId
                );
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

            transactionScope.complete();
            return result;
        } catch (Exception ex) {
            transactionScope.rollback();
            throw ex;
        }
    }

    private static String updateShipmentReceivingStatus(Id shipmentId) {
        List<Inbound_Shipment_Line__c> lines = WarehouseInboundSelector.selectShipmentLines(shipmentId);

        Boolean allReceived = !lines.isEmpty();
        for (Inbound_Shipment_Line__c item : lines) {
            Decimal expected = item.Expected_Quantity__c == null ? 0 : item.Expected_Quantity__c;
            Decimal received = item.Received_Quantity__c == null ? 0 : item.Received_Quantity__c;
            if (received < expected) {
                allReceived = false;
                break;
            }
        }

        Integer exceptionCount = WarehouseInboundSelector.countReceivingExceptions(shipmentId);
        String newStatus = exceptionCount > 0 ? 'Exception' : (allReceived ? 'Received' : 'Receiving');
        Database.update(
            new Inbound_Shipment__c(Id = shipmentId, Status__c = newStatus),
            AccessLevel.USER_MODE
        );
        return newStatus;
    }
}
