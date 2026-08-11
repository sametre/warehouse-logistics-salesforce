public with sharing class WarehousePickingService {
    public class PickingException extends Exception {}

    public class PickingResult {
        @AuraEnabled public Id pickTaskId;
        @AuraEnabled public Decimal pickedQuantity;
        @AuraEnabled public Decimal remainingQuantity;
        @AuraEnabled public String taskStatus;
        @AuraEnabled public String orderStatus;
    }

    public static PickingResult completePick(Id pickTaskId, Decimal quantity, String notes) {
        if (pickTaskId == null) {
            throw new PickingException('Pick task is required.');
        }
        if (quantity == null || quantity <= 0) {
            throw new PickingException('Picked quantity must be greater than zero.');
        }

        WarehouseTransactionManager.Scope transactionScope = WarehouseTransactionManager.begin();
        try {
            Pick_Task__c task = WarehouseOutboundSelector.selectPickTaskForUpdate(pickTaskId);
            if (task == null) {
                throw new PickingException('Pick task could not be found or accessed.');
            }
            if (task.Status__c == 'Completed' || task.Status__c == 'Cancelled') {
                throw new PickingException('This pick task is already closed.');
            }

            Decimal currentPicked = task.Picked_Quantity__c == null ? 0 : task.Picked_Quantity__c;
            Decimal taskQuantity = task.Quantity__c == null ? 0 : task.Quantity__c;
            Decimal remaining = taskQuantity - currentPicked;
            if (quantity > remaining) {
                throw new PickingException('Picked quantity cannot exceed the remaining task quantity.');
            }

            Inventory__c inventory = WarehouseInventorySelector.selectByProductAndBinForUpdate(
                task.Product__c,
                task.Source_Bin__c
            );
            if (inventory == null) {
                throw new PickingException('Reserved inventory could not be found or accessed.');
            }
            Decimal onHand = inventory.On_Hand__c == null ? 0 : inventory.On_Hand__c;
            Decimal reserved = inventory.Reserved__c == null ? 0 : inventory.Reserved__c;
            if (onHand < quantity || reserved < quantity) {
                throw new PickingException('The reserved inventory is no longer sufficient for this pick.');
            }

            inventory.On_Hand__c = onHand - quantity;
            inventory.Reserved__c = reserved - quantity;
            inventory.Status__c = WarehouseInventoryService.calculateStatus(
                inventory.On_Hand__c,
                inventory.Reserved__c,
                inventory.Reorder_Level__c
            );
            Database.update(inventory, AccessLevel.USER_MODE);

            Database.insert(new Inventory_Transaction__c(
                Inventory__c = inventory.Id,
                Transaction_Type__c = 'Pick',
                Quantity__c = -quantity,
                Reference__c = task.Name,
                Notes__c = notes,
                Transaction_Date__c = System.now()
            ), AccessLevel.USER_MODE);

            task.Picked_Quantity__c = currentPicked + quantity;
            task.Status__c = task.Picked_Quantity__c >= taskQuantity ? 'Completed' : 'In Progress';
            if (task.Status__c == 'Completed') {
                task.Completed_At__c = System.now();
            }
            if (!String.isBlank(notes)) {
                task.Notes__c = notes;
            }
            Database.update(task, AccessLevel.USER_MODE);

            Outbound_Order_Line__c line = WarehouseOutboundSelector.selectOrderLineForUpdate(task.Outbound_Order_Line__c);
            if (line == null) {
                throw new PickingException('Outbound order line could not be found or accessed.');
            }
            Decimal linePicked = line.Picked_Quantity__c == null ? 0 : line.Picked_Quantity__c;
            line.Picked_Quantity__c = linePicked + quantity;
            line.Status__c = line.Picked_Quantity__c >= line.Allocated_Quantity__c ? 'Picked' : 'Picking';
            Database.update(line, AccessLevel.USER_MODE);

            Boolean allPicked = true;
            for (Outbound_Order_Line__c orderLine : WarehouseOutboundSelector.selectOrderLines(task.Outbound_Order__c)) {
                Decimal allocated = orderLine.Allocated_Quantity__c == null ? 0 : orderLine.Allocated_Quantity__c;
                Decimal picked = orderLine.Picked_Quantity__c == null ? 0 : orderLine.Picked_Quantity__c;
                if (allocated <= 0 || picked < allocated) {
                    allPicked = false;
                    break;
                }
            }

            Outbound_Order__c orderRecord = WarehouseOutboundSelector.selectOrderForUpdate(task.Outbound_Order__c);
            if (orderRecord == null) {
                throw new PickingException('Outbound order could not be found or accessed.');
            }
            orderRecord.Status__c = allPicked ? 'Packing' : 'Picking';
            Database.update(orderRecord, AccessLevel.USER_MODE);

            PickingResult result = new PickingResult();
            result.pickTaskId = task.Id;
            result.pickedQuantity = task.Picked_Quantity__c;
            result.remainingQuantity = taskQuantity - task.Picked_Quantity__c;
            result.taskStatus = task.Status__c;
            result.orderStatus = orderRecord.Status__c;

            transactionScope.complete();
            return result;
        } catch (Exception ex) {
            transactionScope.rollback();
            throw ex;
        }
    }
}
