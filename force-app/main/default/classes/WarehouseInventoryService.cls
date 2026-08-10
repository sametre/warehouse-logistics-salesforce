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
            SELECT Id, Product__c, Bin_Location__c, On_Hand__c, Reserved__c, Reorder_Level__c, Status__c
            FROM Inventory__c
            WHERE Id = :inventoryId
            WITH USER_MODE
            LIMIT 1
            FOR UPDATE
        ];

        applyQuantityChange(inventory, quantity);
        Database.update(inventory, AccessLevel.USER_MODE);
        createTransaction(inventory.Id, 'Receipt', quantity, reference, null);
        return inventory;
    }

    public static Inventory__c receiveIntoBin(
        Id productId,
        Id binLocationId,
        Decimal quantity,
        String reference,
        String notes
    ) {
        validateProductAndBin(productId, binLocationId);
        if (quantity == null || quantity <= 0) {
            throw new WarehouseInventoryException('Received quantity must be greater than zero.');
        }

        Inventory__c inventory = getOrCreateInventory(productId, binLocationId);
        applyQuantityChange(inventory, quantity);
        Database.update(inventory, AccessLevel.USER_MODE);
        createTransaction(inventory.Id, 'Receipt', quantity, reference, notes);
        return inventory;
    }

    public static void recordDamage(Id inventoryId, Decimal quantity, String reference, String notes) {
        if (inventoryId == null || quantity == null || quantity <= 0) {
            return;
        }
        createTransaction(inventoryId, 'Damage', quantity, reference, notes);
    }

    public static void moveStock(
        Id productId,
        Id sourceBinId,
        Id destinationBinId,
        Decimal quantity,
        String reference,
        String notes
    ) {
        validateProductAndBin(productId, sourceBinId);
        validateProductAndBin(productId, destinationBinId);
        if (sourceBinId == destinationBinId) {
            throw new WarehouseInventoryException('Source and destination bins must be different.');
        }
        if (quantity == null || quantity <= 0) {
            throw new WarehouseInventoryException('Transfer quantity must be greater than zero.');
        }

        Inventory__c sourceInventory = getExistingInventory(productId, sourceBinId);
        Decimal sourceOnHand = sourceInventory.On_Hand__c == null ? 0 : sourceInventory.On_Hand__c;
        Decimal sourceReserved = sourceInventory.Reserved__c == null ? 0 : sourceInventory.Reserved__c;
        if (sourceOnHand - sourceReserved < quantity) {
            throw new WarehouseInventoryException('Not enough available stock in the source bin.');
        }

        Inventory__c destinationInventory = getOrCreateInventory(productId, destinationBinId);

        applyQuantityChange(sourceInventory, -quantity);
        applyQuantityChange(destinationInventory, quantity);
        Database.update(new List<Inventory__c>{ sourceInventory, destinationInventory }, AccessLevel.USER_MODE);

        createTransaction(sourceInventory.Id, 'Transfer Out', -quantity, reference, notes);
        createTransaction(destinationInventory.Id, 'Transfer In', quantity, reference, notes);
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

    private static Inventory__c getExistingInventory(Id productId, Id binLocationId) {
        List<Inventory__c> records = [
            SELECT Id, Product__c, Bin_Location__c, On_Hand__c, Reserved__c, Reorder_Level__c, Status__c
            FROM Inventory__c
            WHERE Product__c = :productId AND Bin_Location__c = :binLocationId
            WITH USER_MODE
            LIMIT 1
            FOR UPDATE
        ];
        if (records.isEmpty()) {
            throw new WarehouseInventoryException('No source inventory exists for the selected product and bin.');
        }
        return records[0];
    }

    private static Inventory__c getOrCreateInventory(Id productId, Id binLocationId) {
        List<Inventory__c> records = [
            SELECT Id, Product__c, Bin_Location__c, On_Hand__c, Reserved__c, Reorder_Level__c, Status__c
            FROM Inventory__c
            WHERE Product__c = :productId AND Bin_Location__c = :binLocationId
            WITH USER_MODE
            LIMIT 1
            FOR UPDATE
        ];
        if (!records.isEmpty()) {
            return records[0];
        }

        Inventory__c inventory = new Inventory__c(
            Product__c = productId,
            Bin_Location__c = binLocationId,
            On_Hand__c = 0,
            Reserved__c = 0,
            Reorder_Level__c = 0,
            Status__c = 'Out of Stock'
        );
        Database.insert(inventory, AccessLevel.USER_MODE);
        return inventory;
    }

    private static void applyQuantityChange(Inventory__c inventory, Decimal quantityDelta) {
        Decimal currentOnHand = inventory.On_Hand__c == null ? 0 : inventory.On_Hand__c;
        Decimal newOnHand = currentOnHand + quantityDelta;
        if (newOnHand < 0) {
            throw new WarehouseInventoryException('Inventory balance cannot become negative.');
        }
        inventory.On_Hand__c = newOnHand;
        inventory.Status__c = calculateStatus(newOnHand, inventory.Reserved__c, inventory.Reorder_Level__c);
    }

    private static void createTransaction(
        Id inventoryId,
        String transactionType,
        Decimal quantity,
        String reference,
        String notes
    ) {
        Inventory_Transaction__c transactionRecord = new Inventory_Transaction__c(
            Inventory__c = inventoryId,
            Transaction_Type__c = transactionType,
            Quantity__c = quantity,
            Reference__c = reference,
            Notes__c = notes,
            Transaction_Date__c = System.now()
        );
        Database.insert(transactionRecord, AccessLevel.USER_MODE);
    }

    private static void validateProductAndBin(Id productId, Id binLocationId) {
        if (productId == null) {
            throw new WarehouseInventoryException('Product is required.');
        }
        if (binLocationId == null) {
            throw new WarehouseInventoryException('Bin location is required.');
        }
    }
}
