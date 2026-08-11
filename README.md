# Warehouse Management & Logistics

Salesforce DX classroom project for warehouse receiving, putaway, inventory control, and logistics operations.

## Implemented

- Warehouse and typed bin locations (Receiving, Staging, Storage, Picking, Shipping)
- Inventory balance plus immutable-style inventory transaction history
- Inbound shipments and shipment lines
- Receiving tasks with damaged quantity handling
- Putaway tasks with suggested and final destination bins
- Apex services for receipt and bin-to-bin stock movement
- Receiving/putaway Apex tests and negative-path tests
- Lightning Operations Workspace for receiving, putaway, and inventory
- Warehouse Operator permission set and Warehouse Operations app

## Local workflow

```bash
sf org login web --alias warehouse-dev
sf project deploy start --source-dir force-app --target-org warehouse-dev
sf apex run test --target-org warehouse-dev --test-level RunLocalTests --wait 20
sf apex run --file scripts/apex/seed.apex --target-org warehouse-dev
```

After deployment, add **Warehouse Operations Workspace** to a Lightning App Page in App Builder. The optional `warehouseId` property can filter the workspace to one warehouse.

API version: 67.0.

## Outbound fulfillment

The current build also covers order allocation, inventory reservation, pick tasks, packing, package creation, and shipment release. Physical inventory is reduced only when a pick is recorded; allocation uses the reserved quantity so available stock stays accurate.
## Week 07 core automation

When an outbound order moves to **Ready to Allocate**, the active record-triggered Flow `Outbound_Order_Auto_Allocation` calls a bulk-safe invocable Apex action. Apex owns inventory locking, reservation, and pick-task creation; Flow owns orchestration and routes failures to `Warehouse_Automation_Log__c` for manager review.

## Week 10 quality gate

Run the local checks before every push:

```bash
./scripts/ci/run-local-gate.sh
```

With an authenticated development org, run Code Analyzer, a dry-run deploy, and the Week 10 Apex test suite:

```bash
./scripts/ci/run-salesforce-gate.sh warehouse-dev
```

GitHub Actions runs the same static gate on pull requests. Org-side tests run only when the repository secret `SF_AUTH_URL` is configured; the authorization URL must never be committed to the repository.

