import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getAllocationQueue from '@salesforce/apex/WarehouseOutboundController.getAllocationQueue';
import getPickingQueue from '@salesforce/apex/WarehouseOutboundController.getPickingQueue';
import getPackingQueue from '@salesforce/apex/WarehouseOutboundController.getPackingQueue';
import getShippingQueue from '@salesforce/apex/WarehouseOutboundController.getShippingQueue';
import allocateOrder from '@salesforce/apex/WarehouseOutboundController.allocateOrder';
import completePick from '@salesforce/apex/WarehouseOutboundController.completePick';
import packOrder from '@salesforce/apex/WarehouseOutboundController.packOrder';
import shipPackage from '@salesforce/apex/WarehouseOutboundController.shipPackage';
import validateOrderDestination from '@salesforce/apex/WarehousePostalController.validateOrderDestination';

const ORDER_COLUMNS = [
    { label: 'Order', fieldName: 'orderNumber' },
    { label: 'Customer', fieldName: 'customerName' },
    { label: 'Warehouse', fieldName: 'warehouseName' },
    { label: 'Priority', fieldName: 'priority' },
    { label: 'Required Ship', fieldName: 'requiredShipDate', type: 'date' },
    { label: 'Status', fieldName: 'status' },
    {
        type: 'button', initialWidth: 110,
        typeAttributes: { label: 'Allocate', name: 'allocate', variant: 'brand-outline' }
    }
];

const PICK_COLUMNS = [
    { label: 'Task', fieldName: 'taskNumber' },
    { label: 'Order', fieldName: 'orderNumber' },
    { label: 'Product', fieldName: 'productName' },
    { label: 'Source Bin', fieldName: 'sourceBin' },
    { label: 'Qty', fieldName: 'quantity', type: 'number' },
    { label: 'Picked', fieldName: 'pickedQuantity', type: 'number' },
    { label: 'Remaining', fieldName: 'remainingQuantity', type: 'number' },
    {
        type: 'button', initialWidth: 100,
        typeAttributes: { label: 'Pick', name: 'pick', variant: 'brand-outline' }
    }
];

const PACK_COLUMNS = [
    { label: 'Order', fieldName: 'orderNumber' },
    { label: 'Customer', fieldName: 'customerName' },
    { label: 'Warehouse', fieldName: 'warehouseName' },
    { label: 'Priority', fieldName: 'priority' },
    { label: 'Required Ship', fieldName: 'requiredShipDate', type: 'date' },
    {
        type: 'button', initialWidth: 100,
        typeAttributes: { label: 'Pack', name: 'pack', variant: 'brand-outline' }
    }
];

const SHIP_COLUMNS = [
    { label: 'Package', fieldName: 'packageNumber' },
    { label: 'Order', fieldName: 'orderNumber' },
    { label: 'Warehouse', fieldName: 'warehouseName' },
    { label: 'Weight', fieldName: 'weight', type: 'number' },
    { label: 'Destination', fieldName: 'destination' },
    { label: 'Validated', fieldName: 'destinationValidated', type: 'boolean', initialWidth: 100 },
    { label: 'Packed At', fieldName: 'packedAt', type: 'date' },
    { label: 'Status', fieldName: 'status' },
    {
        type: 'button', initialWidth: 100,
        typeAttributes: { label: 'Ship', name: 'ship', variant: 'brand' }
    }
];

export default class WarehouseOutboundWorkspace extends LightningElement {
    @api warehouseId;

    orderColumns = ORDER_COLUMNS;
    pickColumns = PICK_COLUMNS;
    packColumns = PACK_COLUMNS;
    shipColumns = SHIP_COLUMNS;

    allocationRows = [];
    pickRows = [];
    packingRows = [];
    shippingRows = [];

    selectedPick;
    selectedPack;
    selectedPackage;
    pickQuantity;
    pickNotes = '';
    packageWeight = 0;
    packNotes = '';
    carrier = '';
    trackingNumber = '';
    shipNotes = '';
    isSaving = false;

    allocationWire;
    pickingWire;
    packingWire;
    shippingWire;

    @wire(getAllocationQueue, { warehouseId: '$warehouseId' })
    wiredAllocation(result) {
        this.allocationWire = result;
        if (result.data) this.allocationRows = result.data;
        else if (result.error) this.handleLoadError('allocation queue', result.error);
    }

    @wire(getPickingQueue, { warehouseId: '$warehouseId' })
    wiredPicking(result) {
        this.pickingWire = result;
        if (result.data) this.pickRows = result.data;
        else if (result.error) this.handleLoadError('picking queue', result.error);
    }

    @wire(getPackingQueue, { warehouseId: '$warehouseId' })
    wiredPacking(result) {
        this.packingWire = result;
        if (result.data) this.packingRows = result.data;
        else if (result.error) this.handleLoadError('packing queue', result.error);
    }

    @wire(getShippingQueue, { warehouseId: '$warehouseId' })
    wiredShipping(result) {
        this.shippingWire = result;
        if (result.data) this.shippingRows = result.data;
        else if (result.error) this.handleLoadError('shipping queue', result.error);
    }

