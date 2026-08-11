@IsTest
public class WarehouseTestDataFactory {
    public class CoreScenario {
        public Warehouse__c warehouse;
        public Bin_Location__c receivingBin;
        public Bin_Location__c pickingBin;
        public Product2 product;
        public Inventory__c inventory;
        public Account customer;
    }

    public static CoreScenario createCoreScenario(String prefix, Decimal onHand) {
        String key = String.isBlank(prefix) ? 'TEST' : prefix;

        CoreScenario scenario = new CoreScenario();
        scenario.warehouse = new Warehouse__c(
            Name = key + ' Distribution Center',
            Code__c = key + '-DC',
            City__c = 'Bursa',
            Is_Active__c = true
        );
        insert scenario.warehouse;

        scenario.receivingBin = new Bin_Location__c(
            Name = key + ' Receiving',
            Warehouse__c = scenario.warehouse.Id,
            Bin_Code__c = key + '-REC-01',
            Bin_Type__c = 'Receiving',
            Capacity__c = 1000,
            Is_Active__c = true
        );
        scenario.pickingBin = new Bin_Location__c(
            Name = key + ' Picking',
            Warehouse__c = scenario.warehouse.Id,
            Bin_Code__c = key + '-PICK-01',
            Bin_Type__c = 'Picking',
            Capacity__c = 1000,
            Is_Active__c = true
        );
        insert new List<Bin_Location__c>{ scenario.receivingBin, scenario.pickingBin };

        scenario.product = new Product2(
            Name = key + ' Product',
            ProductCode = key + '-SKU',
            IsActive = true
        );
        insert scenario.product;

        scenario.inventory = new Inventory__c(
            Product__c = scenario.product.Id,
            Bin_Location__c = scenario.pickingBin.Id,
            On_Hand__c = onHand,
            Reserved__c = 0,
            Reorder_Level__c = 5,
            Status__c = onHand > 0 ? 'Available' : 'Out of Stock'
        );
        insert scenario.inventory;

        scenario.customer = new Account(Name = key + ' Customer');
        insert scenario.customer;
        return scenario;
    }

    public static Outbound_Order__c createOutboundOrder(
        CoreScenario scenario,
        String externalReference,
        Decimal quantity
    ) {
        Outbound_Order__c orderRecord = new Outbound_Order__c(
            Warehouse__c = scenario.warehouse.Id,
            Customer__c = scenario.customer.Id,
            Status__c = 'Draft',
            Priority__c = 'Normal',
            Order_Date__c = Date.today(),
            Required_Ship_Date__c = Date.today().addDays(2),
            External_Order_Reference__c = externalReference,
            Shipping_Country_Code__c = 'US',
            Shipping_Postal_Code__c = '90210'
        );
        insert orderRecord;

        insert new Outbound_Order_Line__c(
            Outbound_Order__c = orderRecord.Id,
            Product__c = scenario.product.Id,
            Ordered_Quantity__c = quantity,
            Allocated_Quantity__c = 0,
            Picked_Quantity__c = 0,
            Packed_Quantity__c = 0,
            Status__c = 'Pending'
        );
        return orderRecord;
    }

    public static User createMinimumAccessUser(String seed) {
        Profile minimumAccess = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Minimum Access - Salesforce'
            LIMIT 1
        ];
        String unique = String.valueOf(DateTime.now().getTime()) + '-' + seed;
        User userRecord = new User(
            Alias = 'whsec',
            Email = 'warehouse.' + unique + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Warehouse ' + seed,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = minimumAccess.Id,
            TimeZoneSidKey = 'Europe/Istanbul',
            Username = 'warehouse.' + unique + '@example.invalid'
        );
        insert userRecord;
        return userRecord;
    }

    public static void assignPermissionSet(Id userId, String permissionSetName) {
        PermissionSet permission = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :permissionSetName
            LIMIT 1
        ];
        insert new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetId = permission.Id
        );
    }
}
