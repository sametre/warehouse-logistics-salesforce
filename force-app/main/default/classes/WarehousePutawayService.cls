public with sharing class WarehousePutawayService {
    public class PutawayException extends Exception {}

    public static void completePutaway(Id putawayTaskId, Id destinationBinId, String notes) {
        if (putawayTaskId == null || destinationBinId == null) {
            throw new PutawayException('Putaway task and destination bin are required.');
        }

        WarehouseTransactionManager.Scope transactionScope = WarehouseTransactionManager.begin();
        try {
            Putaway_Task__c task = WarehouseInboundSelector.selectPutawayTaskForUpdate(putawayTaskId);
            if (task == null) {
                throw new PutawayException('Putaway task could not be found or accessed.');
            }
            if (task.Status__c == 'Completed') {
                throw new PutawayException('This putaway task is already completed.');
            }
            if (task.Status__c == 'Exception') {
                throw new PutawayException('Resolve the putaway exception before completing the task.');
            }

            Bin_Location__c destination = WarehouseInboundSelector.selectBin(destinationBinId);
            if (destination == null) {
                throw new PutawayException('Destination bin could not be found or accessed.');
            }
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
            transactionScope.complete();
        } catch (Exception ex) {
            transactionScope.rollback();
            throw ex;
        }
    }

    private static void updateShipmentPutawayStatus(Id shipmentId) {
        if (shipmentId == null) {
            return;
        }

        Integer openTaskCount = WarehouseInboundSelector.countOpenPutawayTasks(shipmentId);
        Integer receivingExceptionCount = WarehouseInboundSelector.countReceivingExceptions(shipmentId);
        String shipmentStatus = receivingExceptionCount > 0
            ? 'Exception'
            : (openTaskCount == 0 ? 'Closed' : 'Putaway');

        Database.update(
            new Inbound_Shipment__c(Id = shipmentId, Status__c = shipmentStatus),
            AccessLevel.USER_MODE
        );
    }
}
