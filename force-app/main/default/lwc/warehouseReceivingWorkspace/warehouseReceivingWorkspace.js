import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getReceivingQueue from '@salesforce/apex/WarehouseOperationsController.getReceivingQueue';
import getPutawayQueue from '@salesforce/apex/WarehouseOperationsController.getPutawayQueue';
import getActiveBins from '@salesforce/apex/WarehouseOperationsController.getActiveBins';
import receiveLine from '@salesforce/apex/WarehouseOperationsController.receiveLine';
import completePutaway from '@salesforce/apex/WarehouseOperationsController.completePutaway';

const RECEIVING_COLUMNS = [
    { label: 'Shipment', fieldName: 'shipmentNumber' },
    { label: 'Supplier', fieldName: 'supplierName' },
    { label: 'Product', fieldName: 'productName' },
    { label: 'Warehouse', fieldName: 'warehouseName' },
    { label: 'Expected', fieldName: 'expectedQuantity', type: 'number' },
    { label: 'Received', fieldName: 'receivedQuantity', type: 'number' },
    { label: 'Remaining', fieldName: 'remainingQuantity', type: 'number' },
    {
        type: 'button',
        initialWidth: 110,
        typeAttributes: { label: 'Receive', name: 'receive', variant: 'brand-outline' }
    }
];

const PUTAWAY_COLUMNS = [
    { label: 'Task', fieldName: 'taskNumber' },
    { label: 'Product', fieldName: 'productName' },
    { label: 'Warehouse', fieldName: 'warehouseName' },
    { label: 'Source', fieldName: 'sourceBin' },
    { label: 'Suggested', fieldName: 'suggestedBin' },
    { label: 'Quantity', fieldName: 'quantity', type: 'number' },
    {
        type: 'button',
        initialWidth: 120,
        typeAttributes: { label: 'Put Away', name: 'putaway', variant: 'brand-outline' }
    }
];

export default class WarehouseReceivingWorkspace extends LightningElement {
    @api warehouseId;

    receivingColumns = RECEIVING_COLUMNS;
    putawayColumns = PUTAWAY_COLUMNS;
    receivingRows = [];
    putawayRows = [];
    bins = [];
    selectedReceivingLine;
    selectedPutawayTask;
    receivingBinId;
    destinationBinId;
    receivedQuantity;
    damagedQuantity = 0;
    receivingNotes = '';
    putawayNotes = '';
    isSaving = false;

    receivingWireResult;
    putawayWireResult;
    binsWireResult;

    @wire(getReceivingQueue, { warehouseId: '$warehouseId' })
    wiredReceiving(result) {
        this.receivingWireResult = result;
        if (result.data) {
            this.receivingRows = result.data;
        } else if (result.error) {
            this.receivingRows = [];
            this.showError('Unable to load receiving queue', result.error);
        }
    }

    @wire(getPutawayQueue, { warehouseId: '$warehouseId' })
    wiredPutaway(result) {
        this.putawayWireResult = result;
        if (result.data) {
            this.putawayRows = result.data;
        } else if (result.error) {
            this.putawayRows = [];
            this.showError('Unable to load putaway queue', result.error);
        }
    }

    @wire(getActiveBins, { warehouseId: '$warehouseId' })
    wiredBins(result) {
        this.binsWireResult = result;
        if (result.data) {
            this.bins = result.data;
        } else if (result.error) {
            this.bins = [];
            this.showError('Unable to load warehouse bins', result.error);
        }
    }

    get hasReceivingRows() {
        return this.receivingRows.length > 0;
    }

    get hasPutawayRows() {
        return this.putawayRows.length > 0;
    }

    get receivingBinOptions() {
        if (!this.selectedReceivingLine) {
            return [];
        }
        return this.bins
            .filter((bin) =>
                bin.warehouseId === this.selectedReceivingLine.warehouseId &&
                (bin.type === 'Receiving' || bin.type === 'Staging')
            )
            .map((bin) => ({ label: `${bin.label} · ${bin.type}`, value: bin.id }));
    }

