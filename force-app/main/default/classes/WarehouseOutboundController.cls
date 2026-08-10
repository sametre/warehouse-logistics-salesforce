public with sharing class WarehouseOutboundController {
    public class OrderRow {
        @AuraEnabled public Id orderId;
        @AuraEnabled public String orderNumber;
        @AuraEnabled public String customerName;
        @AuraEnabled public Id warehouseId;
        @AuraEnabled public String warehouseName;
        @AuraEnabled public String status;
        @AuraEnabled public String priority;
        @AuraEnabled public Date requiredShipDate;
    }

    public class PickRow {
        @AuraEnabled public Id taskId;
        @AuraEnabled public String taskNumber;
        @AuraEnabled public String orderNumber;
        @AuraEnabled public Id warehouseId;
        @AuraEnabled public String warehouseName;
        @AuraEnabled public String productName;
        @AuraEnabled public String sourceBin;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal pickedQuantity;
        @AuraEnabled public Decimal remainingQuantity;
        @AuraEnabled public String status;
    }

    public class PackRow {
        @AuraEnabled public Id orderId;
        @AuraEnabled public String orderNumber;
        @AuraEnabled public Id warehouseId;
        @AuraEnabled public String warehouseName;
        @AuraEnabled public String customerName;
        @AuraEnabled public String priority;
        @AuraEnabled public Date requiredShipDate;
    }

    public class ShipRow {
        @AuraEnabled public Id packageId;
        @AuraEnabled public String packageNumber;
        @AuraEnabled public Id orderId;
        @AuraEnabled public String orderNumber;
        @AuraEnabled public Id warehouseId;
        @AuraEnabled public String warehouseName;
        @AuraEnabled public Decimal weight;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime packedAt;
    }

    @AuraEnabled(cacheable=true)
    public static List<OrderRow> getAllocationQueue(Id warehouseId) {
        List<Outbound_Order__c> orders;
        if (warehouseId == null) {
            orders = [
                SELECT Id, Name, Customer__r.Name, Warehouse__c, Warehouse__r.Name,
                       Status__c, Priority__c, Required_Ship_Date__c
                FROM Outbound_Order__c
                WHERE Status__c IN ('Draft', 'Ready to Allocate')
                WITH USER_MODE
                ORDER BY Priority__c DESC, Required_Ship_Date__c, CreatedDate
                LIMIT 200
            ];
        } else {
            orders = [
                SELECT Id, Name, Customer__r.Name, Warehouse__c, Warehouse__r.Name,
                       Status__c, Priority__c, Required_Ship_Date__c
                FROM Outbound_Order__c
                WHERE Warehouse__c = :warehouseId AND Status__c IN ('Draft', 'Ready to Allocate')
                WITH USER_MODE
                ORDER BY Priority__c DESC, Required_Ship_Date__c, CreatedDate
                LIMIT 200
            ];
        }
        return mapOrders(orders);
    }

    @AuraEnabled(cacheable=true)
    public static List<PickRow> getPickingQueue(Id warehouseId) {
        List<Pick_Task__c> tasks;
        if (warehouseId == null) {
            tasks = [
                SELECT Id, Name, Outbound_Order__r.Name, Warehouse__c, Warehouse__r.Name,
                       Product__r.Name, Source_Bin__r.Bin_Code__c,
                       Quantity__c, Picked_Quantity__c, Status__c
                FROM Pick_Task__c
                WHERE Status__c IN ('Open', 'In Progress')
                WITH USER_MODE
                ORDER BY CreatedDate
                LIMIT 300
            ];
        } else {
            tasks = [
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

        List<PickRow> rows = new List<PickRow>();
        for (Pick_Task__c task : tasks) {
            Decimal taskQuantity = task.Quantity__c == null ? 0 : task.Quantity__c;
            Decimal picked = task.Picked_Quantity__c == null ? 0 : task.Picked_Quantity__c;
            PickRow row = new PickRow();
            row.taskId = task.Id;
            row.taskNumber = task.Name;
            row.orderNumber = task.Outbound_Order__r == null ? null : task.Outbound_Order__r.Name;
            row.warehouseId = task.Warehouse__c;
            row.warehouseName = task.Warehouse__r == null ? null : task.Warehouse__r.Name;
            row.productName = task.Product__r == null ? null : task.Product__r.Name;
            row.sourceBin = task.Source_Bin__r == null ? null : task.Source_Bin__r.Bin_Code__c;
            row.quantity = taskQuantity;
            row.pickedQuantity = picked;
            row.remainingQuantity = taskQuantity - picked;
            row.status = task.Status__c;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static List<PackRow> getPackingQueue(Id warehouseId) {
        List<Outbound_Order__c> orders;
        if (warehouseId == null) {
            orders = [
                SELECT Id, Name, Customer__r.Name, Warehouse__c, Warehouse__r.Name,
                       Priority__c, Required_Ship_Date__c
                FROM Outbound_Order__c
                WHERE Status__c = 'Packing'
                WITH USER_MODE
                ORDER BY Required_Ship_Date__c, CreatedDate
                LIMIT 200
            ];
        } else {
            orders = [
                SELECT Id, Name, Customer__r.Name, Warehouse__c, Warehouse__r.Name,
                       Priority__c, Required_Ship_Date__c
                FROM Outbound_Order__c
                WHERE Warehouse__c = :warehouseId AND Status__c = 'Packing'
                WITH USER_MODE
                ORDER BY Required_Ship_Date__c, CreatedDate
                LIMIT 200
            ];
        }

        List<PackRow> rows = new List<PackRow>();
        for (Outbound_Order__c orderRecord : orders) {
            PackRow row = new PackRow();
            row.orderId = orderRecord.Id;
            row.orderNumber = orderRecord.Name;
            row.warehouseId = orderRecord.Warehouse__c;
            row.warehouseName = orderRecord.Warehouse__r == null ? null : orderRecord.Warehouse__r.Name;
            row.customerName = orderRecord.Customer__r == null ? null : orderRecord.Customer__r.Name;
            row.priority = orderRecord.Priority__c;
            row.requiredShipDate = orderRecord.Required_Ship_Date__c;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static List<ShipRow> getShippingQueue(Id warehouseId) {
        List<Package__c> packages;
        if (warehouseId == null) {
            packages = [
                SELECT Id, Name, Outbound_Order__c, Outbound_Order__r.Name,
                       Warehouse__c, Warehouse__r.Name, Weight__c, Status__c, Packed_At__c
                FROM Package__c
                WHERE Status__c = 'Ready to Ship'
                WITH USER_MODE
                ORDER BY Packed_At__c, CreatedDate
                LIMIT 200
            ];
        } else {
            packages = [
                SELECT Id, Name, Outbound_Order__c, Outbound_Order__r.Name,
                       Warehouse__c, Warehouse__r.Name, Weight__c, Status__c, Packed_At__c
                FROM Package__c
                WHERE Warehouse__c = :warehouseId AND Status__c = 'Ready to Ship'
                WITH USER_MODE
                ORDER BY Packed_At__c, CreatedDate
                LIMIT 200
            ];
        }

        List<ShipRow> rows = new List<ShipRow>();
        for (Package__c packageRecord : packages) {
            ShipRow row = new ShipRow();
            row.packageId = packageRecord.Id;
            row.packageNumber = packageRecord.Name;
            row.orderId = packageRecord.Outbound_Order__c;
            row.orderNumber = packageRecord.Outbound_Order__r == null ? null : packageRecord.Outbound_Order__r.Name;
            row.warehouseId = packageRecord.Warehouse__c;
            row.warehouseName = packageRecord.Warehouse__r == null ? null : packageRecord.Warehouse__r.Name;
            row.weight = packageRecord.Weight__c;
            row.status = packageRecord.Status__c;
            row.packedAt = packageRecord.Packed_At__c;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static WarehouseOutboundService.AllocationResult allocateOrder(Id orderId) {
        return WarehouseOutboundService.allocateOrder(orderId);
    }

    @AuraEnabled
    public static WarehousePickingService.PickingResult completePick(Id pickTaskId, Decimal quantity, String notes) {
        return WarehousePickingService.completePick(pickTaskId, quantity, notes);
    }

    @AuraEnabled
    public static Id packOrder(Id orderId, Decimal weight, String notes) {
        return WarehouseShippingService.packOrder(orderId, weight, notes).Id;
    }

    @AuraEnabled
    public static Id shipPackage(Id packageId, String carrier, String trackingNumber, String notes) {
        return WarehouseShippingService.shipPackage(packageId, carrier, trackingNumber, notes).Id;
    }

    private static List<OrderRow> mapOrders(List<Outbound_Order__c> orders) {
        List<OrderRow> rows = new List<OrderRow>();
        for (Outbound_Order__c orderRecord : orders) {
            OrderRow row = new OrderRow();
            row.orderId = orderRecord.Id;
            row.orderNumber = orderRecord.Name;
            row.customerName = orderRecord.Customer__r == null ? null : orderRecord.Customer__r.Name;
            row.warehouseId = orderRecord.Warehouse__c;
            row.warehouseName = orderRecord.Warehouse__r == null ? null : orderRecord.Warehouse__r.Name;
            row.status = orderRecord.Status__c;
            row.priority = orderRecord.Priority__c;
            row.requiredShipDate = orderRecord.Required_Ship_Date__c;
            rows.add(row);
        }
        return rows;
    }
}
