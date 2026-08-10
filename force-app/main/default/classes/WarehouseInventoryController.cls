public with sharing class WarehouseInventoryController {
    public class InventoryRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String inventoryNumber;
        @AuraEnabled public String productName;
        @AuraEnabled public String binCode;
        @AuraEnabled public String warehouseName;
        @AuraEnabled public Decimal onHand;
        @AuraEnabled public Decimal reserved;
        @AuraEnabled public Decimal available;
        @AuraEnabled public String status;
    }

    public class InventorySummary {
        @AuraEnabled public Integer recordCount;
        @AuraEnabled public Decimal onHand;
        @AuraEnabled public Decimal reserved;
        @AuraEnabled public Decimal available;
        @AuraEnabled public Integer lowStockCount;
        @AuraEnabled public List<InventoryRow> rows;
    }

    @AuraEnabled(cacheable=true)
    public static InventorySummary getSummary(Id warehouseId) {
        List<Inventory__c> records = WarehouseInventoryService.getInventory(warehouseId, 100);
        InventorySummary summary = new InventorySummary();
        summary.recordCount = records.size();
        summary.onHand = 0;
        summary.reserved = 0;
        summary.available = 0;
        summary.lowStockCount = 0;
        summary.rows = new List<InventoryRow>();

        for (Inventory__c item : records) {
            Decimal onHand = item.On_Hand__c == null ? 0 : item.On_Hand__c;
            Decimal reserved = item.Reserved__c == null ? 0 : item.Reserved__c;
            Decimal available = item.Available__c == null ? onHand - reserved : item.Available__c;

            summary.onHand += onHand;
            summary.reserved += reserved;
            summary.available += available;
            if (item.Status__c == 'Low Stock' || item.Status__c == 'Out of Stock') {
                summary.lowStockCount++;
            }

            InventoryRow row = new InventoryRow();
            row.id = item.Id;
            row.inventoryNumber = item.Name;
            row.productName = item.Product__r == null ? null : item.Product__r.Name;
            row.binCode = item.Bin_Location__r == null ? null : item.Bin_Location__r.Bin_Code__c;
            row.warehouseName = item.Bin_Location__r == null || item.Bin_Location__r.Warehouse__r == null
                ? null : item.Bin_Location__r.Warehouse__r.Name;
            row.onHand = onHand;
            row.reserved = reserved;
            row.available = available;
            row.status = item.Status__c;
            summary.rows.add(row);
        }
        return summary;
    }
}
