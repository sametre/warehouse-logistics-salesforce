@IsTest
private class WarehouseReceivingPutawayTest {
    @TestSetup
    static void setupData() {
        Warehouse__c warehouse = new Warehouse__c(
            Name = 'Bursa DC', Code__c = 'BUR-01', City__c = 'Bursa', Is_Active__c = true
        );
        insert warehouse;

        insert new List<Bin_Location__c>{
            new Bin_Location__c(
                Name = 'Receiving Dock 1', Warehouse__c = warehouse.Id, Bin_Code__c = 'RCV-01',
                Bin_Type__c = 'Receiving', Capacity__c = 500, Is_Active__c = true
            ),
            new Bin_Location__c(
                Name = 'Storage A-01', Warehouse__c = warehouse.Id, Bin_Code__c = 'A-01',
                Bin_Type__c = 'Storage', Capacity__c = 500, Is_Active__c = true
            )
        };

        Product2 product = new Product2(Name = 'Logistics Demo Item', ProductCode = 'LOG-001', IsActive = true);
        insert product;

        Account supplier = new Account(Name = 'Demo Supplier');
        insert supplier;

        Inbound_Shipment__c shipment = new Inbound_Shipment__c(
            Supplier__c = supplier.Id,
            Warehouse__c = warehouse.Id,
            Expected_Date__c = Date.today(),
            Status__c = 'Expected',
            Carrier__c = 'Demo Carrier',
            Tracking_Number__c = 'TRK-1001'
        );
        insert shipment;

        insert new Inbound_Shipment_Line__c(
            Inbound_Shipment__c = shipment.Id,
            Product__c = product.Id,
            Expected_Quantity__c = 20,
            Received_Quantity__c = 0,
            Damaged_Quantity__c = 0
        );
    }

    @IsTest
    static void receivingCreatesStagingStockAndPutawayTask() {
        Inbound_Shipment_Line__c line = [SELECT Id FROM Inbound_Shipment_Line__c LIMIT 1];
        Bin_Location__c receivingBin = [SELECT Id FROM Bin_Location__c WHERE Bin_Type__c = 'Receiving' LIMIT 1];

        Test.startTest();
        WarehouseReceivingService.ReceivingResult result = WarehouseReceivingService.receiveLine(
            line.Id, receivingBin.Id, 20, 2, 'Two cartons damaged on arrival.'
        );
        Test.stopTest();

        System.assertEquals(18, result.acceptedQuantity);
        System.assertEquals(2, result.damagedQuantity);
        System.assertNotEquals(null, result.receivingTaskId);
        System.assertNotEquals(null, result.putawayTaskId);
        System.assertEquals('Received', result.shipmentStatus);

        Inventory__c stagedInventory = [
            SELECT On_Hand__c, Bin_Location__c FROM Inventory__c WHERE Bin_Location__c = :receivingBin.Id LIMIT 1
        ];
        System.assertEquals(18, stagedInventory.On_Hand__c);

        Receiving_Task__c receivingTask = [
            SELECT Status__c, Received_Quantity__c, Damaged_Quantity__c FROM Receiving_Task__c LIMIT 1
        ];
        System.assertEquals('Exception', receivingTask.Status__c);
        System.assertEquals(20, receivingTask.Received_Quantity__c);
        System.assertEquals(2, receivingTask.Damaged_Quantity__c);

        Putaway_Task__c task = [SELECT Status__c, Quantity__c, Suggested_Bin__c FROM Putaway_Task__c LIMIT 1];
        System.assertEquals('Open', task.Status__c);
        System.assertEquals(18, task.Quantity__c);
        System.assertNotEquals(null, task.Suggested_Bin__c);

        List<Inventory_Transaction__c> transactions = [
            SELECT Transaction_Type__c, Quantity__c FROM Inventory_Transaction__c ORDER BY CreatedDate
        ];
        System.assertEquals(2, transactions.size());
    }

    @IsTest
    static void putawayMovesStockAndClosesShipment() {
        Inbound_Shipment_Line__c line = [SELECT Id FROM Inbound_Shipment_Line__c LIMIT 1];
        Bin_Location__c receivingBin = [SELECT Id FROM Bin_Location__c WHERE Bin_Type__c = 'Receiving' LIMIT 1];
        Bin_Location__c storageBin = [SELECT Id FROM Bin_Location__c WHERE Bin_Type__c = 'Storage' LIMIT 1];

        WarehouseReceivingService.ReceivingResult receiveResult = WarehouseReceivingService.receiveLine(
            line.Id, receivingBin.Id, 20, 0, null
        );

        Test.startTest();
        WarehousePutawayService.completePutaway(receiveResult.putawayTaskId, storageBin.Id, 'Placed in A-01.');
        Test.stopTest();

        Putaway_Task__c task = [
            SELECT Status__c, Destination_Bin__c, Completed_At__c FROM Putaway_Task__c WHERE Id = :receiveResult.putawayTaskId
        ];
        System.assertEquals('Completed', task.Status__c);
        System.assertEquals(storageBin.Id, task.Destination_Bin__c);
        System.assertNotEquals(null, task.Completed_At__c);

        Map<Id, Inventory__c> inventoriesByBin = new Map<Id, Inventory__c>();
        for (Inventory__c inventory : [SELECT Bin_Location__c, On_Hand__c FROM Inventory__c]) {
            inventoriesByBin.put(inventory.Bin_Location__c, inventory);
        }
        System.assertEquals(0, inventoriesByBin.get(receivingBin.Id).On_Hand__c);
        System.assertEquals(20, inventoriesByBin.get(storageBin.Id).On_Hand__c);

        Inbound_Shipment__c shipment = [SELECT Status__c FROM Inbound_Shipment__c LIMIT 1];
        System.assertEquals('Closed', shipment.Status__c);

        List<Inventory_Transaction__c> transfers = [
            SELECT Transaction_Type__c, Quantity__c
            FROM Inventory_Transaction__c
            WHERE Transaction_Type__c IN ('Transfer In', 'Transfer Out')
        ];
        System.assertEquals(2, transfers.size());
    }

    @IsTest
    static void receivingRejectsOverReceipt() {
        Inbound_Shipment_Line__c line = [SELECT Id FROM Inbound_Shipment_Line__c LIMIT 1];
        Bin_Location__c receivingBin = [SELECT Id FROM Bin_Location__c WHERE Bin_Type__c = 'Receiving' LIMIT 1];
        Boolean rejected = false;

        Test.startTest();
        try {
            WarehouseReceivingService.receiveLine(line.Id, receivingBin.Id, 21, 0, null);
        } catch (WarehouseReceivingService.ReceivingException ex) {
            rejected = true;
            System.assert(ex.getMessage().contains('exceed'));
        }
        Test.stopTest();

        System.assertEquals(true, rejected);
    }

    @IsTest
    static void controllerReturnsOperationalQueues() {
        Warehouse__c warehouse = [SELECT Id FROM Warehouse__c LIMIT 1];

        Test.startTest();
        List<WarehouseOperationsController.ReceivingRow> receivingRows = WarehouseOperationsController.getReceivingQueue(warehouse.Id);
        List<WarehouseOperationsController.BinOption> bins = WarehouseOperationsController.getActiveBins(warehouse.Id);
        Test.stopTest();

        System.assertEquals(1, receivingRows.size());
        System.assertEquals(20, receivingRows[0].remainingQuantity);
        System.assertEquals(2, bins.size());
    }
}
