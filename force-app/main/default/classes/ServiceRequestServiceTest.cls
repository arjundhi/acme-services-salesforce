@IsTest
private class ServiceRequestServiceTest {
    @testSetup
    static void setupUserAccess() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User testUser = new User(
            Alias = 'srusr',
            Email = 'sruser@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'ServiceUser',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'sruser' + System.now().getTime() + '@example.com'
        );
        insert testUser;

        PermissionSet accessPermset = [SELECT Id FROM PermissionSet WHERE Name = 'Service_Request_Access' LIMIT 1];
        insert new PermissionSetAssignment(
            AssigneeId = testUser.Id,
            PermissionSetId = accessPermset.Id
        );
    }

    private static User getTestUser() {
        return [SELECT Id FROM User WHERE Alias = 'srusr' LIMIT 1];
    }

    @IsTest
    static void createRequestsInsertsValidRecords() {
        System.runAs(getTestUser()) {
            ServiceRequestService.CreateRequestInput input = new ServiceRequestService.CreateRequestInput();
            input.customerEmail = 'customer@example.com';
            input.description = 'Battery is draining quickly.';
            input.priority = 'High';

            Test.startTest();
            List<Service_Request__c> createdRequests = ServiceRequestService.createRequests(
                new List<ServiceRequestService.CreateRequestInput>{ input }
            );
            Test.stopTest();

            System.assertEquals(1, createdRequests.size(), 'One record should be returned.');
            Service_Request__c insertedRequest = [
                SELECT Id, Name, Customer_Email__c, Description__c, Priority__c, Status__c
                FROM Service_Request__c
                WHERE Id = :createdRequests[0].Id
            ];
            System.assertEquals('customer@example.com', insertedRequest.Customer_Email__c);
            System.assertEquals('Battery is draining quickly.', insertedRequest.Description__c);
            System.assertEquals('High', insertedRequest.Priority__c);
            System.assertEquals('New', insertedRequest.Status__c);
            System.assert(insertedRequest.Name.startsWith('SR-'), 'Auto number should use SR- format.');
        }
    }

    @IsTest
    static void createRequestsThrowsForMissingEmail() {
        System.runAs(getTestUser()) {
            ServiceRequestService.CreateRequestInput input = new ServiceRequestService.CreateRequestInput();
            input.description = 'No email was provided.';
            input.priority = 'Low';

            try {
                ServiceRequestService.createRequests(new List<ServiceRequestService.CreateRequestInput>{ input });
                System.assert(false, 'Expected ServiceRequestException to be thrown.');
            } catch (ServiceRequestService.ServiceRequestException exceptionInstance) {
                System.assert(exceptionInstance.getMessage().contains('Customer email is required'));
            }
        }
    }

    @IsTest
    static void createRequestsThrowsForInvalidPriority() {
        System.runAs(getTestUser()) {
            ServiceRequestService.CreateRequestInput input = new ServiceRequestService.CreateRequestInput();
            input.customerEmail = 'customer@example.com';
            input.description = 'Priority is invalid.';
            input.priority = 'Urgent';

            try {
                ServiceRequestService.createRequests(new List<ServiceRequestService.CreateRequestInput>{ input });
                System.assert(false, 'Expected ServiceRequestException to be thrown.');
            } catch (ServiceRequestService.ServiceRequestException exceptionInstance) {
                System.assert(exceptionInstance.getMessage().contains('Priority must be Low, Medium, or High'));
            }
        }
    }

    @IsTest
    static void createRequestsHandlesBulkInput() {
        System.runAs(getTestUser()) {
            List<ServiceRequestService.CreateRequestInput> inputs = new List<ServiceRequestService.CreateRequestInput>();
            for (Integer index = 0; index < 200; index++) {
                ServiceRequestService.CreateRequestInput input = new ServiceRequestService.CreateRequestInput();
                input.customerEmail = 'bulk' + index + '@example.com';
                input.description = 'Bulk request #' + index;
                input.priority = Math.mod(index, 2) == 0 ? 'Medium' : 'Low';
                inputs.add(input);
            }

            Test.startTest();
            List<Service_Request__c> createdRequests = ServiceRequestService.createRequests(inputs);
            Test.stopTest();

            System.assertEquals(200, createdRequests.size(), 'All bulk requests should be created.');
            System.assertEquals(200, [SELECT COUNT() FROM Service_Request__c WHERE Customer_Email__c LIKE 'bulk%@example.com']);
        }
    }

    @IsTest
    static void resolveRequestsUpdatesStatusAndNotes() {
        System.runAs(getTestUser()) {
            Service_Request__c requestRecord = new Service_Request__c(
                Customer_Email__c = 'resolve@example.com',
                Description__c = 'Needs a replacement part.',
                Priority__c = 'Medium',
                Status__c = 'In Progress'
            );
            insert requestRecord;

            ServiceRequestService.ResolveRequestInput input = new ServiceRequestService.ResolveRequestInput();
            input.serviceRequestId = requestRecord.Id;
            input.resolutionNotes = 'Replacement part ordered and confirmed with customer.';

            Test.startTest();
            List<Service_Request__c> resolvedRequests = ServiceRequestService.resolveRequests(
                new List<ServiceRequestService.ResolveRequestInput>{ input }
            );
            Test.stopTest();

            System.assertEquals(1, resolvedRequests.size(), 'One record should be resolved.');
            Service_Request__c updatedRequest = [
                SELECT Status__c, Resolution_Notes__c
                FROM Service_Request__c
                WHERE Id = :requestRecord.Id
            ];
            System.assertEquals('Resolved', updatedRequest.Status__c);
            System.assertEquals('Replacement part ordered and confirmed with customer.', updatedRequest.Resolution_Notes__c);
        }
    }

    @IsTest
    static void resolveRequestsThrowsWhenNotesMissing() {
        System.runAs(getTestUser()) {
            Service_Request__c requestRecord = new Service_Request__c(
                Customer_Email__c = 'missingnotes@example.com',
                Description__c = 'Needs status update.',
                Priority__c = 'Low',
                Status__c = 'In Progress'
            );
            insert requestRecord;

            ServiceRequestService.ResolveRequestInput input = new ServiceRequestService.ResolveRequestInput();
            input.serviceRequestId = requestRecord.Id;
            input.resolutionNotes = '   ';

            try {
                ServiceRequestService.resolveRequests(new List<ServiceRequestService.ResolveRequestInput>{ input });
                System.assert(false, 'Expected ServiceRequestException to be thrown.');
            } catch (ServiceRequestService.ServiceRequestException exceptionInstance) {
                System.assert(exceptionInstance.getMessage().contains('Resolution notes are required'));
            }
        }
    }

    @IsTest
    static void getRecentRequestsReturnsNewestRecordsFirst() {
        System.runAs(getTestUser()) {
            List<Service_Request__c> requestsToInsert = new List<Service_Request__c>();
            for (Integer index = 0; index < 6; index++) {
                requestsToInsert.add(new Service_Request__c(
                    Customer_Email__c = 'recent' + index + '@example.com',
                    Description__c = 'Recent request #' + index,
                    Priority__c = 'Medium',
                    Status__c = 'New'
                ));
            }
            insert requestsToInsert;
            for (Integer index = 0; index < requestsToInsert.size(); index++) {
                Test.setCreatedDate(requestsToInsert[index].Id, Datetime.newInstance(2026, 1, 1, 0, 0, index));
            }

            Test.startTest();
            List<Service_Request__c> recentRequests = ServiceRequestService.getRecentRequests(5);
            Test.stopTest();

            System.assertEquals(5, recentRequests.size(), 'Method should cap output at five records here.');
            System.assertEquals(requestsToInsert[5].Id, recentRequests[0].Id, 'Newest record should appear first.');
        }
    }
}