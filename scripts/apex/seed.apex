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
