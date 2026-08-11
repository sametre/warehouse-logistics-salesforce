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
        return mapOrders(WarehouseOutboundSelector.selectAllocationQueue(warehouseId));
    }

    @AuraEnabled(cacheable=true)
    public static List<PickRow> getPickingQueue(Id warehouseId) {
        List<Pick_Task__c> tasks = WarehouseOutboundSelector.selectPickingQueue(warehouseId);
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
        List<PackRow> rows = new List<PackRow>();
        for (Outbound_Order__c orderRecord : WarehouseOutboundSelector.selectPackingQueue(warehouseId)) {
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
        List<ShipRow> rows = new List<ShipRow>();
        for (Package__c packageRecord : WarehouseOutboundSelector.selectShippingQueue(warehouseId)) {
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
        Package__c packageRecord = WarehouseShippingService.packOrder(orderId, weight, notes);
        return packageRecord.Id;
    }

    @AuraEnabled
    public static Id shipPackage(Id packageId, String carrier, String trackingNumber, String notes) {
        Shipment__c shipment = WarehouseShippingService.shipPackage(packageId, carrier, trackingNumber, notes);
        return shipment.Id;
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