    get hasAllocationRows() { return this.allocationRows.length > 0; }
    get hasPickRows() { return this.pickRows.length > 0; }
    get hasPackingRows() { return this.packingRows.length > 0; }
    get hasShippingRows() { return this.shippingRows.length > 0; }
    get selectedDestinationValidated() { return this.selectedPackage?.destinationValidated === true; }
    get selectedDestinationStatus() { return this.selectedDestinationValidated ? 'Validated' : 'Validation required'; }

    async handleOrderAction(event) {
        const row = event.detail.row;
        this.isSaving = true;
        try {
            const result = await allocateOrder({ orderId: row.orderId });
            this.toast('Order allocated', `${result.pickTaskCount} pick task(s) created for ${result.allocatedQuantity} units.`, 'success');
            await this.refreshAll();
        } catch (error) {
            this.showError('Allocation failed', error);
        } finally {
            this.isSaving = false;
        }
    }

    handlePickAction(event) {
        this.selectedPick = event.detail.row;
        this.pickQuantity = this.selectedPick.remainingQuantity;
        this.pickNotes = '';
    }

    handlePackAction(event) {
        this.selectedPack = event.detail.row;
        this.packageWeight = 0;
        this.packNotes = '';
    }

    handleShipAction(event) {
        this.selectedPackage = event.detail.row;
        this.carrier = '';
        this.trackingNumber = '';
        this.shipNotes = '';
    }

    handlePickQuantity(event) { this.pickQuantity = Number(event.target.value); }
    handlePickNotes(event) { this.pickNotes = event.target.value; }
    handlePackageWeight(event) { this.packageWeight = Number(event.target.value || 0); }
    handlePackNotes(event) { this.packNotes = event.target.value; }
    handleCarrier(event) { this.carrier = event.target.value; }
    handleTracking(event) { this.trackingNumber = event.target.value; }
    handleShipNotes(event) { this.shipNotes = event.target.value; }

    async submitPick() {
        if (!this.pickQuantity || this.pickQuantity <= 0 || this.pickQuantity > this.selectedPick.remainingQuantity) {
            this.toast('Check quantity', 'Enter a quantity within the remaining pick amount.', 'warning');
            return;
        }
        this.isSaving = true;
        try {
            const result = await completePick({
                pickTaskId: this.selectedPick.taskId,
                quantity: this.pickQuantity,
                notes: this.pickNotes
            });
            this.toast('Pick recorded', `${result.pickedQuantity} total picked for ${this.selectedPick.taskNumber}.`, 'success');
            this.selectedPick = null;
            await this.refreshAll();
        } catch (error) {
            this.showError('Pick failed', error);
        } finally {
            this.isSaving = false;
        }
    }

    async submitPack() {
        if (this.packageWeight < 0) {
            this.toast('Check weight', 'Package weight cannot be negative.', 'warning');
            return;
        }
        this.isSaving = true;
        try {
            await packOrder({ orderId: this.selectedPack.orderId, weight: this.packageWeight, notes: this.packNotes });
            this.toast('Package ready', `${this.selectedPack.orderNumber} is ready for shipping.`, 'success');
            this.selectedPack = null;
            await this.refreshAll();
        } catch (error) {
            this.showError('Packing failed', error);
        } finally {
            this.isSaving = false;
        }
    }


    async validateSelectedDestination() {
        if (!this.selectedPackage?.orderId) return;
        this.isSaving = true;
        try {
            const result = await validateOrderDestination({ orderId: this.selectedPackage.orderId });
            const destination = [result.city, result.region, result.postalCode, result.countryCode]
                .filter(Boolean)
                .filter((value, index, items) => items.indexOf(value) === index)
                .join(', ');
            this.selectedPackage = {
                ...this.selectedPackage,
                destinationValidated: true,
                destination,
                city: result.city,
                region: result.region,
                postalCode: result.postalCode,
                countryCode: result.countryCode
            };
            this.toast('Destination validated', `${destination} confirmed by ${result.source}.`, 'success');
            await this.refreshAll();
        } catch (error) {
            this.showError('Destination validation failed', error);
        } finally {
            this.isSaving = false;
        }
    }

    async submitShip() {
        if (!this.selectedDestinationValidated) {
            this.toast('Destination validation required', 'Validate the current country and postal code before release.', 'warning');
            return;
        }
        if (!this.carrier?.trim() || !this.trackingNumber?.trim()) {
            this.toast('Shipping details required', 'Enter both carrier and tracking number.', 'warning');
            return;
        }
        this.isSaving = true;
        try {
            await shipPackage({
                packageId: this.selectedPackage.packageId,
                carrier: this.carrier,
                trackingNumber: this.trackingNumber,
                notes: this.shipNotes
            });
            this.toast('Shipment released', `${this.selectedPackage.packageNumber} left the warehouse.`, 'success');
            this.selectedPackage = null;
            await this.refreshAll();
        } catch (error) {
            this.showError('Shipping failed', error);
        } finally {
            this.isSaving = false;
        }
    }

    async handleRefresh() { await this.refreshAll(); }

    async refreshAll() {
        const jobs = [this.allocationWire, this.pickingWire, this.packingWire, this.shippingWire]
            .filter(Boolean)
            .map((result) => refreshApex(result));
        await Promise.all(jobs);
    }

    handleLoadError(queue, error) {
        this.showError(`Unable to load ${queue}`, error);
    }

    showError(title, error) {
        const message = error?.body?.message || error?.message || 'Unexpected error.';
        this.toast(title, message, 'error');
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
