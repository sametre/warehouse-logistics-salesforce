public with sharing class WarehouseShippingService {
    public class ShippingException extends Exception {}

    public static Package__c packOrder(Id orderId, Decimal weight, String notes) {
        if (orderId == null) {
            throw new ShippingException('Outbound order is required.');
        }
        if (weight != null && weight < 0) {
            throw new ShippingException('Package weight cannot be negative.');
        }

        WarehouseTransactionManager.Scope transactionScope = WarehouseTransactionManager.begin();
        try {
            Outbound_Order__c orderRecord = WarehouseOutboundSelector.selectOrderForUpdate(orderId);
            if (orderRecord == null) {
                throw new ShippingException('Outbound order could not be found or accessed.');
            }
            if (orderRecord.Status__c != 'Packing') {
                throw new ShippingException('The order must finish picking before it can be packed.');
            }

            List<Outbound_Order_Line__c> lines = WarehouseOutboundSelector.selectOrderLinesForUpdate(orderId);
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

            if (!WarehouseOutboundSelector.selectActivePackages(orderId).isEmpty()) {
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

            transactionScope.complete();
            return packageRecord;
        } catch (Exception ex) {
            transactionScope.rollback();
            throw ex;
        }
    }

    public static Shipment__c shipPackage(Id packageId, String carrier, String trackingNumber, String notes) {
        if (packageId == null) {
            throw new ShippingException('Package is required.');
        }
        if (String.isBlank(carrier) || String.isBlank(trackingNumber)) {
            throw new ShippingException('Carrier and tracking number are required.');
        }

        WarehouseTransactionManager.Scope transactionScope = WarehouseTransactionManager.begin();
        try {
            Package__c packageRecord = WarehouseOutboundSelector.selectPackageForUpdate(packageId);
            if (packageRecord == null) {
                throw new ShippingException('Package could not be found or accessed.');
            }
            if (packageRecord.Status__c != 'Ready to Ship') {
                throw new ShippingException('Only ready-to-ship packages can leave the warehouse.');
            }

            if (!WarehouseOutboundSelector.selectActiveShipments(packageId).isEmpty()) {
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

            Outbound_Order__c orderRecord = WarehouseOutboundSelector.selectOrderForUpdate(
                packageRecord.Outbound_Order__c
            );
            if (orderRecord == null) {
                throw new ShippingException('Outbound order could not be found or accessed.');
            }
            orderRecord.Status__c = 'Shipped';
            Database.update(orderRecord, AccessLevel.USER_MODE);

            transactionScope.complete();
            return shipment;
        } catch (Exception ex) {
            transactionScope.rollback();
            throw ex;
        }
    }
}
