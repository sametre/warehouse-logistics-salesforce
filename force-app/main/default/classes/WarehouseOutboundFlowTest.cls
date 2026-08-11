@IsTest
private class WarehouseOutboundFlowTest {
    @TestSetup
    static void setupData() {
        Warehouse__c warehouse = new Warehouse__c(
            Name = 'Outbound DC', Code__c = 'OUT-01', City__c = 'Bursa', Is_Active__c = true
        );
        insert warehouse;

        Bin_Location__c pickBin = new Bin_Location__c(
            Name = 'Picking A-01', Warehouse__c = warehouse.Id, Bin_Code__c = 'PICK-A-01',
            Bin_Type__c = 'Picking', Capacity__c = 500, Is_Active__c = true
        );
        Bin_Location__c storageBin = new Bin_Location__c(
            Name = 'Storage B-01', Warehouse__c = warehouse.Id, Bin_Code__c = 'STO-B-01',
            Bin_Type__c = 'Storage', Capacity__c = 500, Is_Active__c = true
        );
        insert new List<Bin_Location__c>{ pickBin, storageBin };

        Product2 product = new Product2(Name = 'Outbound Demo Product', ProductCode = 'OUT-SKU-01', IsActive = true);
        insert product;

        insert new List<Inventory__c>{
            new Inventory__c(
                Product__c = product.Id, Bin_Location__c = pickBin.Id,
                On_Hand__c = 12, Reserved__c = 0, Reorder_Level__c = 2, Status__c = 'Available'
            ),
            new Inventory__c(
                Product__c = product.Id, Bin_Location__c = storageBin.Id,
                On_Hand__c = 20, Reserved__c = 0, Reorder_Level__c = 2, Status__c = 'Available'
            )
        };

        Account customer = new Account(Name = 'Outbound Demo Customer');
        insert customer;

        Outbound_Order__c orderRecord = new Outbound_Order__c(
            Warehouse__c = warehouse.Id,
            Customer__c = customer.Id,
            Status__c = 'Draft',
            Priority__c = 'High',
            Order_Date__c = Date.today(),
            Required_Ship_Date__c = Date.today().addDays(1),
            External_Order_Reference__c = 'WEB-1001'
        );
        insert orderRecord;

        insert new Outbound_Order_Line__c(
            Outbound_Order__c = orderRecord.Id,
            Product__c = product.Id,
            Ordered_Quantity__c = 18,
            Allocated_Quantity__c = 0,
            Picked_Quantity__c = 0,
            Packed_Quantity__c = 0,
            Status__c = 'Pending'
        );
    }

    @IsTest
    static void allocationReservesStockAndCreatesPickTasks() {
        Outbound_Order__c orderRecord = [SELECT Id FROM Outbound_Order__c LIMIT 1];

        Test.startTest();
        WarehouseOutboundService.AllocationResult result = WarehouseOutboundService.allocateOrder(orderRecord.Id);
        Test.stopTest();

        System.assertEquals('Allocated', result.orderStatus);
        System.assertEquals(18, result.allocatedQuantity);
        System.assertEquals(2, result.pickTaskCount);

        Decimal reservedTotal = 0;
        for (Inventory__c inventory : [SELECT Reserved__c FROM Inventory__c]) {
            reservedTotal += inventory.Reserved__c == null ? 0 : inventory.Reserved__c;
        }
        System.assertEquals(18, reservedTotal);
        System.assertEquals(2, [SELECT COUNT() FROM Pick_Task__c]);

        Outbound_Order_Line__c line = [
            SELECT Allocated_Quantity__c, Status__c FROM Outbound_Order_Line__c LIMIT 1
        ];
        System.assertEquals(18, line.Allocated_Quantity__c);
        System.assertEquals('Allocated', line.Status__c);
    }

