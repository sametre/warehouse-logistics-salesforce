@IsTest
private class WarehouseInventoryServiceTest {
    @TestSetup
    static void setupData() {
        Warehouse__c warehouse = new Warehouse__c(
            Name = 'Bursa Distribution Center',
            Code__c = 'BUR-01',
            City__c = 'Bursa',
            Is_Active__c = true
        );
        insert warehouse;

        Bin_Location__c binLocation = new Bin_Location__c(
            Name = 'A-01-01',
            Warehouse__c = warehouse.Id,
            Bin_Code__c = 'BUR-A-01-01',
            Zone__c = 'A',
            Capacity__c = 500,
            Is_Active__c = true
        );
        insert binLocation;

        Product2 product = new Product2(Name = 'Demo Product', ProductCode = 'SKU-001', IsActive = true);
        insert product;

        Inventory__c inventory = new Inventory__c(
            Product__c = product.Id,
            Bin_Location__c = binLocation.Id,
            On_Hand__c = 10,
            Reserved__c = 2,
            Reorder_Level__c = 5,
            Status__c = 'Available'
        );
        insert inventory;
    }

    @IsTest
    static void receiveStockUpdatesBalanceAndCreatesLedgerEntry() {
        Inventory__c inventory = [SELECT Id FROM Inventory__c LIMIT 1];

        Test.startTest();
        Inventory__c updatedInventory = WarehouseInventoryService.receiveStock(inventory.Id, 7, 'PO-1001');
        Test.stopTest();

        Inventory__c stored = [SELECT On_Hand__c, Status__c FROM Inventory__c WHERE Id = :inventory.Id];
        System.assertEquals(17, stored.On_Hand__c);
        System.assertEquals('Available', stored.Status__c);
        System.assertEquals(inventory.Id, updatedInventory.Id);

        Inventory_Transaction__c ledger = [
            SELECT Transaction_Type__c, Quantity__c, Reference__c
            FROM Inventory_Transaction__c
            WHERE Inventory__c = :inventory.Id
            LIMIT 1
        ];
        System.assertEquals('Receipt', ledger.Transaction_Type__c);
        System.assertEquals(7, ledger.Quantity__c);
        System.assertEquals('PO-1001', ledger.Reference__c);
    }

    @IsTest
    static void receiveStockRejectsInvalidQuantity() {
        Inventory__c inventory = [SELECT Id FROM Inventory__c LIMIT 1];
        Boolean failedAsExpected = false;

        Test.startTest();
        try {
            WarehouseInventoryService.receiveStock(inventory.Id, 0, 'PO-1002');
        } catch (WarehouseInventoryService.WarehouseInventoryException ex) {
            failedAsExpected = true;
            System.assert(ex.getMessage().contains('greater than zero'));
        }
        Test.stopTest();

        System.assertEquals(true, failedAsExpected, 'Zero quantity must be rejected.');
    }

    @IsTest
    static void summaryReturnsWarehouseInventory() {
        Warehouse__c warehouse = [SELECT Id FROM Warehouse__c LIMIT 1];

        Test.startTest();
        WarehouseInventoryController.InventorySummary result = WarehouseInventoryController.getSummary(warehouse.Id);
        Test.stopTest();

        System.assertEquals(1, result.recordCount);
        System.assertEquals(10, result.onHand);
        System.assertEquals(2, result.reserved);
        System.assertEquals(8, result.available);
        System.assertEquals(1, result.rows.size());
        System.assertEquals('Demo Product', result.rows[0].productName);
    }
}
