Warehouse__c warehouse = new Warehouse__c(
    Name = 'Bursa Distribution Center',
    Code__c = 'BUR-01',
    City__c = 'Bursa',
    Is_Active__c = true
);
insert warehouse;

Bin_Location__c receivingBin = new Bin_Location__c(
    Name = 'Receiving Dock 01',
    Warehouse__c = warehouse.Id,
    Bin_Code__c = 'BUR-RCV-01',
    Bin_Type__c = 'Receiving',
    Zone__c = 'DOCK',
    Capacity__c = 1000,
    Is_Active__c = true
);
Bin_Location__c storageBin = new Bin_Location__c(
    Name = 'Storage A-01-01',
    Warehouse__c = warehouse.Id,
    Bin_Code__c = 'BUR-A-01-01',
    Bin_Type__c = 'Storage',
    Zone__c = 'A',
    Aisle__c = '01',
    Rack__c = '01',
    Capacity__c = 500,
    Is_Active__c = true
);
insert new List<Bin_Location__c>{ receivingBin, storageBin };

Product2 product = new Product2(
    Name = 'Warehouse Demo Product',
    ProductCode = 'SKU-001',
    IsActive = true
);
insert product;

Account supplier = new Account(Name = 'Demo Logistics Supplier');
insert supplier;

Inbound_Shipment__c shipment = new Inbound_Shipment__c(
    Supplier__c = supplier.Id,
    Warehouse__c = warehouse.Id,
    Expected_Date__c = Date.today(),
    Status__c = 'Expected',
    Carrier__c = 'Demo Carrier',
    Tracking_Number__c = 'DEMO-TRK-001'
);
insert shipment;

insert new Inbound_Shipment_Line__c(
    Inbound_Shipment__c = shipment.Id,
    Product__c = product.Id,
    Expected_Quantity__c = 40,
    Received_Quantity__c = 0,
    Damaged_Quantity__c = 0
);

System.debug('Warehouse: ' + warehouse.Id);
System.debug('Receiving bin: ' + receivingBin.Id);
System.debug('Storage bin: ' + storageBin.Id);
System.debug('Inbound shipment: ' + shipment.Id);

// Outbound fulfillment demo data
Bin_Location__c pickingBin = new Bin_Location__c(
    Name = 'Picking P-01-01',
    Warehouse__c = warehouse.Id,
    Bin_Code__c = 'BUR-P-01-01',
    Bin_Type__c = 'Picking',
    Zone__c = 'PICK',
    Capacity__c = 250,
    Is_Active__c = true
);
Bin_Location__c shippingBin = new Bin_Location__c(
    Name = 'Shipping Dock 01',
    Warehouse__c = warehouse.Id,
    Bin_Code__c = 'BUR-SHP-01',
    Bin_Type__c = 'Shipping',
    Zone__c = 'DOCK',
    Capacity__c = 500,
    Is_Active__c = true
);
insert new List<Bin_Location__c>{ pickingBin, shippingBin };

insert new Inventory__c(
    Product__c = product.Id,
    Bin_Location__c = pickingBin.Id,
    On_Hand__c = 60,
    Reserved__c = 0,
    Reorder_Level__c = 10,
    Status__c = 'Available'
);

Account customer = new Account(Name = 'Demo Retail Customer');
insert customer;

Outbound_Order__c outboundOrder = new Outbound_Order__c(
    Warehouse__c = warehouse.Id,
    Customer__c = customer.Id,
    Status__c = 'Draft',
    Priority__c = 'High',
    Order_Date__c = Date.today(),
    Required_Ship_Date__c = Date.today().addDays(1),
    External_Order_Reference__c = 'WEB-DEMO-001',
    Shipping_Address__c = 'Beverly Hills demo destination',
    Shipping_Country_Code__c = 'US',
    Shipping_Postal_Code__c = '90210'
);
insert outboundOrder;

insert new Outbound_Order_Line__c(
    Outbound_Order__c = outboundOrder.Id,
    Product__c = product.Id,
    Ordered_Quantity__c = 12,
    Allocated_Quantity__c = 0,
    Picked_Quantity__c = 0,
    Packed_Quantity__c = 0,
    Status__c = 'Pending'
);

// Week 07 automation: entering Ready to Allocate invokes the record-triggered Flow.
outboundOrder.Status__c = 'Ready to Allocate';
update outboundOrder;

System.debug('Outbound order: ' + outboundOrder.Id);
System.debug('Picking bin: ' + pickingBin.Id);
