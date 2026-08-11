public with sharing class WarehousePostalService {
    public class PostalException extends Exception {}

    public class PostalLocation {
        @AuraEnabled public String countryCode;
        @AuraEnabled public String countryName;
        @AuraEnabled public String postalCode;
        @AuraEnabled public String city;
        @AuraEnabled public String region;
        @AuraEnabled public Decimal latitude;
        @AuraEnabled public Decimal longitude;
        @AuraEnabled public String source;
    }

    public static PostalLocation lookup(String countryCode, String postalCode) {
        String normalizedCountry = normalizeCountry(countryCode);
        String normalizedPostal = normalizePostal(postalCode);
        if (String.isBlank(normalizedCountry) || normalizedCountry.length() != 2) {
            throw new PostalException('A two-letter shipping country code is required.');
        }
        if (String.isBlank(normalizedPostal)) {
            throw new PostalException('A shipping postal code is required.');
        }

        HttpRequest request = new HttpRequest();
        request.setMethod('GET');
        request.setTimeout(10000);
        request.setHeader('Accept', 'application/json');
        request.setEndpoint(
            'callout:Warehouse_Postal_API/' +
            EncodingUtil.urlEncode(normalizedCountry.toLowerCase(), 'UTF-8') + '/' +
            EncodingUtil.urlEncode(normalizedPostal, 'UTF-8')
        );

        HttpResponse response;
        try {
            response = new Http().send(request);
        } catch (CalloutException ex) {
            throw new PostalException('Postal validation service could not be reached.');
        }

        if (response.getStatusCode() == 404) {
            throw new PostalException('The shipping postal code was not found for the selected country.');
        }
        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
            throw new PostalException('Postal validation service returned HTTP ' + response.getStatusCode() + '.');
        }

        Map<String, Object> payload;
        try {
            payload = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        } catch (Exception ex) {
            throw new PostalException('Postal validation service returned an invalid response.');
        }

        List<Object> places = (List<Object>) payload.get('places');
        if (places == null || places.isEmpty()) {
            throw new PostalException('Postal validation service returned no matching location.');
        }
        Map<String, Object> firstPlace = (Map<String, Object>) places[0];

        PostalLocation result = new PostalLocation();
        result.countryCode = stringValue(payload.get('country abbreviation'));
        result.countryName = stringValue(payload.get('country'));
        result.postalCode = stringValue(payload.get('post code'));
        result.city = stringValue(firstPlace.get('place name'));
        result.region = stringValue(firstPlace.get('state'));
        result.latitude = decimalValue(firstPlace.get('latitude'));
        result.longitude = decimalValue(firstPlace.get('longitude'));
        result.source = 'Zippopotam.us';
        return result;
    }

    public static PostalLocation validateOrderDestination(Id orderId) {
        if (orderId == null) {
            throw new PostalException('Outbound order is required.');
        }

        Outbound_Order__c snapshot = WarehouseOutboundSelector.selectOrderDestination(orderId);
        if (snapshot == null) {
            throw new PostalException('Outbound order could not be found or accessed.');
        }

        String requestedCountry = normalizeCountry(snapshot.Shipping_Country_Code__c);
        String requestedPostal = normalizePostal(snapshot.Shipping_Postal_Code__c);
        PostalLocation location = lookup(requestedCountry, requestedPostal);

        WarehouseTransactionManager.Scope transactionScope = WarehouseTransactionManager.begin();
        try {
            Outbound_Order__c currentOrder = WarehouseOutboundSelector.selectOrderDestinationForUpdate(orderId);
            if (currentOrder == null) {
                throw new PostalException('Outbound order could not be found or accessed.');
            }
            if (
                normalizeCountry(currentOrder.Shipping_Country_Code__c) != requestedCountry ||
                normalizePostal(currentOrder.Shipping_Postal_Code__c) != requestedPostal
            ) {
                throw new PostalException('Shipping destination changed during validation. Run validation again.');
            }

            currentOrder.Shipping_Country_Code__c = requestedCountry;
            currentOrder.Shipping_Postal_Code__c = requestedPostal;
            currentOrder.Shipping_City__c = location.city;
            currentOrder.Shipping_Region__c = location.region;
            currentOrder.Shipping_Latitude__c = location.latitude;
            currentOrder.Shipping_Longitude__c = location.longitude;
            currentOrder.Shipping_Address_Validated__c = true;
            currentOrder.Shipping_Address_Validated_At__c = System.now();
            currentOrder.Shipping_Address_Source__c = location.source;
            currentOrder.Shipping_Validated_Country_Code__c = requestedCountry;
            currentOrder.Shipping_Validated_Postal_Code__c = requestedPostal;
            Database.update(currentOrder, AccessLevel.USER_MODE);

            transactionScope.complete();
            return location;
        } catch (Exception ex) {
            transactionScope.rollback();
            throw ex;
        }
    }

    private static String normalizeCountry(String countryCode) {
        return String.isBlank(countryCode) ? null : countryCode.trim().toUpperCase();
    }

    private static String normalizePostal(String postalCode) {
        return String.isBlank(postalCode) ? null : postalCode.trim();
    }

    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static Decimal decimalValue(Object value) {
        if (value == null || String.isBlank(String.valueOf(value))) {
            return null;
        }
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception ex) {
            return null;
        }
    }
}
