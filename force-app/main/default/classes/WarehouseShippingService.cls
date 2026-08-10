public with sharing class WarehouseShippingService {
    public class ShippingException extends Exception {}

    public static Package__c packOrder(Id orderId, Decimal weight, String notes) {
        if (orderId == null) {
            throw new ShippingException('Outbound order is required.');
        }
        if (weight != null && weight < 0) {
            throw new ShippingException('Package weight cannot be negative.');
        }

        Outbound_Order__c orderRecord = [
            SELECT Id, Name, Warehouse__c, Status__c
            FROM Outbound_Order__c
            WHERE Id = :orderId
            WITH USER_MODE
            LIMIT 1
            FOR UPDATE
        ];
        if (orderRecord.Status__c != 'Packing') {
            throw new ShippingException('The order must finish picking before it can be packed.');
        }

        List<Outbound_Order_Line__c> lines = [
            SELECT Id, Ordered_Quantity__c, Picked_Quantity__c, Packed_Quantity__c, Status__c
            FROM Outbound_Order_Line__c
            WHERE Outbound_Order__c = :orderId AND Status__c != 'Cancelled'
            WITH USER_MODE
            FOR UPDATE
        ];
        if (lines.isEmpty()) {
            throw new ShippingException('No order lines were found.');
        }
        for (Outbound_Order_Line__c line : lines) {
            Decimal ordered = line.Ordered_Quantity__c == null ? 0 : line.Ordered_Quantity__c;
            Decimal picked = line.Picked_Quantity__c == null ? 0 : line.Picked_Quantity__c;
            if (ordered <= 0 || picked < ordered) {
                throw new ShippingException('All order lines must be fully picked before packing.');
            }
        }

        List<Package__c> existingPackages = [
            SELECT Id
            FROM Package__c
            WHERE Outbound_Order__c = :orderId AND Status__c != 'Cancelled'
            WITH USER_MODE
            LIMIT 1
        ];
        if (!existingPackages.isEmpty()) {
            throw new ShippingException('This order already has an active package.');
        }

        Package__c packageRecord = new Package__c(
            Outbound_Order__c = orderRecord.Id,
            Warehouse__c = orderRecord.Warehouse__c,
            Status__c = 'Ready to Ship',
            Weight__c = weight == null ? 0 : weight,
            Packed_At__c = System.now(),
            Packed_By__c = UserInfo.getUserId(),
            Notes__c = notes
        );
        Database.insert(packageRecord, AccessLevel.USER_MODE);

        for (Outbound_Order_Line__c line : lines) {
            line.Packed_Quantity__c = line.Picked_Quantity__c;
            line.Status__c = 'Packed';
        }
        Database.update(lines, true, AccessLevel.USER_MODE);

        orderRecord.Status__c = 'Ready to Ship';
        Database.update(orderRecord, AccessLevel.USER_MODE);
        return packageRecord;
    }

    public static Shipment__c shipPackage(Id packageId, String carrier, String trackingNumber, String notes) {
        if (packageId == null) {
            throw new ShippingException('Package is required.');
        }
        if (String.isBlank(carrier) || String.isBlank(trackingNumber)) {
            throw new ShippingException('Carrier and tracking number are required.');
        }

        Package__c packageRecord = [
            SELECT Id, Name, Outbound_Order__c, Warehouse__c, Status__c
            FROM Package__c
            WHERE Id = :packageId
            WITH USER_MODE
            LIMIT 1
            FOR UPDATE
        ];
        if (packageRecord.Status__c != 'Ready to Ship') {
            throw new ShippingException('Only ready-to-ship packages can leave the warehouse.');
        }

        List<Shipment__c> existingShipments = [
            SELECT Id
            FROM Shipment__c
            WHERE Package__c = :packageId AND Status__c != 'Cancelled'
            WITH USER_MODE
            LIMIT 1
        ];
        if (!existingShipments.isEmpty()) {
            throw new ShippingException('This package already has an active shipment.');
        }

        Shipment__c shipment = new Shipment__c(
            Outbound_Order__c = packageRecord.Outbound_Order__c,
            Package__c = packageRecord.Id,
            Warehouse__c = packageRecord.Warehouse__c,
            Carrier__c = carrier.trim(),
            Tracking_Number__c = trackingNumber.trim(),
            Status__c = 'Shipped',
            Shipped_At__c = System.now(),
            Notes__c = notes
        );
        Database.insert(shipment, AccessLevel.USER_MODE);

        packageRecord.Status__c = 'Shipped';
        Database.update(packageRecord, AccessLevel.USER_MODE);

        Outbound_Order__c orderRecord = [
            SELECT Id, Status__c
            FROM Outbound_Order__c
            WHERE Id = :packageRecord.Outbound_Order__c
            WITH USER_MODE
            LIMIT 1
            FOR UPDATE
        ];
        orderRecord.Status__c = 'Shipped';
        Database.update(orderRecord, AccessLevel.USER_MODE);
        return shipment;
    }
}
