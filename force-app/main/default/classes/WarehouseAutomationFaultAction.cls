public with sharing class WarehouseAutomationFaultAction {
    public class Request {
        @InvocableVariable(required=true label='Flow Name')
        public String flowName;

        @InvocableVariable(label='Related Record Id')
        public String relatedRecordId;

        @InvocableVariable(required=true label='Fault Message')
        public String message;

        @InvocableVariable(label='Context')
        public String context;
    }

    @InvocableMethod(
        label='Log Warehouse Automation Faults'
        description='Writes background automation failures to the warehouse automation log for review.'
    )
    public static void logFaults(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        List<Warehouse_Automation_Log__c> logs = new List<Warehouse_Automation_Log__c>();
        for (Request request : requests) {
            if (request == null || String.isBlank(request.flowName) || String.isBlank(request.message)) {
                continue;
            }
            logs.add(new Warehouse_Automation_Log__c(
                Flow_Name__c = request.flowName.length() > 120 ? request.flowName.substring(0, 120) : request.flowName,
                Related_Record_Id__c = normalizeRecordId(request.relatedRecordId),
                Severity__c = 'Error',
                Message__c = request.message,
                Context__c = request.context,
                Logged_At__c = System.now()
            ));
        }
        if (!logs.isEmpty()) {
            // This is an internal audit trail owned by the application. Logging must not fail just
            // because the initiating persona intentionally has no direct write access to log records.
            Database.insert(logs, false, AccessLevel.SYSTEM_MODE);
        }
    }

    private static String normalizeRecordId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.length() > 18 ? trimmed.substring(0, 18) : trimmed;
    }
}
