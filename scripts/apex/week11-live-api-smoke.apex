Outbound_Order__c orderRecord = [
    SELECT Id, Name, Shipping_Country_Code__c, Shipping_Postal_Code__c
    FROM Outbound_Order__c
    WHERE External_Order_Reference__c = 'WEB-DEMO-001'
    LIMIT 1
];

System.debug('Validating destination for ' + orderRecord.Name + ': ' +
    orderRecord.Shipping_Country_Code__c + ' ' + orderRecord.Shipping_Postal_Code__c);

WarehousePostalService.PostalLocation result =
    WarehousePostalService.validateOrderDestination(orderRecord.Id);

System.debug('LIVE API RESULT: ' + JSON.serializePretty(result));
