@IsTest
private class WarehousePostalServiceTest {
    private class PostalMock implements HttpCalloutMock {
        private Integer statusCode;
        private String body;

        PostalMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest request) {
            System.assertEquals('GET', request.getMethod());
            System.assert(request.getEndpoint().startsWith('callout:Warehouse_Postal_API/'));
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setHeader('Content-Type', 'application/json');
            response.setBody(body);
            return response;
        }
    }

    @TestSetup
    static void setupData() {
        WarehouseTestDataFactory.CoreScenario scenario = WarehouseTestDataFactory.createCoreScenario('POST', 25);
        Outbound_Order__c orderRecord = WarehouseTestDataFactory.createOutboundOrder(
            scenario, 'POSTAL-001', 5
        );
        orderRecord.Shipping_Address__c = 'Beverly Hills delivery address';
        orderRecord.Shipping_Country_Code__c = 'US';
        orderRecord.Shipping_Postal_Code__c = '90210';
        update orderRecord;
    }

    @IsTest
    static void liveApiResponseUpdatesDestinationSnapshot() {
        Outbound_Order__c orderRecord = [
            SELECT Id FROM Outbound_Order__c WHERE External_Order_Reference__c = 'POSTAL-001' LIMIT 1
        ];
        Test.setMock(HttpCalloutMock.class, new PostalMock(200, successBody()));

        Test.startTest();
        WarehousePostalService.PostalLocation result =
            WarehousePostalController.validateOrderDestination(orderRecord.Id);
        Test.stopTest();

        System.assertEquals('Beverly Hills', result.city);
        System.assertEquals('California', result.region);
        System.assertEquals('US', result.countryCode);
        System.assertEquals('90210', result.postalCode);
        System.assertEquals('Zippopotam.us', result.source);

        Outbound_Order__c updatedOrder = [
            SELECT Shipping_Country_Code__c, Shipping_Postal_Code__c,
                   Shipping_City__c, Shipping_Region__c,
                   Shipping_Latitude__c, Shipping_Longitude__c,
                   Shipping_Address_Validated__c, Shipping_Address_Validated_At__c,
                   Shipping_Address_Source__c,
                   Shipping_Validated_Country_Code__c, Shipping_Validated_Postal_Code__c
            FROM Outbound_Order__c
            WHERE Id = :orderRecord.Id
        ];
        System.assertEquals(true, updatedOrder.Shipping_Address_Validated__c);
        System.assertNotEquals(null, updatedOrder.Shipping_Address_Validated_At__c);
        System.assertEquals('Beverly Hills', updatedOrder.Shipping_City__c);
        System.assertEquals('California', updatedOrder.Shipping_Region__c);
        System.assertEquals(34.0901, updatedOrder.Shipping_Latitude__c);
        System.assertEquals(-118.4065, updatedOrder.Shipping_Longitude__c);
        System.assertEquals('US', updatedOrder.Shipping_Validated_Country_Code__c);
        System.assertEquals('90210', updatedOrder.Shipping_Validated_Postal_Code__c);
    }

    @IsTest
    static void missingPostalCodeReturnsUsefulErrorWithoutUpdatingOrder() {
        Outbound_Order__c orderRecord = [SELECT Id FROM Outbound_Order__c LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new PostalMock(404, '{}'));

        Boolean rejected = false;
        Test.startTest();
        try {
            WarehousePostalService.validateOrderDestination(orderRecord.Id);
        } catch (WarehousePostalService.PostalException ex) {
            rejected = true;
            System.assert(ex.getMessage().contains('not found'));
        }
        Test.stopTest();

        System.assertEquals(true, rejected);
        Outbound_Order__c unchanged = [
            SELECT Shipping_Address_Validated__c FROM Outbound_Order__c WHERE Id = :orderRecord.Id
        ];
        System.assertEquals(false, unchanged.Shipping_Address_Validated__c);
    }

    @IsTest
    static void providerFailureAndMalformedResponseAreHandled() {
        Outbound_Order__c orderRecord = [SELECT Id FROM Outbound_Order__c LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new PostalMock(503, '{"error":"maintenance"}'));
        Boolean providerFailure = false;
        Test.startTest();
        try {
            WarehousePostalService.validateOrderDestination(orderRecord.Id);
        } catch (WarehousePostalService.PostalException ex) {
            providerFailure = true;
            System.assert(ex.getMessage().contains('HTTP 503'));
        }
        Test.stopTest();
        System.assertEquals(true, providerFailure);

        Test.setMock(HttpCalloutMock.class, new PostalMock(200, '{not-json'));
        Boolean malformed = false;
        Test.startTest();
        try {
            WarehousePostalService.validateOrderDestination(orderRecord.Id);
        } catch (WarehousePostalService.PostalException ex) {
            malformed = true;
            System.assert(ex.getMessage().contains('invalid response'));
        }
        Test.stopTest();
        System.assertEquals(true, malformed);
    }

    @IsTest
    static void shippingRejectsMissingOrStaleValidationSnapshot() {
        Warehouse__c warehouse = [SELECT Id FROM Warehouse__c LIMIT 1];
        Outbound_Order__c orderRecord = [SELECT Id FROM Outbound_Order__c LIMIT 1];
        orderRecord.Status__c = 'Ready to Ship';
        update orderRecord;

        Package__c packageRecord = new Package__c(
            Outbound_Order__c = orderRecord.Id,
            Warehouse__c = warehouse.Id,
            Status__c = 'Ready to Ship',
            Weight__c = 2
        );
        insert packageRecord;

        Boolean missingRejected = false;
        Test.startTest();
        try {
            WarehouseShippingService.shipPackage(packageRecord.Id, 'Demo Express', 'POST-1', null);
        } catch (WarehouseShippingService.ShippingException ex) {
            missingRejected = true;
            System.assert(ex.getMessage().contains('Validate the current'));
        }
        Test.stopTest();
        System.assertEquals(true, missingRejected);

        orderRecord = [
            SELECT Id, Shipping_Country_Code__c, Shipping_Postal_Code__c
            FROM Outbound_Order__c WHERE Id = :orderRecord.Id
        ];
        orderRecord.Shipping_Address_Validated__c = true;
        orderRecord.Shipping_Validated_Country_Code__c = 'US';
        orderRecord.Shipping_Validated_Postal_Code__c = '10001';
        update orderRecord;

        Boolean staleRejected = false;
        Test.startTest();
        try {
            WarehouseShippingService.shipPackage(packageRecord.Id, 'Demo Express', 'POST-2', null);
        } catch (WarehouseShippingService.ShippingException ex) {
            staleRejected = true;
            System.assert(ex.getMessage().contains('Validate the current'));
        }
        Test.stopTest();
        System.assertEquals(true, staleRejected);
    }

    private static String successBody() {
        return '{' +
            '"post code":"90210",' +
            '"country":"United States",' +
            '"country abbreviation":"US",' +
            '"places":[{' +
                '"place name":"Beverly Hills",' +
                '"longitude":"-118.4065",' +
                '"state":"California",' +
                '"state abbreviation":"CA",' +
                '"latitude":"34.0901"' +
            '}]' +
        '}';
    }
}
