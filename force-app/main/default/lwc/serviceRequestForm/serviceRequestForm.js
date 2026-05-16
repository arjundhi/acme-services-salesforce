import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createServiceRequest from '@salesforce/apex/ServiceRequestController.createServiceRequest';
import getRecentServiceRequests from '@salesforce/apex/ServiceRequestController.getRecentServiceRequests';

export default class ServiceRequestForm extends LightningElement {
    email = '';
    description = '';
    priority = 'Medium';
    createdRecordId;
    errorMessage;
    isLoading = false;
    recentRequests = [];
    wiredRecentRequestsResult;

    priorityOptions = [
        { label: 'Low', value: 'Low' },
        { label: 'Medium', value: 'Medium' },
        { label: 'High', value: 'High' }
    ];

    @wire(getRecentServiceRequests)
    wiredRecentRequests(result) {
        this.wiredRecentRequestsResult = result;
        if (result.data) {
            this.recentRequests = result.data;
        } else if (result.error) {
            this.recentRequests = [];
            console.error('Error loading recent requests:', result.error);
        }
    }

    handleFieldChange(event) {
        const fieldName = event.target.dataset.field;
        this[fieldName] = event.target.value;
        // Clear error when user starts typing
        if (this.errorMessage) {
            this.errorMessage = undefined;
        }
    }

    handleClear() {
        this.email = '';
        this.description = '';
        this.priority = 'Medium';
        this.errorMessage = undefined;
        this.createdRecordId = undefined;
        
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Form Cleared',
                message: 'All fields have been cleared.',
                variant: 'info'
            })
        );
    }

    async handleSubmit() {
        // Validate before submission
        if (!this.validateForm()) {
            return;
        }

        this.errorMessage = undefined;
        this.createdRecordId = undefined;
        this.isLoading = true;

        try {
            this.createdRecordId = await createServiceRequest({
                email: this.email.trim(),
                description: this.description.trim(),
                priority: this.priority
            });

            // Show success toast
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: `Service Request created successfully with ID: ${this.createdRecordId}`,
                    variant: 'success',
                    mode: 'sticky'
                })
            );

            // Clear form
            this.resetForm();

            // Refresh recent requests list
            await refreshApex(this.wiredRecentRequestsResult);
        } catch (error) {
            // Extract meaningful error message
            const errorMessage = this.getErrorMessage(error);
            this.errorMessage = errorMessage;

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error Creating Request',
                    message: errorMessage,
                    variant: 'error',
                    mode: 'sticky'
                })
            );

            console.error('Error creating service request:', error);
        } finally {
            this.isLoading = false;
        }
    }

    validateForm() {
        // Email validation
        if (!this.email || this.email.trim() === '') {
            this.errorMessage = 'Customer email is required.';
            return false;
        }

        // Email format validation
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailRegex.test(this.email.trim())) {
            this.errorMessage = 'Please enter a valid email address.';
            return false;
        }

        // Priority validation
        if (!this.priority || this.priority.trim() === '') {
            this.errorMessage = 'Priority is required.';
            return false;
        }

        // Priority value check
        const validPriorities = ['Low', 'Medium', 'High'];
        if (!validPriorities.includes(this.priority)) {
            this.errorMessage = 'Invalid priority value selected.';
            return false;
        }

        return true;
    }

    resetForm() {
        this.description = '';
        this.email = '';
        this.priority = 'Medium';
    }

    getErrorMessage(error) {
        if (error.body) {
            if (error.body.message) {
                return error.body.message;
            }
            if (error.body.pageErrors && error.body.pageErrors.length > 0) {
                return error.body.pageErrors[0].message;
            }
            if (error.body.fieldErrors) {
                const fieldErrors = Object.values(error.body.fieldErrors);
                if (fieldErrors.length > 0 && fieldErrors[0].length > 0) {
                    return fieldErrors[0][0].message;
                }
            }
        }
        return error.message || 'Unable to create the service request. Please try again.';
    }
}