public with sharing class WarehouseOperationsController {
    public class BinOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
        @AuraEnabled public String type;
        @AuraEnabled public Id warehouseId;
    }

    public class ReceivingRow {
        @AuraEnabled public Id lineId;
        @AuraEnabled public String shipmentNumber;
        @AuraEnabled public String supplierName;
        @AuraEnabled public Id warehouseId;
        @AuraEnabled public String warehouseName;
        @AuraEnabled public String productName;
        @AuraEnabled public Decimal expectedQuantity;
        @AuraEnabled public Decimal receivedQuantity;
        @AuraEnabled public Decimal remainingQuantity;
        @AuraEnabled public String shipmentStatus;
        @AuraEnabled public Date expectedDate;
    }

    public class PutawayRow {
        @AuraEnabled public Id taskId;
        @AuraEnabled public String taskNumber;
        @AuraEnabled public Id warehouseId;
        @AuraEnabled public String warehouseName;
        @AuraEnabled public String productName;
        @AuraEnabled public String sourceBin;
        @AuraEnabled public Id suggestedBinId;
        @AuraEnabled public String suggestedBin;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public String status;
    }

    @AuraEnabled(cacheable=true)
    public static List<ReceivingRow> getReceivingQueue(Id warehouseId) {
        List<Inbound_Shipment_Line__c> lines;
        if (warehouseId == null) {
            lines = [
                SELECT Id, Product__r.Name, Expected_Quantity__c, Received_Quantity__c,
                       Inbound_Shipment__r.Name, Inbound_Shipment__r.Status__c,
                       Inbound_Shipment__r.Expected_Date__c, Inbound_Shipment__r.Supplier__r.Name,
                       Inbound_Shipment__r.Warehouse__c, Inbound_Shipment__r.Warehouse__r.Name
                FROM Inbound_Shipment_Line__c
                WHERE Inbound_Shipment__r.Status__c IN ('Expected', 'Receiving')
                WITH USER_MODE
                ORDER BY Inbound_Shipment__r.Expected_Date__c, CreatedDate
                LIMIT 200
            ];
        } else {
            lines = [
                SELECT Id, Product__r.Name, Expected_Quantity__c, Received_Quantity__c,
                       Inbound_Shipment__r.Name, Inbound_Shipment__r.Status__c,
                       Inbound_Shipment__r.Expected_Date__c, Inbound_Shipment__r.Supplier__r.Name,
                       Inbound_Shipment__r.Warehouse__c, Inbound_Shipment__r.Warehouse__r.Name
                FROM Inbound_Shipment_Line__c
                WHERE Inbound_Shipment__r.Warehouse__c = :warehouseId
                  AND Inbound_Shipment__r.Status__c IN ('Expected', 'Receiving')
                WITH USER_MODE
                ORDER BY Inbound_Shipment__r.Expected_Date__c, CreatedDate
                LIMIT 200
            ];
        }

        List<ReceivingRow> result = new List<ReceivingRow>();
        for (Inbound_Shipment_Line__c line : lines) {
            Decimal expected = line.Expected_Quantity__c == null ? 0 : line.Expected_Quantity__c;
            Decimal received = line.Received_Quantity__c == null ? 0 : line.Received_Quantity__c;
            if (received >= expected) {
                continue;
            }

            ReceivingRow row = new ReceivingRow();
            row.lineId = line.Id;
            row.shipmentNumber = line.Inbound_Shipment__r.Name;
            row.supplierName = line.Inbound_Shipment__r.Supplier__r == null ? null : line.Inbound_Shipment__r.Supplier__r.Name;
            row.warehouseId = line.Inbound_Shipment__r.Warehouse__c;
            row.warehouseName = line.Inbound_Shipment__r.Warehouse__r == null ? null : line.Inbound_Shipment__r.Warehouse__r.Name;
            row.productName = line.Product__r == null ? null : line.Product__r.Name;
            row.expectedQuantity = expected;
            row.receivedQuantity = received;
            row.remainingQuantity = expected - received;
            row.shipmentStatus = line.Inbound_Shipment__r.Status__c;
            row.expectedDate = line.Inbound_Shipment__r.Expected_Date__c;
            result.add(row);
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<PutawayRow> getPutawayQueue(Id warehouseId) {
        List<Putaway_Task__c> tasks;
        if (warehouseId == null) {
            tasks = [
                SELECT Id, Name, Warehouse__c, Warehouse__r.Name, Product__r.Name,
                       Source_Bin__r.Bin_Code__c, Suggested_Bin__c, Suggested_Bin__r.Bin_Code__c,
                       Quantity__c, Status__c
                FROM Putaway_Task__c
                WHERE Status__c IN ('Open', 'In Progress')
                WITH USER_MODE
                ORDER BY CreatedDate
                LIMIT 200
            ];
        } else {
            tasks = [
                SELECT Id, Name, Warehouse__c, Warehouse__r.Name, Product__r.Name,
                       Source_Bin__r.Bin_Code__c, Suggested_Bin__c, Suggested_Bin__r.Bin_Code__c,
                       Quantity__c, Status__c
                FROM Putaway_Task__c
                WHERE Warehouse__c = :warehouseId AND Status__c IN ('Open', 'In Progress')
                WITH USER_MODE
                ORDER BY CreatedDate
                LIMIT 200
            ];
        }

        List<PutawayRow> result = new List<PutawayRow>();
        for (Putaway_Task__c task : tasks) {
            PutawayRow row = new PutawayRow();
            row.taskId = task.Id;
            row.taskNumber = task.Name;
            row.warehouseId = task.Warehouse__c;
            row.warehouseName = task.Warehouse__r == null ? null : task.Warehouse__r.Name;
            row.productName = task.Product__r == null ? null : task.Product__r.Name;
            row.sourceBin = task.Source_Bin__r == null ? null : task.Source_Bin__r.Bin_Code__c;
            row.suggestedBinId = task.Suggested_Bin__c;
            row.suggestedBin = task.Suggested_Bin__r == null ? null : task.Suggested_Bin__r.Bin_Code__c;
            row.quantity = task.Quantity__c;
            row.status = task.Status__c;
            result.add(row);
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<BinOption> getActiveBins(Id warehouseId) {
        List<Bin_Location__c> bins;
        if (warehouseId == null) {
            bins = [
                SELECT Id, Bin_Code__c, Bin_Type__c, Warehouse__c, Warehouse__r.Name
                FROM Bin_Location__c
                WHERE Is_Active__c = true
                WITH USER_MODE
                ORDER BY Warehouse__r.Name, Bin_Type__c, Bin_Code__c
                LIMIT 300
            ];
        } else {
            bins = [
                SELECT Id, Bin_Code__c, Bin_Type__c, Warehouse__c, Warehouse__r.Name
                FROM Bin_Location__c
                WHERE Is_Active__c = true AND Warehouse__c = :warehouseId
                WITH USER_MODE
                ORDER BY Bin_Type__c, Bin_Code__c
                LIMIT 300
            ];
        }

        List<BinOption> result = new List<BinOption>();
        for (Bin_Location__c bin : bins) {
            BinOption option = new BinOption();
            option.id = bin.Id;
            option.label = (bin.Warehouse__r == null ? '' : bin.Warehouse__r.Name + ' · ') + bin.Bin_Code__c;
            option.type = bin.Bin_Type__c;
            option.warehouseId = bin.Warehouse__c;
            result.add(option);
        }
        return result;
    }

    @AuraEnabled
    public static WarehouseReceivingService.ReceivingResult receiveLine(
        Id shipmentLineId,
        Id receivingBinId,
        Decimal receivedQuantity,
        Decimal damagedQuantity,
        String notes
    ) {
        return WarehouseReceivingService.receiveLine(
            shipmentLineId,
            receivingBinId,
            receivedQuantity,
            damagedQuantity,
            notes
        );
    }

    @AuraEnabled
    public static void completePutaway(Id putawayTaskId, Id destinationBinId, String notes) {
        WarehousePutawayService.completePutaway(putawayTaskId, destinationBinId, notes);
    }
}
