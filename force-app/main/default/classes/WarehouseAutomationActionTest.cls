@IsTest
private class WarehouseAutomationActionTest {
    private class Scenario {
        Id warehouseId;
        Id productId;
        Id customerId;
    }

    private static Scenario createScenario() {
        Warehouse__c warehouse = new Warehouse__c(
            Name = 'Automation DC', Code__c = 'AUTO-01', City__c = 'Bursa', Is_Active__c = true
        );
        insert warehouse;

        Bin_Location__c pickBin = new Bin_Location__c(
            Name = 'Automation Pick', Warehouse__c = warehouse.Id, Bin_Code__c = 'AUTO-PICK-01',
            Bin_Type__c = 'Picking', Capacity__c = 500, Is_Active__c = true
        );
        insert pickBin;

        Product2 product = new Product2(Name = 'Automation Product', ProductCode = 'AUTO-SKU', IsActive = true);
        insert product;
        insert new Inventory__c(
            Product__c = product.Id, Bin_Location__c = pickBin.Id,
            On_Hand__c = 50, Reserved__c = 0, Reorder_Level__c = 5, Status__c = 'Available'
        );

        Account customer = new Account(Name = 'Automation Customer');
        insert customer;

        Scenario scenario = new Scenario();
        scenario.warehouseId = warehouse.Id;
        scenario.productId = product.Id;
        scenario.customerId = customer.Id;
        return scenario;
    }

    private static Outbound_Order__c createDraftOrder(Scenario scenario, String externalReference, Decimal quantity) {
        Outbound_Order__c orderRecord = new Outbound_Order__c(
            Warehouse__c = scenario.warehouseId,
            Customer__c = scenario.customerId,
            Status__c = 'Draft',
            Priority__c = 'Normal',
            Order_Date__c = Date.today(),
            Required_Ship_Date__c = Date.today().addDays(1),
            External_Order_Reference__c = externalReference
        );
        insert orderRecord;
        insert new Outbound_Order_Line__c(
            Outbound_Order__c = orderRecord.Id,
            Product__c = scenario.productId,
            Ordered_Quantity__c = quantity,
            Allocated_Quantity__c = 0,
            Picked_Quantity__c = 0,
            Packed_Quantity__c = 0,
            Status__c = 'Pending'
        );
        return orderRecord;
    }

    @IsTest
    static void invocableActionHandlesMultipleOrdersInOneCall() {
        Scenario scenario = createScenario();
        Outbound_Order__c firstOrder = createDraftOrder(scenario, 'AUTO-1001', 12);
        Outbound_Order__c secondOrder = createDraftOrder(scenario, 'AUTO-1002', 8);

        WarehouseAllocateOrderAction.Request firstRequest = new WarehouseAllocateOrderAction.Request();
        firstRequest.orderId = firstOrder.Id;
        WarehouseAllocateOrderAction.Request secondRequest = new WarehouseAllocateOrderAction.Request();
        secondRequest.orderId = secondOrder.Id;

        Test.startTest();
        List<WarehouseAllocateOrderAction.Response> responses = WarehouseAllocateOrderAction.allocate(
            new List<WarehouseAllocateOrderAction.Request>{ firstRequest, secondRequest }
        );
        Test.stopTest();

        System.assertEquals(2, responses.size());
        System.assertEquals('Allocated', responses[0].orderStatus);
        System.assertEquals('Allocated', responses[1].orderStatus);
        System.assertEquals(20, [SELECT Reserved__c FROM Inventory__c WHERE Product__c = :scenario.productId LIMIT 1].Reserved__c);
        System.assertEquals(2, [SELECT COUNT() FROM Pick_Task__c]);
    }

    @IsTest
    static void recordTriggeredFlowAllocatesWhenOrderBecomesReady() {
        Scenario scenario = createScenario();
        Outbound_Order__c orderRecord = createDraftOrder(scenario, 'AUTO-FLOW-01', 10);

        Test.startTest();
        orderRecord.Status__c = 'Ready to Allocate';
        update orderRecord;
        Test.stopTest();

        Outbound_Order__c allocated = [SELECT Status__c FROM Outbound_Order__c WHERE Id = :orderRecord.Id];
        System.assertEquals('Allocated', allocated.Status__c);
        System.assertEquals(1, [SELECT COUNT() FROM Pick_Task__c WHERE Outbound_Order__c = :orderRecord.Id]);
    }

    @IsTest
    static void recordTriggeredFlowRoutesAllocationFailureToLog() {
        Scenario scenario = createScenario();
        Outbound_Order__c orderRecord = createDraftOrder(scenario, 'AUTO-FAIL-01', 80);

        Test.startTest();
        orderRecord.Status__c = 'Ready to Allocate';
        update orderRecord;
        Test.stopTest();

        Outbound_Order__c failedOrder = [SELECT Status__c FROM Outbound_Order__c WHERE Id = :orderRecord.Id];
        System.assertEquals('Ready to Allocate', failedOrder.Status__c);
        String orderIdText = String.valueOf(orderRecord.Id);
        Warehouse_Automation_Log__c logRecord = [
            SELECT Flow_Name__c, Related_Record_Id__c, Severity__c, Message__c
            FROM Warehouse_Automation_Log__c
            WHERE Related_Record_Id__c = :orderIdText
            LIMIT 1
        ];
        System.assertEquals('Outbound_Order_Auto_Allocation', logRecord.Flow_Name__c);
        System.assertEquals('Error', logRecord.Severity__c);
        System.assert(logRecord.Message__c.contains('Insufficient'));
        System.assertEquals(0, [SELECT COUNT() FROM Pick_Task__c WHERE Outbound_Order__c = :orderRecord.Id]);
    }

    @IsTest
    static void faultLoggerCreatesReviewableAuditRecord() {
        WarehouseAutomationFaultAction.Request request = new WarehouseAutomationFaultAction.Request();
        request.flowName = 'Unit_Test_Flow';
        request.relatedRecordId = 'a001234567890ABCDE';
        request.message = 'Allocation test failure';
        request.context = 'Negative-path unit test';

        Test.startTest();
        WarehouseAutomationFaultAction.logFaults(new List<WarehouseAutomationFaultAction.Request>{ request });
        Test.stopTest();

        Warehouse_Automation_Log__c logRecord = [
            SELECT Flow_Name__c, Related_Record_Id__c, Severity__c, Message__c, Context__c
            FROM Warehouse_Automation_Log__c
            LIMIT 1
        ];
        System.assertEquals('Unit_Test_Flow', logRecord.Flow_Name__c);
        System.assertEquals('a001234567890ABCDE', logRecord.Related_Record_Id__c);
        System.assertEquals('Error', logRecord.Severity__c);
        System.assertEquals('Allocation test failure', logRecord.Message__c);
        System.assertEquals('Negative-path unit test', logRecord.Context__c);
    }
}
