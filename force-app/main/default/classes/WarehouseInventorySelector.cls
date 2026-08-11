public with sharing class WarehouseInventorySelector {
    public static Inventory__c selectByIdForUpdate(Id inventoryId) {
        List<Inventory__c> records = [
            SELECT Id, Product__c, Bin_Location__c, On_Hand__c, Reserved__c, Reorder_Level__c, Status__c
            FROM Inventory__c
            WHERE Id = :inventoryId
            WITH USER_MODE
            LIMIT 1
            FOR UPDATE
        ];
        return records.isEmpty() ? null : records[0];
    }

    public static Inventory__c selectByProductAndBinForUpdate(Id productId, Id binLocationId) {
        List<Inventory__c> records = [
            SELECT Id, Product__c, Bin_Location__c, On_Hand__c, Reserved__c, Reorder_Level__c, Status__c
            FROM Inventory__c
            WHERE Product__c = :productId AND Bin_Location__c = :binLocationId
            WITH USER_MODE
            LIMIT 1
            FOR UPDATE
        ];
        return records.isEmpty() ? null : records[0];
    }

    public static List<Inventory__c> selectForAllocationForUpdate(Set<Id> productIds, Set<Id> warehouseIds) {
        if (productIds == null || productIds.isEmpty() || warehouseIds == null || warehouseIds.isEmpty()) {
            return new List<Inventory__c>();
        }

        return [
            SELECT Id, Product__c, Bin_Location__c, Bin_Location__r.Warehouse__c,
                   Bin_Location__r.Bin_Type__c, On_Hand__c, Reserved__c,
                   Reorder_Level__c, Status__c, CreatedDate
            FROM Inventory__c
            WHERE Product__c IN :productIds
              AND Bin_Location__r.Warehouse__c IN :warehouseIds
              AND Status__c != 'Hold'
              AND Bin_Location__r.Bin_Type__c IN ('Picking', 'Storage')
            WITH USER_MODE
            FOR UPDATE
        ];
    }

    public static List<Inventory__c> selectInventory(Id warehouseId, Integer rowLimit) {
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
