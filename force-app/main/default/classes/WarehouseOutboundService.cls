public with sharing class WarehouseOutboundService {
    public class OutboundException extends Exception {}

    public class AllocationResult {
        @AuraEnabled public Id orderId;
        @AuraEnabled public Integer pickTaskCount;
        @AuraEnabled public Decimal allocatedQuantity;
        @AuraEnabled public String orderStatus;
    }

    public static AllocationResult allocateOrder(Id orderId) {
        if (orderId == null) {
            throw new OutboundException('Outbound order is required.');
        }

        Outbound_Order__c orderRecord = [
            SELECT Id, Name, Warehouse__c, Status__c
            FROM Outbound_Order__c
            WHERE Id = :orderId
            WITH USER_MODE
            LIMIT 1
            FOR UPDATE
        ];

        if (orderRecord.Warehouse__c == null) {
            throw new OutboundException('A warehouse must be selected before allocation.');
        }
        if (orderRecord.Status__c != 'Draft' && orderRecord.Status__c != 'Ready to Allocate') {
            throw new OutboundException('Only draft or ready-to-allocate orders can be allocated.');
        }

        List<Outbound_Order_Line__c> lines = [
            SELECT Id, Product__c, Ordered_Quantity__c, Allocated_Quantity__c, Status__c
            FROM Outbound_Order_Line__c
            WHERE Outbound_Order__c = :orderId AND Status__c != 'Cancelled'
            WITH USER_MODE
            ORDER BY CreatedDate
            FOR UPDATE
        ];
        if (lines.isEmpty()) {
            throw new OutboundException('Add at least one order line before allocation.');
        }

        Set<Id> productIds = new Set<Id>();
        for (Outbound_Order_Line__c line : lines) {
            if (line.Product__c == null || line.Ordered_Quantity__c == null || line.Ordered_Quantity__c <= 0) {
                throw new OutboundException('Every order line requires a product and quantity greater than zero.');
            }
            productIds.add(line.Product__c);
        }

        List<Inventory__c> inventoryRecords = [
            SELECT Id, Product__c, Bin_Location__c, Bin_Location__r.Bin_Type__c,
                   On_Hand__c, Reserved__c, Reorder_Level__c, Status__c
            FROM Inventory__c
            WHERE Product__c IN :productIds
              AND Bin_Location__r.Warehouse__c = :orderRecord.Warehouse__c
              AND Status__c != 'Hold'
            WITH USER_MODE
            ORDER BY Bin_Location__r.Bin_Type__c, CreatedDate
            FOR UPDATE
        ];

        Map<Id, List<Inventory__c>> inventoryByProduct = new Map<Id, List<Inventory__c>>();
        for (Inventory__c inventory : inventoryRecords) {
            Decimal onHand = inventory.On_Hand__c == null ? 0 : inventory.On_Hand__c;
            Decimal reserved = inventory.Reserved__c == null ? 0 : inventory.Reserved__c;
            if (onHand - reserved <= 0) {
                continue;
            }
            if (!inventoryByProduct.containsKey(inventory.Product__c)) {
                inventoryByProduct.put(inventory.Product__c, new List<Inventory__c>());
            }
            inventoryByProduct.get(inventory.Product__c).add(inventory);
        }

        List<Pick_Task__c> pickTasks = new List<Pick_Task__c>();
        Decimal totalAllocated = 0;

        for (Outbound_Order_Line__c line : lines) {
            Decimal requiredQuantity = line.Ordered_Quantity__c;
            List<Inventory__c> candidates = inventoryByProduct.get(line.Product__c);
            if (candidates == null) {
                throw new OutboundException('Insufficient available stock for one or more order lines.');
            }

            for (Inventory__c inventory : candidates) {
                if (requiredQuantity <= 0) {
                    break;
                }
                Decimal onHand = inventory.On_Hand__c == null ? 0 : inventory.On_Hand__c;
                Decimal reserved = inventory.Reserved__c == null ? 0 : inventory.Reserved__c;
                Decimal available = onHand - reserved;
                if (available <= 0) {
                    continue;
                }

                Decimal allocated = available < requiredQuantity ? available : requiredQuantity;
                inventory.Reserved__c = reserved + allocated;
                inventory.Status__c = WarehouseInventoryService.calculateStatus(
                    inventory.On_Hand__c,
                    inventory.Reserved__c,
                    inventory.Reorder_Level__c
                );

                pickTasks.add(new Pick_Task__c(
                    Outbound_Order__c = orderRecord.Id,
                    Outbound_Order_Line__c = line.Id,
                    Warehouse__c = orderRecord.Warehouse__c,
                    Product__c = line.Product__c,
                    Source_Bin__c = inventory.Bin_Location__c,
                    Quantity__c = allocated,
                    Picked_Quantity__c = 0,
                    Status__c = 'Open'
                ));
                requiredQuantity -= allocated;
                totalAllocated += allocated;
            }

            if (requiredQuantity > 0) {
                throw new OutboundException('Insufficient available stock for one or more order lines.');
            }
            line.Allocated_Quantity__c = line.Ordered_Quantity__c;
            line.Status__c = 'Allocated';
        }

        Database.update(inventoryRecords, true, AccessLevel.USER_MODE);
        Database.update(lines, true, AccessLevel.USER_MODE);
        Database.insert(pickTasks, true, AccessLevel.USER_MODE);

        orderRecord.Status__c = 'Allocated';
        Database.update(orderRecord, AccessLevel.USER_MODE);

        AllocationResult result = new AllocationResult();
        result.orderId = orderRecord.Id;
        result.pickTaskCount = pickTasks.size();
        result.allocatedQuantity = totalAllocated;
        result.orderStatus = orderRecord.Status__c;
        return result;
    }
}
