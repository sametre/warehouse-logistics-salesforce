public with sharing class WarehouseOutboundSelector {
    public static List<Outbound_Order__c> selectOrdersForUpdate(Set<Id> orderIds) {
        if (orderIds == null || orderIds.isEmpty()) {
            return new List<Outbound_Order__c>();
        }
        return [
            SELECT Id, Name, Warehouse__c, Status__c, CreatedDate
            FROM Outbound_Order__c
            WHERE Id IN :orderIds
            WITH USER_MODE
            FOR UPDATE
        ];
    }

    public static List<Outbound_Order_Line__c> selectLinesForUpdate(Set<Id> orderIds) {
        if (orderIds == null || orderIds.isEmpty()) {
            return new List<Outbound_Order_Line__c>();
        }
        return [
            SELECT Id, Outbound_Order__c, Product__c, Ordered_Quantity__c,
                   Allocated_Quantity__c, Picked_Quantity__c, Packed_Quantity__c,
                   Status__c, CreatedDate
            FROM Outbound_Order_Line__c
            WHERE Outbound_Order__c IN :orderIds AND Status__c != 'Cancelled'
            WITH USER_MODE
            FOR UPDATE
        ];
    }

    public static Pick_Task__c selectPickTaskForUpdate(Id pickTaskId) {
        List<Pick_Task__c> records = [
            SELECT Id, Name, Outbound_Order__c, Outbound_Order_Line__c, Product__c, Source_Bin__c,
                   Quantity__c, Picked_Quantity__c, Status__c, Notes__c
            FROM Pick_Task__c
            WHERE Id = :pickTaskId
            WITH USER_MODE
            LIMIT 1
            FOR UPDATE
        ];
        return records.isEmpty() ? null : records[0];
    }

    public static Outbound_Order_Line__c selectOrderLineForUpdate(Id orderLineId) {
        List<Outbound_Order_Line__c> records = [
            SELECT Id, Allocated_Quantity__c, Picked_Quantity__c, Packed_Quantity__c, Status__c
            FROM Outbound_Order_Line__c
            WHERE Id = :orderLineId
            WITH USER_MODE
            LIMIT 1
            FOR UPDATE
        ];
        return records.isEmpty() ? null : records[0];
    }

    public static List<Outbound_Order_Line__c> selectOrderLines(Id orderId) {
        return [
            SELECT Id, Ordered_Quantity__c, Allocated_Quantity__c, Picked_Quantity__c,
                   Packed_Quantity__c, Status__c
            FROM Outbound_Order_Line__c
            WHERE Outbound_Order__c = :orderId AND Status__c != 'Cancelled'
            WITH USER_MODE
        ];
    }

    public static List<Outbound_Order_Line__c> selectOrderLinesForUpdate(Id orderId) {
        return [
            SELECT Id, Ordered_Quantity__c, Allocated_Quantity__c, Picked_Quantity__c,
                   Packed_Quantity__c, Status__c
            FROM Outbound_Order_Line__c
            WHERE Outbound_Order__c = :orderId AND Status__c != 'Cancelled'
            WITH USER_MODE
            FOR UPDATE
        ];
    }

    public static Outbound_Order__c selectOrderForUpdate(Id orderId) {
        List<Outbound_Order__c> records = [
            SELECT Id, Name, Warehouse__c, Status__c, Shipping_Address_Validated__c,
                   Shipping_Country_Code__c, Shipping_Postal_Code__c,
                   Shipping_Validated_Country_Code__c, Shipping_Validated_Postal_Code__c
            FROM Outbound_Order__c
            WHERE Id = :orderId
            WITH USER_MODE
            LIMIT 1
            FOR UPDATE
        ];
        return records.isEmpty() ? null : records[0];
    }


    public static Outbound_Order__c selectOrderDestination(Id orderId) {
        List<Outbound_Order__c> records = [
            SELECT Id, Shipping_Country_Code__c, Shipping_Postal_Code__c,
                   Shipping_City__c, Shipping_Region__c, Shipping_Latitude__c,
                   Shipping_Longitude__c, Shipping_Address_Validated__c,
                   Shipping_Address_Validated_At__c, Shipping_Address_Source__c,
                   Shipping_Validated_Country_Code__c, Shipping_Validated_Postal_Code__c
            FROM Outbound_Order__c
            WHERE Id = :orderId
            WITH USER_MODE
            LIMIT 1
        ];
        return records.isEmpty() ? null : records[0];
    }

    public static Outbound_Order__c selectOrderDestinationForUpdate(Id orderId) {
        List<Outbound_Order__c> records = [
            SELECT Id, Shipping_Country_Code__c, Shipping_Postal_Code__c,
                   Shipping_City__c, Shipping_Region__c, Shipping_Latitude__c,
                   Shipping_Longitude__c, Shipping_Address_Validated__c,
                   Shipping_Address_Validated_At__c, Shipping_Address_Source__c,
                   Shipping_Validated_Country_Code__c, Shipping_Validated_Postal_Code__c
            FROM Outbound_Order__c
            WHERE Id = :orderId
            WITH USER_MODE
            LIMIT 1
            FOR UPDATE
        ];
        return records.isEmpty() ? null : records[0];
    }

    public static List<Package__c> selectActivePackages(Id orderId) {
        return [
            SELECT Id
            FROM Package__c
            WHERE Outbound_Order__c = :orderId AND Status__c != 'Cancelled'
            WITH USER_MODE
            LIMIT 1
        ];
    }

    public static Package__c selectPackageForUpdate(Id packageId) {
        List<Package__c> records = [
            SELECT Id, Name, Outbound_Order__c, Warehouse__c, Status__c
            FROM Package__c
            WHERE Id = :packageId
            WITH USER_MODE
            LIMIT 1
            FOR UPDATE
        ];
        return records.isEmpty() ? null : records[0];
    }

    public static List<Shipment__c> selectActiveShipments(Id packageId) {
        return [
            SELECT Id
            FROM Shipment__c
            WHERE Package__c = :packageId AND Status__c != 'Cancelled'
            WITH USER_MODE
            LIMIT 1
        ];
    }

    public static List<Outbound_Order__c> selectAllocationQueue(Id warehouseId) {
        if (warehouseId == null) {
            return [
                SELECT Id, Name, Customer__r.Name, Warehouse__c, Warehouse__r.Name,
                       Status__c, Priority__c, Required_Ship_Date__c
                FROM Outbound_Order__c
                WHERE Status__c IN ('Draft', 'Ready to Allocate')
                WITH USER_MODE
                ORDER BY Priority__c DESC, Required_Ship_Date__c, CreatedDate
                LIMIT 200
            ];
        }
        return [
            SELECT Id, Name, Customer__r.Name, Warehouse__c, Warehouse__r.Name,
                   Status__c, Priority__c, Required_Ship_Date__c
            FROM Outbound_Order__c
            WHERE Warehouse__c = :warehouseId AND Status__c IN ('Draft', 'Ready to Allocate')
            WITH USER_MODE
            ORDER BY Priority__c DESC, Required_Ship_Date__c, CreatedDate
            LIMIT 200
        ];
    }

    public static List<Pick_Task__c> selectPickingQueue(Id warehouseId) {
        if (warehouseId == null) {
            return [
                SELECT Id, Name, Outbound_Order__r.Name, Warehouse__c, Warehouse__r.Name,
                       Product__r.Name, Source_Bin__r.Bin_Code__c,
                       Quantity__c, Picked_Quantity__c, Status__c
                FROM Pick_Task__c
                WHERE Status__c IN ('Open', 'In Progress')
                WITH USER_MODE
                ORDER BY CreatedDate
                LIMIT 300
            ];
        }
        return [
            SELECT Id, Name, Outbound_Order__r.Name, Warehouse__c, Warehouse__r.Name,
                   Product__r.Name, Source_Bin__r.Bin_Code__c,
                   Quantity__c, Picked_Quantity__c, Status__c
            FROM Pick_Task__c
            WHERE Warehouse__c = :warehouseId AND Status__c IN ('Open', 'In Progress')
            WITH USER_MODE
            ORDER BY CreatedDate
            LIMIT 300
        ];
    }

    public static List<Outbound_Order__c> selectPackingQueue(Id warehouseId) {
        if (warehouseId == null) {
            return [
                SELECT Id, Name, Customer__r.Name, Warehouse__c, Warehouse__r.Name,
                       Priority__c, Required_Ship_Date__c
                FROM Outbound_Order__c
                WHERE Status__c = 'Packing'
                WITH USER_MODE
                ORDER BY Required_Ship_Date__c, CreatedDate
                LIMIT 200
            ];
        }
        return [
            SELECT Id, Name, Customer__r.Name, Warehouse__c, Warehouse__r.Name,
                   Priority__c, Required_Ship_Date__c
            FROM Outbound_Order__c
            WHERE Warehouse__c = :warehouseId AND Status__c = 'Packing'
            WITH USER_MODE
            ORDER BY Required_Ship_Date__c, CreatedDate
            LIMIT 200
        ];
    }

    public static List<Package__c> selectShippingQueue(Id warehouseId) {
        if (warehouseId == null) {
            return [
                SELECT Id, Name, Outbound_Order__c, Outbound_Order__r.Name,
                       Outbound_Order__r.Shipping_Country_Code__c,
                       Outbound_Order__r.Shipping_Postal_Code__c,
                       Outbound_Order__r.Shipping_City__c,
                       Outbound_Order__r.Shipping_Region__c,
                       Outbound_Order__r.Shipping_Address_Validated__c,
                       Outbound_Order__r.Shipping_Address_Validated_At__c,
                       Warehouse__c, Warehouse__r.Name, Weight__c, Status__c, Packed_At__c
                FROM Package__c
                WHERE Status__c = 'Ready to Ship'
                WITH USER_MODE
                ORDER BY Packed_At__c, CreatedDate
                LIMIT 200
            ];
        }
        return [
            SELECT Id, Name, Outbound_Order__c, Outbound_Order__r.Name,
                   Outbound_Order__r.Shipping_Country_Code__c,
                   Outbound_Order__r.Shipping_Postal_Code__c,
                   Outbound_Order__r.Shipping_City__c,
                   Outbound_Order__r.Shipping_Region__c,
                   Outbound_Order__r.Shipping_Address_Validated__c,
                   Outbound_Order__r.Shipping_Address_Validated_At__c,
                   Warehouse__c, Warehouse__r.Name, Weight__c, Status__c, Packed_At__c
            FROM Package__c
            WHERE Warehouse__c = :warehouseId AND Status__c = 'Ready to Ship'
            WITH USER_MODE
            ORDER BY Packed_At__c, CreatedDate
            LIMIT 200
        ];
    }
}
