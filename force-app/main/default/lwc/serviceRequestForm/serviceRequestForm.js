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
        }
    }

    handleFieldChange(event) {
        const fieldName = event.target.dataset.field;
        this[fieldName] = event.target.value;
    }

    async handleSubmit() {
        this.errorMessage = undefined;
        this.createdRecordId = undefined;

        if (!this.email || !this.priority) {
            this.errorMessage = 'Customer email and priority are required.';
            return;
        }

        this.isLoading = true;
        try {
            this.createdRecordId = await createServiceRequest({
                email: this.email,
                description: this.description,
                priority: this.priority
            });

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Service Request created successfully.',
                    variant: 'success'
                })
            );

            this.description = '';
            this.email = '';
            this.priority = 'Medium';
            await refreshApex(this.wiredRecentRequestsResult);
        } catch (error) {
            this.errorMessage = error?.body?.message || 'Unable to create the service request.';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: this.errorMessage,
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }
}