    @IsTest
    static void pickingConsumesOnHandAndReservation() {
        Outbound_Order__c orderRecord = [SELECT Id FROM Outbound_Order__c LIMIT 1];
        WarehouseOutboundService.allocateOrder(orderRecord.Id);
        List<Pick_Task__c> tasks = [SELECT Id, Quantity__c FROM Pick_Task__c ORDER BY Quantity__c];

        Test.startTest();
        for (Pick_Task__c task : tasks) {
            WarehousePickingService.completePick(task.Id, task.Quantity__c, 'Picked during test.');
        }
        Test.stopTest();

        Decimal reservedTotal = 0;
        Decimal onHandTotal = 0;
        for (Inventory__c inventory : [SELECT On_Hand__c, Reserved__c FROM Inventory__c]) {
            reservedTotal += inventory.Reserved__c == null ? 0 : inventory.Reserved__c;
            onHandTotal += inventory.On_Hand__c == null ? 0 : inventory.On_Hand__c;
        }
        System.assertEquals(0, reservedTotal);
        System.assertEquals(14, onHandTotal);
        System.assertEquals(2, [SELECT COUNT() FROM Inventory_Transaction__c WHERE Transaction_Type__c = 'Pick']);

        Outbound_Order__c updatedOrder = [SELECT Status__c FROM Outbound_Order__c WHERE Id = :orderRecord.Id];
        System.assertEquals('Packing', updatedOrder.Status__c);
    }

    @IsTest
    static void packingAndShippingCompleteTheOrder() {
        Outbound_Order__c orderRecord = [SELECT Id FROM Outbound_Order__c LIMIT 1];
        WarehouseOutboundService.allocateOrder(orderRecord.Id);
        for (Pick_Task__c task : [SELECT Id, Quantity__c FROM Pick_Task__c]) {
            WarehousePickingService.completePick(task.Id, task.Quantity__c, null);
        }

        Test.startTest();
        Package__c packageRecord = WarehouseShippingService.packOrder(orderRecord.Id, 4.5, 'Packed in one carton.');
        Shipment__c shipment = WarehouseShippingService.shipPackage(
            packageRecord.Id, 'Demo Express', 'TRACK-OUT-1001', 'Released from dock.'
        );
        Test.stopTest();

        System.assertNotEquals(null, shipment.Id);
        System.assertEquals('Shipped', shipment.Status__c);
        System.assertEquals('TRACK-OUT-1001', shipment.Tracking_Number__c);

        Outbound_Order__c shippedOrder = [SELECT Status__c FROM Outbound_Order__c WHERE Id = :orderRecord.Id];
        Package__c shippedPackage = [SELECT Status__c FROM Package__c WHERE Id = :packageRecord.Id];
        System.assertEquals('Shipped', shippedOrder.Status__c);
        System.assertEquals('Shipped', shippedPackage.Status__c);
    }

    @IsTest
    static void allocationRejectsInsufficientStock() {
        Outbound_Order__c orderRecord = [SELECT Id FROM Outbound_Order__c LIMIT 1];
        Outbound_Order_Line__c line = [SELECT Id, Ordered_Quantity__c FROM Outbound_Order_Line__c LIMIT 1];
        line.Ordered_Quantity__c = 100;
        update line;

        Boolean rejected = false;
        Test.startTest();
        try {
            WarehouseOutboundService.allocateOrder(orderRecord.Id);
        } catch (WarehouseOutboundService.OutboundException ex) {
            rejected = true;
            System.assert(ex.getMessage().contains('Insufficient'));
        }
        Test.stopTest();

        System.assertEquals(true, rejected);
        System.assertEquals(0, [SELECT COUNT() FROM Pick_Task__c]);
    }

    @IsTest
    static void controllerReturnsOutboundQueues() {
        Warehouse__c warehouse = [SELECT Id FROM Warehouse__c LIMIT 1];
        Outbound_Order__c orderRecord = [SELECT Id FROM Outbound_Order__c LIMIT 1];

        Test.startTest();
        List<WarehouseOutboundController.OrderRow> allocationRows = WarehouseOutboundController.getAllocationQueue(warehouse.Id);
        WarehouseOutboundController.allocateOrder(orderRecord.Id);
        List<WarehouseOutboundController.PickRow> pickRows = WarehouseOutboundController.getPickingQueue(warehouse.Id);
        Test.stopTest();

        System.assertEquals(1, allocationRows.size());
        System.assertEquals(2, pickRows.size());
    }
}
