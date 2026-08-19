# Week 05 — Data Quality Controls

## Implemented controls

| Area | Control | User-facing outcome |
| --- | --- | --- |
| Inventory | `Available__c = On_Hand__c - Reserved__c` formula | Current available stock is calculated consistently. |
| Receiving | Damaged quantity cannot exceed received quantity | User receives a clear save error rather than invalid stock data. |
| Putaway | Destination bin must differ from source bin | Prevents no-op putaway movements. |
| Picking | Picked quantity cannot exceed assigned task quantity | Prevents over-picking. |
| Outbound lines | Ordered quantity must be positive; downstream quantities cannot exceed prior stage | Protects allocation, pick, and pack data. |
| Shipment | Tracking number is required when status is Shipped | Prevents untraceable shipments. |
| Package | Weight cannot be negative | Prevents invalid carrier payloads. |
| Orders | Required ship date cannot predate order date; country code has a validated format | Prevents invalid fulfillment commitments and address data. |

## Duplicate prevention and identifiers

- `Bin_Location__c.Bin_Code__c` is a required, unique external ID.
- Existing integration-facing values should use external IDs rather than matching on record name.
- Duplicate Rules are an org-level configuration and must be activated in the training org after review; they are not deployed as source metadata in this branch.

## Record types and conditional visibility

Use record types to separate operational entry paths: standard shipment processing versus exception handling, and standard inventory maintenance versus cycle-count adjustment. Page layouts should expose exception reason/resolution fields only to the exception record type and limit cycle-count adjustment fields to authorized operators/managers.

## Positive and negative test evidence

| Scenario | Expected result | Evidence status |
| --- | --- | --- |
| Save a receiving task with received 10 and damaged 2 | Save succeeds | Ready for org screenshot |
| Save a receiving task with received 10 and damaged 11 | Save blocked with validation message | Ready for org screenshot |
| Save a putaway task using different source/destination bins | Save succeeds | Ready for org screenshot |
| Save a putaway task using the same source/destination bin | Save blocked with validation message | Ready for org screenshot |
| Mark a shipment Shipped with a tracking number | Save succeeds | Ready for org screenshot |
| Mark a shipment Shipped without a tracking number | Save blocked with validation message | Ready for org screenshot |

## Data-quality decision log

| Decision | Rationale |
| --- | --- |
| Calculate availability with a formula | Avoids duplicated, manually maintained balance values. |
| Validate at record save | Blocks invalid data before downstream automation and reporting consume it. |
| Keep movement history separate from current inventory balance | Maintains an auditable event trail. |
| Use external IDs for integration keys | Supports idempotent upserts and prevents duplicate operational records. |
| Keep duplicate rules in org configuration | Allows matching behavior and alerts to be tuned without changing application source. |
