# Warehouse Management & Logistics

Salesforce DX project for the classroom Warehouse Management & Logistics application.

The first development slice covers warehouse locations, bin locations, inventory balances, inventory transactions, inbound shipments, and a small inventory workspace in Lightning Experience.

## Current scope

- Warehouse and bin location metadata
- Inventory and inventory transaction metadata
- Inbound shipment and shipment line metadata
- Inventory service and controller in Apex
- Apex tests for receiving stock and inventory summary
- Lightning Web Component inventory workspace
- Permission set, tabs, and Lightning application
- Scratch org definition and deployment manifest

## Local workflow

```bash
sf org login web --alias warehouse-dev
sf project deploy start --source-dir force-app --target-org warehouse-dev
sf apex run test --target-org warehouse-dev --test-level RunLocalTests --wait 20
```

The project uses Salesforce API version 67.0.
