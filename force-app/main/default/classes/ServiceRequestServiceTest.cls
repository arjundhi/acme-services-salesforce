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

    @IsTest
    static void resolveBulkRequestsValidatesAndUpdatesBothStatusAndNotes() {
        System.runAs(getTestUser()) {
            List<Service_Request__c> requestsToResolve = new List<Service_Request__c>();
            for (Integer index = 0; index < 50; index++) {
                requestsToResolve.add(new Service_Request__c(
                    Customer_Email__c = 'bulk-resolve' + index + '@example.com',
                    Description__c = 'Bulk resolve test #' + index,
                    Priority__c = 'Medium',
                    Status__c = 'In Progress'
                ));
            }
            insert requestsToResolve;

            List<ServiceRequestService.ResolveRequestInput> resolveInputs = new List<ServiceRequestService.ResolveRequestInput>();
            for (Integer index = 0; index < requestsToResolve.size(); index++) {
                ServiceRequestService.ResolveRequestInput input = new ServiceRequestService.ResolveRequestInput();
                input.serviceRequestId = requestsToResolve[index].Id;
                input.resolutionNotes = 'Resolved bulk request #' + index + ' with comprehensive notes.';
                resolveInputs.add(input);
            }

            Test.startTest();
            List<Service_Request__c> resolvedRequests = ServiceRequestService.resolveRequests(resolveInputs);
            Test.stopTest();

            System.assertEquals(50, resolvedRequests.size(), 'All 50 bulk requests should be resolved.');
            List<Service_Request__c> verifyResolved = [
                SELECT Id, Status__c, Resolution_Notes__c, Priority__c
                FROM Service_Request__c
                WHERE Customer_Email__c LIKE 'bulk-resolve%@example.com'
            ];
            System.assertEquals(50, verifyResolved.size(), 'All 50 records should be in database.');
            for (Service_Request__c record : verifyResolved) {
                System.assertEquals('Resolved', record.Status__c, 'Status should be Resolved.');
                System.assert(record.Resolution_Notes__c.contains('Resolved'), 'Resolution notes should be captured.');
            }
        }
    }

    @IsTest
    static void resolveRequestsThrowsForInvalidId() {
        System.runAs(getTestUser()) {
            ServiceRequestService.ResolveRequestInput input = new ServiceRequestService.ResolveRequestInput();
            input.serviceRequestId = null;
            input.resolutionNotes = 'This should fail';

            try {
                ServiceRequestService.resolveRequests(new List<ServiceRequestService.ResolveRequestInput>{ input });
                System.assert(false, 'Expected ServiceRequestException for null record ID.');
            } catch (ServiceRequestService.ServiceRequestException exceptionInstance) {
                System.assert(exceptionInstance.getMessage().contains('required'), 'Error message should indicate Id is required.');
            }
        }
    }

    @IsTest
    static void validateDataIntegrityForWhitespaceHandling() {
        System.runAs(getTestUser()) {
            ServiceRequestService.CreateRequestInput input = new ServiceRequestService.CreateRequestInput();
            input.customerEmail = '  customer@example.com  ';
            input.description = '  Description with whitespace  ';
            input.priority = '  High  ';

            List<Service_Request__c> createdRequests = ServiceRequestService.createRequests(
                new List<ServiceRequestService.CreateRequestInput>{ input }
            );

            Service_Request__c insertedRequest = [
                SELECT Customer_Email__c, Description__c, Priority__c
                FROM Service_Request__c
                WHERE Id = :createdRequests[0].Id
            ];
            System.assertEquals('customer@example.com', insertedRequest.Customer_Email__c, 'Email should be trimmed.');
            System.assertEquals('Description with whitespace', insertedRequest.Description__c, 'Description should be trimmed.');
            System.assertEquals('High', insertedRequest.Priority__c, 'Priority should be trimmed.');
        }
    }

    @IsTest
    static void validateDataIntegrityForEmailValidation() {
        System.runAs(getTestUser()) {
            List<String> invalidEmails = new List<String>{
                'notanemail',
                'missing@domain',
                '@nodomain.com',
                'spaces in@email.com'
            };

            for (String invalidEmail : invalidEmails) {
                ServiceRequestService.CreateRequestInput input = new ServiceRequestService.CreateRequestInput();
                input.customerEmail = invalidEmail;
                input.description = 'Test';
                input.priority = 'Medium';

                try {
                    ServiceRequestService.createRequests(
                        new List<ServiceRequestService.CreateRequestInput>{ input }
                    );
                    System.assert(false, 'Should throw for invalid email: ' + invalidEmail);
                } catch (ServiceRequestService.ServiceRequestException exceptionInstance) {
                    System.assert(exceptionInstance.getMessage().contains('email is invalid'), 'Error should indicate invalid email format.');
                }
            }
        }
    }

    @IsTest
    static void validateCreateAccessCheck() {
        System.runAs(getTestUser()) {
            ServiceRequestService.CreateRequestInput input = new ServiceRequestService.CreateRequestInput();
            input.customerEmail = 'test@example.com';
            input.description = 'Test access check';
            input.priority = 'Low';

            // This test verifies the CRUD check passes with valid permission set
            List<Service_Request__c> result = ServiceRequestService.createRequests(
                new List<ServiceRequestService.CreateRequestInput>{ input }
            );
            System.assertEquals(1, result.size(), 'Should create record with valid access.');
        }
    }

    @IsTest
    static void validateEmptyInputThrows() {
        System.runAs(getTestUser()) {
            try {
                ServiceRequestService.createRequests(new List<ServiceRequestService.CreateRequestInput>());
                System.assert(false, 'Should throw for empty input list.');
            } catch (ServiceRequestService.ServiceRequestException exceptionInstance) {
                System.assert(exceptionInstance.getMessage().contains('At least one'), 'Error should indicate empty list.');
            }
        }
    }

    @IsTest
    static void validateNullInputThrows() {
        System.runAs(getTestUser()) {
            try {
                ServiceRequestService.createRequests(null);
                System.assert(false, 'Should throw for null input list.');
            } catch (ServiceRequestService.ServiceRequestException exceptionInstance) {
                System.assert(exceptionInstance.getMessage().contains('At least one'), 'Error should indicate null list.');
            }
        }
    }

    @IsTest
    static void validateResolveEmptyInputThrows() {
        System.runAs(getTestUser()) {
            try {
                ServiceRequestService.resolveRequests(new List<ServiceRequestService.ResolveRequestInput>());
                System.assert(false, 'Should throw for empty resolve input.');
            } catch (ServiceRequestService.ServiceRequestException exceptionInstance) {
                System.assert(exceptionInstance.getMessage().contains('At least one'), 'Error should indicate empty list.');
            }
        }
    }

    @IsTest
    static void validateResolveNullInputThrows() {
        System.runAs(getTestUser()) {
            try {
                ServiceRequestService.resolveRequests(null);
                System.assert(false, 'Should throw for null resolve input.');
            } catch (ServiceRequestService.ServiceRequestException exceptionInstance) {
                System.assert(exceptionInstance.getMessage().contains('At least one'), 'Error should indicate null list.');
            }
        }
    }

    @IsTest
    static void validateGetRecentRequestsAccessCheck() {
        System.runAs(getTestUser()) {
            Service_Request__c requestRecord = new Service_Request__c(
                Customer_Email__c = 'access@example.com',
                Description__c = 'Access check test',
                Priority__c = 'Medium',
                Status__c = 'New'
            );
            insert requestRecord;

            List<Service_Request__c> recentRequests = ServiceRequestService.getRecentRequests(10);
            System.assertNotEquals(0, recentRequests.size(), 'Should retrieve records with valid access.');
        }
    }

    @IsTest
    static void validateGetRecentRequestsWithLargeLimit() {
        System.runAs(getTestUser()) {
            // Large limit should be capped at 50
            List<Service_Request__c> recentRequests = ServiceRequestService.getRecentRequests(1000);
            System.assert(recentRequests.size() <= 50, 'Large limit should be capped at 50.');
        }
    }

    @IsTest
    static void validateRecordNotFoundInResolve() {
        System.runAs(getTestUser()) {
            // Create a request
            Service_Request__c requestRecord = new Service_Request__c(
                Customer_Email__c = 'notfound@example.com',
                Description__c = 'Will be deleted',
                Priority__c = 'Low',
                Status__c = 'In Progress'
            );
            insert requestRecord;
            Id recordId = requestRecord.Id;
            delete requestRecord;

            // Try to resolve deleted record
            ServiceRequestService.ResolveRequestInput input = new ServiceRequestService.ResolveRequestInput();
            input.serviceRequestId = recordId;
            input.resolutionNotes = 'Should fail';

            try {
                ServiceRequestService.resolveRequests(new List<ServiceRequestService.ResolveRequestInput>{ input });
                System.assert(false, 'Should throw for non-existent record.');
            } catch (ServiceRequestService.ServiceRequestException exceptionInstance) {
                System.assert(exceptionInstance.getMessage().contains('could not be found'), 'Error should indicate record not found.');
            }
        }
    }
}