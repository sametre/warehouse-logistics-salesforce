public with sharing class WarehousePutawayService {
    public class PutawayException extends Exception {}

    public static void completePutaway(Id putawayTaskId, Id destinationBinId, String notes) {
        if (putawayTaskId == null || destinationBinId == null) {
            throw new PutawayException('Putaway task and destination bin are required.');
        }

        Putaway_Task__c task = [
            SELECT Id, Name, Status__c, Product__c, Warehouse__c, Source_Bin__c,
                   Suggested_Bin__c, Destination_Bin__c, Quantity__c, Inbound_Shipment__c
            FROM Putaway_Task__c
            WHERE Id = :putawayTaskId
            WITH USER_MODE
            LIMIT 1
            FOR UPDATE
        ];
        if (task.Status__c == 'Completed') {
            throw new PutawayException('This putaway task is already completed.');
        }
        if (task.Status__c == 'Exception') {
            throw new PutawayException('Resolve the putaway exception before completing the task.');
        }

        Bin_Location__c destination = [
            SELECT Id, Warehouse__c, Is_Active__c, Bin_Type__c
            FROM Bin_Location__c
            WHERE Id = :destinationBinId
            WITH USER_MODE
            LIMIT 1
        ];
        if (!destination.Is_Active__c || destination.Warehouse__c != task.Warehouse__c) {
            throw new PutawayException('Destination bin must be active and belong to the same warehouse.');
        }
        if (destination.Bin_Type__c == 'Receiving' || destination.Bin_Type__c == 'Shipping') {
            throw new PutawayException('Putaway destination must be a storage, staging, or picking bin.');
        }

        WarehouseInventoryService.moveStock(
            task.Product__c,
            task.Source_Bin__c,
            destinationBinId,
            task.Quantity__c,
            task.Name,
            notes
        );

        task.Destination_Bin__c = destinationBinId;
        task.Status__c = 'Completed';
        task.Completed_At__c = System.now();
        task.Notes__c = notes;
        Database.update(task, AccessLevel.USER_MODE);

        updateShipmentPutawayStatus(task.Inbound_Shipment__c);
    }

    private static void updateShipmentPutawayStatus(Id shipmentId) {
        if (shipmentId == null) {
            return;
        }

        Integer openTaskCount = [
            SELECT COUNT()
            FROM Putaway_Task__c
            WHERE Inbound_Shipment__c = :shipmentId AND Status__c != 'Completed'
            WITH USER_MODE
        ];

        Inbound_Shipment__c shipment = new Inbound_Shipment__c(
            Id = shipmentId,
            Status__c = openTaskCount == 0 ? 'Closed' : 'Putaway'
        );
        Database.update(shipment, AccessLevel.USER_MODE);
    }
}
