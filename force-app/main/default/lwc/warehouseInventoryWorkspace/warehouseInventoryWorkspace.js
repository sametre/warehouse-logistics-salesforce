import { LightningElement, api, wire } from 'lwc';
import getSummary from '@salesforce/apex/WarehouseInventoryController.getSummary';

const COLUMNS = [
    { label: 'Inventory', fieldName: 'inventoryNumber' },
    { label: 'Product', fieldName: 'productName' },
    { label: 'Warehouse', fieldName: 'warehouseName' },
    { label: 'Bin', fieldName: 'binCode' },
    { label: 'On Hand', fieldName: 'onHand', type: 'number' },
    { label: 'Reserved', fieldName: 'reserved', type: 'number' },
    { label: 'Available', fieldName: 'available', type: 'number' },
    { label: 'Status', fieldName: 'status' }
];

export default class WarehouseInventoryWorkspace extends LightningElement {
    @api warehouseId;

    columns = COLUMNS;
    rows = [];
    recordCount = 0;
    onHand = 0;
    reserved = 0;
    available = 0;
    lowStockCount = 0;
    isLoading = true;

    @wire(getSummary, { warehouseId: '$warehouseId' })
    wiredSummary({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.recordCount = data.recordCount;
            this.onHand = data.onHand;
            this.reserved = data.reserved;
            this.available = data.available;
            this.lowStockCount = data.lowStockCount;
            this.rows = data.rows || [];
        } else if (error) {
            this.rows = [];
            // Lightning surfaces Apex errors in the browser console during development.
            console.error('Unable to load warehouse inventory', error);
        }
    }

    get hasRows() {
        return this.rows.length > 0;
    }
}
