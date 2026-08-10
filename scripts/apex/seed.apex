Warehouse__c warehouse = new Warehouse__c(
    Name = 'Bursa Distribution Center',
    Code__c = 'BUR-01',
    City__c = 'Bursa',
    Is_Active__c = true
);
insert warehouse;

Bin_Location__c binLocation = new Bin_Location__c(
    Name = 'A-01-01',
    Warehouse__c = warehouse.Id,
    Bin_Code__c = 'BUR-A-01-01',
    Zone__c = 'A',
    Aisle__c = '01',
    Rack__c = '01',
    Capacity__c = 500,
    Is_Active__c = true
);
insert binLocation;

Product2 product = new Product2(
    Name = 'Demo Product',
    ProductCode = 'SKU-001',
    IsActive = true
);
insert product;

insert new Inventory__c(
    Product__c = product.Id,
    Bin_Location__c = binLocation.Id,
    On_Hand__c = 120,
    Reserved__c = 15,
    Reorder_Level__c = 25,
    Status__c = 'Available'
);
