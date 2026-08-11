public with sharing class WarehouseInboundSelector {
    public static Inbound_Shipment_Line__c selectShipmentLineForUpdate(Id shipmentLineId) {
        List<Inbound_Shipment_Line__c> records = [
            SELECT Id, Product__c, Expected_Quantity__c, Received_Quantity__c, Damaged_Quantity__c,
                   Inbound_Shipment__c, Inbound_Shipment__r.Name, Inbound_Shipment__r.Status__c,
                   Inbound_Shipment__r.Warehouse__c
            FROM Inbound_Shipment_Line__c
            WHERE Id = :shipmentLineId
            WITH USER_MODE
            LIMIT 1
            FOR UPDATE
        ];
        return records.isEmpty() ? null : records[0];
    }

    public static Bin_Location__c selectBin(Id binLocationId) {
        List<Bin_Location__c> records = [
            SELECT Id, Bin_Code__c, Warehouse__c, Warehouse__r.Name, Is_Active__c, Bin_Type__c
            FROM Bin_Location__c
            WHERE Id = :binLocationId
            WITH USER_MODE
            LIMIT 1
        ];
        return records.isEmpty() ? null : records[0];
    }

    public static Putaway_Task__c selectPutawayTaskForUpdate(Id putawayTaskId) {
        List<Putaway_Task__c> records = [
            SELECT Id, Name, Status__c, Product__c, Warehouse__c, Source_Bin__c,
                   Suggested_Bin__c, Destination_Bin__c, Quantity__c, Inbound_Shipment__c
            FROM Putaway_Task__c
            WHERE Id = :putawayTaskId
            WITH USER_MODE
            LIMIT 1
            FOR UPDATE
        ];
        return records.isEmpty() ? null : records[0];
    }

    public static Id selectSuggestedPutawayBin(Id warehouseId, Id sourceBinId) {
        List<Bin_Location__c> bins = [
            SELECT Id
            FROM Bin_Location__c
            WHERE Warehouse__c = :warehouseId
              AND Is_Active__c = true
              AND Id != :sourceBinId
              AND Bin_Type__c IN ('Storage', 'Picking')
            WITH USER_MODE
            ORDER BY Bin_Type__c, Bin_Code__c
            LIMIT 1
        ];
        return bins.isEmpty() ? null : bins[0].Id;
    }

    public static List<Inbound_Shipment_Line__c> selectShipmentLines(Id shipmentId) {
        return [
            SELECT Expected_Quantity__c, Received_Quantity__c
            FROM Inbound_Shipment_Line__c
            WHERE Inbound_Shipment__c = :shipmentId
            WITH USER_MODE
        ];
    }

    public static Integer countReceivingExceptions(Id shipmentId) {
        return [
            SELECT COUNT()
            FROM Receiving_Task__c
            WHERE Inbound_Shipment__c = :shipmentId AND Status__c = 'Exception'
            WITH USER_MODE
        ];
    }

    public static Integer countOpenPutawayTasks(Id shipmentId) {
        return [
            SELECT COUNT()
            FROM Putaway_Task__c
            WHERE Inbound_Shipment__c = :shipmentId AND Status__c != 'Completed'
            WITH USER_MODE
        ];
    }

    public static List<Inbound_Shipment_Line__c> selectReceivingQueue(Id warehouseId) {
        if (warehouseId == null) {
            return [
                SELECT Id, Product__r.Name, Expected_Quantity__c, Received_Quantity__c,
                       Inbound_Shipment__r.Name, Inbound_Shipment__r.Status__c,
                       Inbound_Shipment__r.Expected_Date__c, Inbound_Shipment__r.Supplier__r.Name,
                       Inbound_Shipment__r.Warehouse__c, Inbound_Shipment__r.Warehouse__r.Name
                FROM Inbound_Shipment_Line__c
                WHERE Inbound_Shipment__r.Status__c IN ('Expected', 'Receiving', 'Exception')
                WITH USER_MODE
                ORDER BY Inbound_Shipment__r.Expected_Date__c, CreatedDate
                LIMIT 200
            ];
        }

        return [
            SELECT Id, Product__r.Name, Expected_Quantity__c, Received_Quantity__c,
                   Inbound_Shipment__r.Name, Inbound_Shipment__r.Status__c,
                   Inbound_Shipment__r.Expected_Date__c, Inbound_Shipment__r.Supplier__r.Name,
                   Inbound_Shipment__r.Warehouse__c, Inbound_Shipment__r.Warehouse__r.Name
            FROM Inbound_Shipment_Line__c
            WHERE Inbound_Shipment__r.Warehouse__c = :warehouseId
              AND Inbound_Shipment__r.Status__c IN ('Expected', 'Receiving', 'Exception')
            WITH USER_MODE
            ORDER BY Inbound_Shipment__r.Expected_Date__c, CreatedDate
            LIMIT 200
        ];
    }

    public static List<Putaway_Task__c> selectPutawayQueue(Id warehouseId) {
        if (warehouseId == null) {
            return [
                SELECT Id, Name, Warehouse__c, Warehouse__r.Name, Product__r.Name,
                       Source_Bin__r.Bin_Code__c, Suggested_Bin__c, Suggested_Bin__r.Bin_Code__c,
                       Quantity__c, Status__c
                FROM Putaway_Task__c
                WHERE Status__c IN ('Open', 'In Progress')
                WITH USER_MODE
                ORDER BY CreatedDate
                LIMIT 200
            ];
        }

        return [
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

    public static List<Bin_Location__c> selectActiveBins(Id warehouseId) {
        if (warehouseId == null) {
            return [
                SELECT Id, Bin_Code__c, Bin_Type__c, Warehouse__c, Warehouse__r.Name
                FROM Bin_Location__c
                WHERE Is_Active__c = true
                WITH USER_MODE
                ORDER BY Warehouse__r.Name, Bin_Type__c, Bin_Code__c
                LIMIT 300
            ];
        }

        return [
            SELECT Id, Bin_Code__c, Bin_Type__c, Warehouse__c, Warehouse__r.Name
            FROM Bin_Location__c
            WHERE Is_Active__c = true AND Warehouse__c = :warehouseId
            WITH USER_MODE
            ORDER BY Bin_Type__c, Bin_Code__c
            LIMIT 300
        ];
    }
}
