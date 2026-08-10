public with sharing class WarehouseInventoryService {
    public class WarehouseInventoryException extends Exception {}

    public static Inventory__c receiveStock(Id inventoryId, Decimal quantity, String reference) {
        if (inventoryId == null) {
            throw new WarehouseInventoryException('Inventory record is required.');
        }
        if (quantity == null || quantity <= 0) {
            throw new WarehouseInventoryException('Received quantity must be greater than zero.');
        }

        Inventory__c inventory = [
            SELECT Id, On_Hand__c, Reserved__c, Reorder_Level__c, Status__c
            FROM Inventory__c
            WHERE Id = :inventoryId
            WITH USER_MODE
            LIMIT 1
            FOR UPDATE
        ];

        Decimal currentOnHand = inventory.On_Hand__c == null ? 0 : inventory.On_Hand__c;
        inventory.On_Hand__c = currentOnHand + quantity;
        inventory.Status__c = calculateStatus(inventory.On_Hand__c, inventory.Reserved__c, inventory.Reorder_Level__c);
        update inventory;

        Inventory_Transaction__c transactionRecord = new Inventory_Transaction__c(
            Inventory__c = inventory.Id,
            Transaction_Type__c = 'Receipt',
            Quantity__c = quantity,
            Reference__c = reference,
            Transaction_Date__c = System.now()
        );
        insert transactionRecord;

        return inventory;
    }

    public static String calculateStatus(Decimal onHand, Decimal reserved, Decimal reorderLevel) {
        Decimal safeOnHand = onHand == null ? 0 : onHand;
        Decimal safeReserved = reserved == null ? 0 : reserved;
        Decimal safeReorder = reorderLevel == null ? 0 : reorderLevel;
        Decimal available = safeOnHand - safeReserved;

        if (available <= 0) {
            return 'Out of Stock';
        }
        if (available <= safeReorder) {
            return 'Low Stock';
        }
        return 'Available';
    }

    public static List<Inventory__c> getInventory(Id warehouseId, Integer rowLimit) {
        Integer safeLimit = rowLimit == null ? 50 : Math.min(Math.max(rowLimit, 1), 200);

        if (warehouseId == null) {
            return [
                SELECT Id, Name, On_Hand__c, Reserved__c, Available__c, Reorder_Level__c, Status__c,
                       Product__c, Product__r.Name,
                       Bin_Location__c, Bin_Location__r.Name, Bin_Location__r.Bin_Code__c,
                       Bin_Location__r.Warehouse__c, Bin_Location__r.Warehouse__r.Name
                FROM Inventory__c
                WITH USER_MODE
                ORDER BY LastModifiedDate DESC
                LIMIT :safeLimit
            ];
        }

        return [
            SELECT Id, Name, On_Hand__c, Reserved__c, Available__c, Reorder_Level__c, Status__c,
                   Product__c, Product__r.Name,
                   Bin_Location__c, Bin_Location__r.Name, Bin_Location__r.Bin_Code__c,
                   Bin_Location__r.Warehouse__c, Bin_Location__r.Warehouse__r.Name
            FROM Inventory__c
            WHERE Bin_Location__r.Warehouse__c = :warehouseId
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT :safeLimit
        ];
    }
}
