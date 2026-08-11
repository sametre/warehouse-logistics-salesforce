@IsTest
private class WarehouseAutomationActionTest {
    @IsTest
    static void invocableActionHandlesMultipleOrdersInOneCall() {
        WarehouseTestDataFactory.CoreScenario scenario = WarehouseTestDataFactory.createCoreScenario('AUTO', 50);
        Outbound_Order__c firstOrder = WarehouseTestDataFactory.createOutboundOrder(scenario, 'AUTO-1001', 12);
        Outbound_Order__c secondOrder = WarehouseTestDataFactory.createOutboundOrder(scenario, 'AUTO-1002', 8);

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
        System.assertEquals(20, [SELECT Reserved__c FROM Inventory__c WHERE Product__c = :scenario.product.Id LIMIT 1].Reserved__c);
        System.assertEquals(2, [SELECT COUNT() FROM Pick_Task__c]);
    }

    @IsTest
    static void recordTriggeredFlowAllocatesWhenOrderBecomesReady() {
        WarehouseTestDataFactory.CoreScenario scenario = WarehouseTestDataFactory.createCoreScenario('AUTO', 50);
        Outbound_Order__c orderRecord = WarehouseTestDataFactory.createOutboundOrder(scenario, 'AUTO-FLOW-01', 10);

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
        WarehouseTestDataFactory.CoreScenario scenario = WarehouseTestDataFactory.createCoreScenario('AUTO', 50);
        Outbound_Order__c orderRecord = WarehouseTestDataFactory.createOutboundOrder(scenario, 'AUTO-FAIL-01', 80);

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
