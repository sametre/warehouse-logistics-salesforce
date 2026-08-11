@IsTest
private class WarehouseArchitectureTest {
    @TestSetup
    static void setupData() {
        Warehouse__c warehouse = new Warehouse__c(
            Name = 'Architecture DC',
            Code__c = 'ARCH-01',
            City__c = 'Bursa',
            Is_Active__c = true
        );
        insert warehouse;

        Bin_Location__c receivingBin = new Bin_Location__c(
            Name = 'Receiving Dock',
            Warehouse__c = warehouse.Id,
            Bin_Code__c = 'REC-ARCH-01',
            Bin_Type__c = 'Receiving',
            Capacity__c = 500,
            Is_Active__c = true
        );
        Bin_Location__c pickingBin = new Bin_Location__c(
            Name = 'Picking A-01',
            Warehouse__c = warehouse.Id,
            Bin_Code__c = 'PICK-ARCH-01',
            Bin_Type__c = 'Picking',
            Capacity__c = 500,
            Is_Active__c = true
        );
        insert new List<Bin_Location__c>{ receivingBin, pickingBin };

        Product2 product = new Product2(
            Name = 'Architecture Product',
            ProductCode = 'ARCH-SKU-01',
            IsActive = true
        );
        insert product;

        insert new Inventory__c(
            Product__c = product.Id,
            Bin_Location__c = pickingBin.Id,
            On_Hand__c = 25,
            Reserved__c = 0,
            Reorder_Level__c = 3,
            Status__c = 'Available'
        );

        Account customer = new Account(Name = 'Architecture Customer');
        insert customer;

        insert new Outbound_Order__c(
            Warehouse__c = warehouse.Id,
            Customer__c = customer.Id,
            Status__c = 'Draft',
            Priority__c = 'Normal',
            Order_Date__c = Date.today(),
            Required_Ship_Date__c = Date.today().addDays(2),
            External_Order_Reference__c = 'ARCH-ORDER-01'
        );
    }

    @IsTest
    static void selectorsProvideReadModelsWithoutControllerQueries() {
        Warehouse__c warehouse = [SELECT Id FROM Warehouse__c WHERE Code__c = 'ARCH-01' LIMIT 1];

        Test.startTest();
        List<Inventory__c> inventory = WarehouseInventorySelector.selectInventory(warehouse.Id, 500);
        List<Bin_Location__c> bins = WarehouseInboundSelector.selectActiveBins(warehouse.Id);
        List<Outbound_Order__c> orders = WarehouseOutboundSelector.selectAllocationQueue(warehouse.Id);
        Test.stopTest();

        System.assertEquals(1, inventory.size(), 'The inventory selector should respect the warehouse filter.');
        System.assertEquals(2, bins.size(), 'The inbound selector should return active warehouse bins.');
        System.assertEquals(1, orders.size(), 'The outbound selector should expose the draft allocation queue.');
    }

    @IsTest
    static void transactionScopeRollbackRestoresDatabaseState() {
        Warehouse__c warehouse = [SELECT Id, Name FROM Warehouse__c WHERE Code__c = 'ARCH-01' LIMIT 1];
        String originalName = warehouse.Name;

        Test.startTest();
        WarehouseTransactionManager.Scope scope = WarehouseTransactionManager.begin();
        warehouse.Name = 'Temporary Name';
        update warehouse;
        scope.rollback();
        Test.stopTest();

        Warehouse__c restored = [SELECT Name FROM Warehouse__c WHERE Id = :warehouse.Id];
        System.assertEquals(originalName, restored.Name, 'Rollback should restore all DML after the savepoint.');
    }

    @IsTest
    static void transactionScopeCompleteKeepsDatabaseChanges() {
        Warehouse__c warehouse = [SELECT Id, Name FROM Warehouse__c WHERE Code__c = 'ARCH-01' LIMIT 1];

        Test.startTest();
        WarehouseTransactionManager.Scope scope = WarehouseTransactionManager.begin();
        warehouse.Name = 'Committed Architecture DC';
        update warehouse;
        scope.complete();
        Test.stopTest();

        Warehouse__c stored = [SELECT Name FROM Warehouse__c WHERE Id = :warehouse.Id];
        System.assertEquals('Committed Architecture DC', stored.Name);
    }
    @IsTest
    static void bulkAllocationUsesBoundedQueryCount() {
        Warehouse__c warehouse = [SELECT Id FROM Warehouse__c WHERE Code__c = 'ARCH-01' LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 WHERE ProductCode = 'ARCH-SKU-01' LIMIT 1];
        Account customer = [SELECT Id FROM Account WHERE Name = 'Architecture Customer' LIMIT 1];
        Outbound_Order__c firstOrder = [
            SELECT Id FROM Outbound_Order__c WHERE External_Order_Reference__c = 'ARCH-ORDER-01' LIMIT 1
        ];
        insert new Outbound_Order_Line__c(
            Outbound_Order__c = firstOrder.Id,
            Product__c = product.Id,
            Ordered_Quantity__c = 5,
            Allocated_Quantity__c = 0,
            Picked_Quantity__c = 0,
            Packed_Quantity__c = 0,
            Status__c = 'Pending'
        );

        Outbound_Order__c secondOrder = new Outbound_Order__c(
            Warehouse__c = warehouse.Id,
            Customer__c = customer.Id,
            Status__c = 'Draft',
            Priority__c = 'High',
            Order_Date__c = Date.today(),
            Required_Ship_Date__c = Date.today().addDays(1),
            External_Order_Reference__c = 'ARCH-ORDER-02'
        );
        insert secondOrder;
        insert new Outbound_Order_Line__c(
            Outbound_Order__c = secondOrder.Id,
            Product__c = product.Id,
            Ordered_Quantity__c = 7,
            Allocated_Quantity__c = 0,
            Picked_Quantity__c = 0,
            Packed_Quantity__c = 0,
            Status__c = 'Pending'
        );

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        Map<Id, WarehouseOutboundService.AllocationResult> results = WarehouseOutboundService.allocateOrders(
            new Set<Id>{ firstOrder.Id, secondOrder.Id }
        );
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assert(queriesUsed <= 5, 'Bulk allocation should use a bounded selector query set, not queries per order.');
        System.assertEquals(12, [SELECT SUM(Reserved__c) total FROM Inventory__c][0].get('total'));
    }

}
