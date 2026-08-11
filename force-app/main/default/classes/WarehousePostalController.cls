public with sharing class WarehousePostalController {
    @AuraEnabled
    public static WarehousePostalService.PostalLocation validateOrderDestination(Id orderId) {
        return WarehousePostalService.validateOrderDestination(orderId);
    }
}
