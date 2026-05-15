public with sharing class ServiceRequestController {
    @AuraEnabled
    public static Id createServiceRequest(String email, String description, String priority) {
        try {
            ServiceRequestService.CreateRequestInput input = new ServiceRequestService.CreateRequestInput();
            input.customerEmail = email;
            input.description = description;
            input.priority = priority;

            return ServiceRequestService.createRequests(new List<ServiceRequestService.CreateRequestInput>{ input })[0].Id;
        } catch (Exception exceptionInstance) {
            throw buildAuraHandledException(exceptionInstance);
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Service_Request__c> getRecentServiceRequests() {
        try {
            return ServiceRequestService.getRecentRequests(5);
        } catch (Exception exceptionInstance) {
            throw buildAuraHandledException(exceptionInstance);
        }
    }

    private static AuraHandledException buildAuraHandledException(Exception exceptionInstance) {
        AuraHandledException handledException = new AuraHandledException(exceptionInstance.getMessage());
        handledException.setMessage(exceptionInstance.getMessage());
        return handledException;
    }
}