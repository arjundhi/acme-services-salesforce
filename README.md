# Acme Services Take-Home Assessment

This project implements a lean but production-minded Salesforce solution for creating and resolving customer `Service_Request__c` records.

## What’s Included

- Custom object metadata for `Service_Request__c`
- Apex service layer for create and resolve operations
- LWC-facing Apex controller
- `serviceRequestForm` Lightning Web Component
- Apex test coverage for positive, negative, and bulk scenarios
- Agentforce integration notes for the optional bonus

## Design Choices

The solution intentionally avoids unnecessary framework layers to keep the implementation simple, readable, and maintainable:

- A single service class (`ServiceRequestService`) contains validation and DML logic.
- A thin controller (`ServiceRequestController`) exposes only the methods needed by the LWC.
- The LWC handles loading, error states, success feedback, and recent request display.
- The service methods are bulk-safe and validate all inputs before performing DML.

## Metadata Summary

### Custom Object

- `Service_Request__c`
- Auto Number Name format: `SR-{0000}`

### Custom Fields

- `Customer_Email__c` — Email, required
- `Status__c` — Picklist (`New`, `In Progress`, `Resolved`)
- `Description__c` — Long Text Area
- `Resolution_Notes__c` — Long Text Area
- `Priority__c` — Picklist (`Low`, `Medium`, `High`)

## Apex Overview

### `ServiceRequestService`

- `createRequests(List<CreateRequestInput>)`
- `resolveRequests(List<ResolveRequestInput>)`
- `getRecentRequests(Integer)`

Validation includes:

- required email
- valid email format
- allowed priority values
- required resolution notes when resolving
- basic CRUD / field access checks

### `ServiceRequestController`

- `createServiceRequest(String email, String description, String priority)`
- `getRecentServiceRequests()`

## LWC Overview

### `serviceRequestForm`

Features:

- captures email, description, and priority
- creates a service request through Apex
- displays the created record Id
- handles loading and error states
- shows the five most recent service requests

## Agentforce Bonus Approach

If Agentforce were enabled, I would expose a dedicated action that reuses `ServiceRequestService.resolveRequests(...)`.

Suggested flow:

1. Agent identifies a `Service_Request__c` record that should be resolved.
2. An Agentforce action generates draft resolution notes from the request description and context.
3. The action calls Apex to set `Status__c = 'Resolved'` and save `Resolution_Notes__c`.

This keeps AI orchestration thin and ensures all business rules stay centralized in Apex.

## Setup

## Prerequisites

- Salesforce CLI installed and available as `sf`
- An authenticated org or scratch org
- Node.js and npm installed

## Deploy Metadata

```bash
sf org login web --alias acme-dev --instance-url https://login.salesforce.com --set-default
sf project deploy start -d force-app
sf org assign permset --name Service_Request_Access
```

If you are using a sandbox, replace `https://login.salesforce.com` with `https://test.salesforce.com`.

## Run Apex Tests

```bash
sf apex run test --tests ServiceRequestServiceTest --code-coverage --result-format human
```

## Run LWC Unit Tests

```bash
npm install
npm test -- --runInBand
```

## Use the LWC

1. Open Lightning App Builder.
2. Add the `Service Request Form` component to a Home page or App page.
3. Save and activate the page.

## Assumptions

- The reviewer deploys this into an org where the running user has access to custom objects and Apex.
- `Status__c` defaults to `New` during creation.
- Resolution is handled through Apex service logic, even though the LWC currently focuses on create use cases.
- `Priority__c` is enforced as required in the LWC and Apex validation.
- The recent requests bonus is intentionally lightweight and optimized for quick demo value.
# acme-services-salesforce
