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
        Map<Id, AllocationResult> results = allocateOrders(new Set<Id>{ orderId });
        return results.get(orderId);
    }

    public static Map<Id, AllocationResult> allocateOrders(Set<Id> orderIds) {
        if (orderIds == null || orderIds.isEmpty()) {
            return new Map<Id, AllocationResult>();
        }

        List<Outbound_Order__c> orders = [
            SELECT Id, Name, Warehouse__c, Status__c, CreatedDate
            FROM Outbound_Order__c
            WHERE Id IN :orderIds
            WITH USER_MODE
            ORDER BY CreatedDate, Id
            FOR UPDATE
        ];
        if (orders.size() != orderIds.size()) {
            throw new OutboundException('One or more outbound orders could not be found or accessed.');
        }

        Set<Id> warehouseIds = new Set<Id>();
        for (Outbound_Order__c orderRecord : orders) {
            if (orderRecord.Warehouse__c == null) {
                throw new OutboundException('A warehouse must be selected before allocation.');
            }
            if (orderRecord.Status__c != 'Draft' && orderRecord.Status__c != 'Ready to Allocate') {
                throw new OutboundException('Only draft or ready-to-allocate orders can be allocated.');
            }
            warehouseIds.add(orderRecord.Warehouse__c);
        }

        List<Outbound_Order_Line__c> lines = [
            SELECT Id, Outbound_Order__c, Product__c, Ordered_Quantity__c,
                   Allocated_Quantity__c, Status__c, CreatedDate
            FROM Outbound_Order_Line__c
            WHERE Outbound_Order__c IN :orderIds AND Status__c != 'Cancelled'
            WITH USER_MODE
            ORDER BY CreatedDate, Id
            FOR UPDATE
        ];

        Map<Id, List<Outbound_Order_Line__c>> linesByOrder = new Map<Id, List<Outbound_Order_Line__c>>();
        Set<Id> productIds = new Set<Id>();
        for (Outbound_Order_Line__c line : lines) {
            if (line.Product__c == null || line.Ordered_Quantity__c == null || line.Ordered_Quantity__c <= 0) {
                throw new OutboundException('Every order line requires a product and quantity greater than zero.');
            }
            if (!linesByOrder.containsKey(line.Outbound_Order__c)) {
                linesByOrder.put(line.Outbound_Order__c, new List<Outbound_Order_Line__c>());
            }
            linesByOrder.get(line.Outbound_Order__c).add(line);
            productIds.add(line.Product__c);
        }
        for (Outbound_Order__c orderRecord : orders) {
            if (!linesByOrder.containsKey(orderRecord.Id)) {
                throw new OutboundException('Add at least one order line before allocation.');
            }
        }

        List<Inventory__c> inventoryRecords = [
            SELECT Id, Product__c, Bin_Location__c, Bin_Location__r.Warehouse__c,
                   Bin_Location__r.Bin_Type__c, On_Hand__c, Reserved__c,
                   Reorder_Level__c, Status__c, CreatedDate
            FROM Inventory__c
            WHERE Product__c IN :productIds
              AND Bin_Location__r.Warehouse__c IN :warehouseIds
              AND Status__c != 'Hold'
              AND Bin_Location__r.Bin_Type__c IN ('Picking', 'Storage')
            WITH USER_MODE
            ORDER BY CreatedDate, Id
            FOR UPDATE
        ];

        Map<String, List<Inventory__c>> inventoryByWarehouseProduct = new Map<String, List<Inventory__c>>();
        // Build the candidate lists in two passes so forward-pick bins are consumed before reserve storage.
        for (Integer pass = 0; pass < 2; pass++) {
            for (Inventory__c inventory : inventoryRecords) {
                Boolean isPickingBin = inventory.Bin_Location__r.Bin_Type__c == 'Picking';
                if ((pass == 0 && !isPickingBin) || (pass == 1 && isPickingBin)) {
                    continue;
                }
                Decimal onHand = inventory.On_Hand__c == null ? 0 : inventory.On_Hand__c;
                Decimal reserved = inventory.Reserved__c == null ? 0 : inventory.Reserved__c;
                if (onHand - reserved <= 0) {
                    continue;
                }
                String key = inventoryKey(inventory.Bin_Location__r.Warehouse__c, inventory.Product__c);
                if (!inventoryByWarehouseProduct.containsKey(key)) {
                    inventoryByWarehouseProduct.put(key, new List<Inventory__c>());
                }
                inventoryByWarehouseProduct.get(key).add(inventory);
            }
        }

        Map<Id, Inventory__c> touchedInventory = new Map<Id, Inventory__c>();
        List<Outbound_Order_Line__c> linesToUpdate = new List<Outbound_Order_Line__c>();
        List<Pick_Task__c> pickTasks = new List<Pick_Task__c>();
        Map<Id, Decimal> quantityByOrder = new Map<Id, Decimal>();
        Map<Id, Integer> taskCountByOrder = new Map<Id, Integer>();

        for (Outbound_Order__c orderRecord : orders) {
            Decimal orderAllocated = 0;
            Integer orderTaskCount = 0;

            for (Outbound_Order_Line__c line : linesByOrder.get(orderRecord.Id)) {
                Decimal requiredQuantity = line.Ordered_Quantity__c;
                String key = inventoryKey(orderRecord.Warehouse__c, line.Product__c);
                List<Inventory__c> candidates = inventoryByWarehouseProduct.get(key);
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
                    touchedInventory.put(inventory.Id, inventory);

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
                    orderAllocated += allocated;
                    orderTaskCount++;
                }

                if (requiredQuantity > 0) {
                    throw new OutboundException('Insufficient available stock for one or more order lines.');
                }
                line.Allocated_Quantity__c = line.Ordered_Quantity__c;
                line.Status__c = 'Allocated';
                linesToUpdate.add(line);
            }

            orderRecord.Status__c = 'Allocated';
            quantityByOrder.put(orderRecord.Id, orderAllocated);
            taskCountByOrder.put(orderRecord.Id, orderTaskCount);
        }

        if (!touchedInventory.isEmpty()) {
            Database.update(touchedInventory.values(), true, AccessLevel.USER_MODE);
        }
        Database.update(linesToUpdate, true, AccessLevel.USER_MODE);
        Database.insert(pickTasks, true, AccessLevel.USER_MODE);
        Database.update(orders, true, AccessLevel.USER_MODE);

        Map<Id, AllocationResult> results = new Map<Id, AllocationResult>();
        for (Outbound_Order__c orderRecord : orders) {
            AllocationResult result = new AllocationResult();
            result.orderId = orderRecord.Id;
            result.pickTaskCount = taskCountByOrder.get(orderRecord.Id);
            result.allocatedQuantity = quantityByOrder.get(orderRecord.Id);
            result.orderStatus = orderRecord.Status__c;
            results.put(orderRecord.Id, result);
        }
        return results;
    }

    private static String inventoryKey(Id warehouseId, Id productId) {
        return String.valueOf(warehouseId) + ':' + String.valueOf(productId);
    }
}
