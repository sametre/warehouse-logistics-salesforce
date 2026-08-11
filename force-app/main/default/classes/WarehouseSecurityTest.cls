@IsTest
private class WarehouseSecurityTest {
    @TestSetup
    static void setupBusinessData() {
        WarehouseTestDataFactory.createCoreScenario('SEC', 40);
    }

    @IsTest
    static void minimumAccessUserCannotReadWarehouseInventory() {
        Warehouse__c warehouse = [SELECT Id FROM Warehouse__c WHERE Code__c = 'SEC-DC' LIMIT 1];
        User restrictedUser = WarehouseTestDataFactory.createMinimumAccessUser('none');

        System.runAs(restrictedUser) {
            Test.startTest();
            Boolean denied = false;
            try {
                WarehouseInventorySelector.selectInventory(warehouse.Id, 25);
            } catch (QueryException expected) {
                denied = true;
            }
            Test.stopTest();
            System.assertEquals(true, denied, 'User-mode SOQL must reject a user with no warehouse object access.');
        }
    }

    @IsTest
    static void pickerPermissionExposesOnlyPickerCapabilities() {
        User picker = WarehouseTestDataFactory.createMinimumAccessUser('picker');
        WarehouseTestDataFactory.assignPermissionSet(picker.Id, 'Warehouse_Picker');

        System.runAs(picker) {
            System.assertEquals(true, Schema.sObjectType.Warehouse__c.isAccessible());
            System.assertEquals(true, Schema.sObjectType.Inventory__c.isAccessible());
            System.assertEquals(true, Schema.sObjectType.Inventory__c.isUpdateable());
            System.assertEquals(true, Schema.sObjectType.Pick_Task__c.isCreateable());
            System.assertEquals(true, Schema.sObjectType.Pick_Task__c.isUpdateable());
            System.assertEquals(false, Schema.sObjectType.Shipment__c.isCreateable());
            System.assertEquals(false, Schema.sObjectType.Outbound_Order__c.fields.Shipping_Address_Validated__c.getDescribe().isUpdateable());
            System.assertEquals(false, Schema.sObjectType.Receiving_Task__c.isCreateable());
        }
    }

    @IsTest
    static void logisticsPermissionCanShipWithoutInventoryWriteAccess() {
        User coordinator = WarehouseTestDataFactory.createMinimumAccessUser('logistics');
        WarehouseTestDataFactory.assignPermissionSet(coordinator.Id, 'Logistics_Coordinator');

        System.runAs(coordinator) {
            System.assertEquals(true, Schema.sObjectType.Shipment__c.isAccessible());
            System.assertEquals(true, Schema.sObjectType.Shipment__c.isCreateable());
            System.assertEquals(true, Schema.sObjectType.Shipment__c.isUpdateable());
            System.assertEquals(false, Schema.sObjectType.Inventory__c.isUpdateable());
            System.assertEquals(true, Schema.sObjectType.Outbound_Order__c.fields.Shipping_Address_Validated__c.getDescribe().isUpdateable());
            System.assertEquals(false, Schema.sObjectType.Receiving_Task__c.isCreateable());
        }
    }
}
