public with sharing class ServiceRequestService {
    private static final Set<String> ALLOWED_PRIORITIES = new Set<String>{ 'Low', 'Medium', 'High' };
    private static final Pattern EMAIL_PATTERN =
        Pattern.compile('(?i)^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$');

    public class ServiceRequestException extends Exception {
    }

    public class CreateRequestInput {
        public String customerEmail;
        public String description;
        public String priority;
    }

    public class ResolveRequestInput {
        public Id serviceRequestId;
        public String resolutionNotes;
    }

    public static List<Service_Request__c> createRequests(List<CreateRequestInput> inputs) {
        if (inputs == null || inputs.isEmpty()) {
            throw new ServiceRequestException('At least one service request is required.');
        }

        enforceCreateAccess();

        List<Service_Request__c> requestsToInsert = new List<Service_Request__c>();
        for (Integer index = 0; index < inputs.size(); index++) {
            CreateRequestInput input = inputs[index];
            validateCreateInput(input, index);

            requestsToInsert.add(new Service_Request__c(
                Customer_Email__c = input.customerEmail.trim(),
                Description__c = normalizeText(input.description),
                Priority__c = input.priority.trim(),
                Status__c = 'New'
            ));
        }

        insert requestsToInsert;
        return requestsToInsert;
    }

    public static List<Service_Request__c> resolveRequests(List<ResolveRequestInput> inputs) {
        if (inputs == null || inputs.isEmpty()) {
            throw new ServiceRequestException('At least one service request resolution is required.');
        }

        enforceUpdateAccess();

        Set<Id> requestIds = new Set<Id>();
        Map<Id, String> notesById = new Map<Id, String>();
        for (Integer index = 0; index < inputs.size(); index++) {
            ResolveRequestInput input = inputs[index];
            validateResolveInput(input, index);
            requestIds.add(input.serviceRequestId);
            notesById.put(input.serviceRequestId, input.resolutionNotes.trim());
        }

        Map<Id, Service_Request__c> requestsById = new Map<Id, Service_Request__c>([
            SELECT Id, Status__c, Resolution_Notes__c
            FROM Service_Request__c
            WHERE Id IN :requestIds
        ]);

        if (requestsById.size() != requestIds.size()) {
            throw new ServiceRequestException('One or more service requests could not be found.');
        }

        List<Service_Request__c> requestsToUpdate = new List<Service_Request__c>();
        for (Id requestId : requestIds) {
            Service_Request__c requestRecord = requestsById.get(requestId);
            if (requestRecord.Status__c == 'Resolved') {
                throw new ServiceRequestException('Service request ' + requestRecord.Id + ' is already resolved.');
            }
            requestRecord.Status__c = 'Resolved';
            requestRecord.Resolution_Notes__c = notesById.get(requestId);
            requestsToUpdate.add(requestRecord);
        }

        update requestsToUpdate;
        return requestsToUpdate;
    }

    public static List<Service_Request__c> getRecentRequests(Integer limitSize) {
        if (!Schema.sObjectType.Service_Request__c.isAccessible()) {
            throw new ServiceRequestException('You do not have access to view service requests.');
        }

        Integer safeLimit = limitSize == null || limitSize <= 0 ? 5 : Math.min(limitSize, 50);
        return [
            SELECT Id, Name, Customer_Email__c, Priority__c, Status__c, CreatedDate
            FROM Service_Request__c
            ORDER BY CreatedDate DESC, Id DESC
            LIMIT :safeLimit
        ];
    }

    private static void validateCreateInput(CreateRequestInput input, Integer index) {
        if (input == null) {
            throw new ServiceRequestException('Input row ' + (index + 1) + ' is required.');
        }
        if (String.isBlank(input.customerEmail)) {
            throw new ServiceRequestException('Customer email is required for row ' + (index + 1) + '.');
        }
        if (!EMAIL_PATTERN.matcher(input.customerEmail.trim()).matches()) {
            throw new ServiceRequestException('Customer email is invalid for row ' + (index + 1) + '.');
        }
        if (String.isBlank(input.priority)) {
            throw new ServiceRequestException('Priority is required for row ' + (index + 1) + '.');
        }
        if (!ALLOWED_PRIORITIES.contains(input.priority.trim())) {
            throw new ServiceRequestException('Priority must be Low, Medium, or High for row ' + (index + 1) + '.');
        }
    }

    private static void validateResolveInput(ResolveRequestInput input, Integer index) {
        if (input == null) {
            throw new ServiceRequestException('Resolution row ' + (index + 1) + ' is required.');
        }
        if (input.serviceRequestId == null) {
            throw new ServiceRequestException('Service request Id is required for row ' + (index + 1) + '.');
        }
        if (String.isBlank(input.resolutionNotes)) {
            throw new ServiceRequestException('Resolution notes are required for row ' + (index + 1) + '.');
        }
    }

    private static String normalizeText(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static void enforceCreateAccess() {
        if (!Schema.sObjectType.Service_Request__c.isCreateable()) {
            throw new ServiceRequestException('You do not have permission to create service requests.');
        }

        List<Schema.DescribeFieldResult> requiredFields = new List<Schema.DescribeFieldResult>{
            Service_Request__c.Customer_Email__c.getDescribe(),
            Service_Request__c.Description__c.getDescribe(),
            Service_Request__c.Priority__c.getDescribe(),
            Service_Request__c.Status__c.getDescribe()
        };
        validateFieldAccess(requiredFields, 'create');
    }

    private static void enforceUpdateAccess() {
        if (!Schema.sObjectType.Service_Request__c.isUpdateable()) {
            throw new ServiceRequestException('You do not have permission to update service requests.');
        }

        List<Schema.DescribeFieldResult> requiredFields = new List<Schema.DescribeFieldResult>{
            Service_Request__c.Status__c.getDescribe(),
            Service_Request__c.Resolution_Notes__c.getDescribe()
        };
        validateFieldAccess(requiredFields, 'update');
    }

    private static void validateFieldAccess(List<Schema.DescribeFieldResult> fields, String operation) {
        for (Schema.DescribeFieldResult fieldDescribe : fields) {
            Boolean allowed = operation == 'create' ? fieldDescribe.isCreateable() : fieldDescribe.isUpdateable();
            if (!allowed) {
                throw new ServiceRequestException('Missing field-level access required to ' + operation + ' service requests.');
            }
        }
    }

    // ---------- Agentforce / Flow Invocable ----------

    public class ResolveRequestInvocableInput {
        @InvocableVariable(required=true description='Id of the Service Request to resolve')
        public Id serviceRequestId;

        @InvocableVariable(required=true description='Resolution notes to save on the record')
        public String resolutionNotes;
    }

    @InvocableMethod(
        label='Resolve Service Request'
        description='Sets a Service Request to Resolved and saves the provided Resolution Notes. Designed for Agentforce AI Actions and Flows.'
        category='Service Requests'
    )
    public static List<Id> resolveRequestsInvocable(List<ResolveRequestInvocableInput> inputs) {
        List<ResolveRequestInput> resolveInputs = new List<ResolveRequestInput>();
        for (ResolveRequestInvocableInput inv : inputs) {
            ResolveRequestInput ri = new ResolveRequestInput();
            ri.serviceRequestId = inv.serviceRequestId;
            ri.resolutionNotes = inv.resolutionNotes;
            resolveInputs.add(ri);
        }
        List<Service_Request__c> resolved = resolveRequests(resolveInputs);
        List<Id> resolvedIds = new List<Id>();
        for (Service_Request__c rec : resolved) {
            resolvedIds.add(rec.Id);
        }
        return resolvedIds;
    }
}