    get destinationBinOptions() {
        if (!this.selectedPutawayTask) {
            return [];
        }
        return this.bins
            .filter((bin) =>
                bin.warehouseId === this.selectedPutawayTask.warehouseId &&
                bin.type !== 'Receiving' &&
                bin.type !== 'Shipping'
            )
            .map((bin) => ({ label: `${bin.label} · ${bin.type}`, value: bin.id }));
    }

    handleReceivingAction(event) {
        const row = event.detail.row;
        this.selectedReceivingLine = row;
        this.receivedQuantity = row.remainingQuantity;
        this.damagedQuantity = 0;
        this.receivingNotes = '';

        const defaultBin = this.bins.find((bin) =>
            bin.warehouseId === row.warehouseId && (bin.type === 'Receiving' || bin.type === 'Staging')
        );
        this.receivingBinId = defaultBin ? defaultBin.id : null;
    }

    handlePutawayAction(event) {
        const row = event.detail.row;
        this.selectedPutawayTask = row;
        this.destinationBinId = row.suggestedBinId || null;
        this.putawayNotes = '';
    }

    handleReceivingBinChange(event) {
        this.receivingBinId = event.detail.value;
    }

    handleReceivedQuantityChange(event) {
        this.receivedQuantity = Number(event.target.value);
    }

    handleDamagedQuantityChange(event) {
        this.damagedQuantity = Number(event.target.value || 0);
    }

    handleReceivingNotesChange(event) {
        this.receivingNotes = event.target.value;
    }

    handleDestinationBinChange(event) {
        this.destinationBinId = event.detail.value;
    }

    handlePutawayNotesChange(event) {
        this.putawayNotes = event.target.value;
    }

    async submitReceipt() {
        if (!this.receivingBinId || !this.receivedQuantity || this.receivedQuantity <= 0) {
            this.toast('Check receiving details', 'Select a receiving bin and enter a quantity greater than zero.', 'warning');
            return;
        }

        this.isSaving = true;
        try {
            const result = await receiveLine({
                shipmentLineId: this.selectedReceivingLine.lineId,
                receivingBinId: this.receivingBinId,
                receivedQuantity: this.receivedQuantity,
                damagedQuantity: this.damagedQuantity || 0,
                notes: this.receivingNotes
            });
            this.toast(
                'Receipt completed',
                `${result.acceptedQuantity} accepted, ${result.damagedQuantity} damaged.`,
                result.damagedQuantity > 0 ? 'warning' : 'success'
            );
            this.selectedReceivingLine = null;
            await this.refreshQueues();
        } catch (error) {
            this.showError('Receipt failed', error);
        } finally {
            this.isSaving = false;
        }
    }

    async submitPutaway() {
        if (!this.destinationBinId) {
            this.toast('Destination required', 'Choose the final bin before completing putaway.', 'warning');
            return;
        }

        this.isSaving = true;
        try {
            await completePutaway({
                putawayTaskId: this.selectedPutawayTask.taskId,
                destinationBinId: this.destinationBinId,
                notes: this.putawayNotes
            });
            this.toast('Putaway completed', `${this.selectedPutawayTask.taskNumber} moved successfully.`, 'success');
            this.selectedPutawayTask = null;
            await this.refreshQueues();
        } catch (error) {
            this.showError('Putaway failed', error);
        } finally {
            this.isSaving = false;
        }
    }

    async handleRefresh() {
        await this.refreshQueues();
    }

    async refreshQueues() {
        const jobs = [];
        if (this.receivingWireResult) jobs.push(refreshApex(this.receivingWireResult));
        if (this.putawayWireResult) jobs.push(refreshApex(this.putawayWireResult));
        if (this.binsWireResult) jobs.push(refreshApex(this.binsWireResult));
        await Promise.all(jobs);
    }

    showError(title, error) {
        const message = error?.body?.message || error?.message || 'Unexpected error.';
        this.toast(title, message, 'error');
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
