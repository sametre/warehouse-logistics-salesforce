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
