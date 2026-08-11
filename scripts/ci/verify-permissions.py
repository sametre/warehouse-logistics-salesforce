#!/usr/bin/env python3
from __future__ import annotations
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PERMS = ROOT / 'force-app' / 'main' / 'default' / 'permissionsets'
NS = {'m': 'http://soap.sforce.com/2006/04/metadata'}
errors: list[str] = []

def load(name: str):
    root = ET.parse(PERMS / f'{name}.permissionset-meta.xml').getroot()
    objects = {}
    classes = set()
    for node in root.findall('m:objectPermissions', NS):
        obj = node.findtext('m:object', namespaces=NS)
        objects[obj] = {
            'read': node.findtext('m:allowRead', namespaces=NS) == 'true',
            'create': node.findtext('m:allowCreate', namespaces=NS) == 'true',
            'edit': node.findtext('m:allowEdit', namespaces=NS) == 'true',
            'delete': node.findtext('m:allowDelete', namespaces=NS) == 'true',
            'view_all': node.findtext('m:viewAllRecords', namespaces=NS) == 'true',
            'modify_all': node.findtext('m:modifyAllRecords', namespaces=NS) == 'true',
        }
    for node in root.findall('m:classAccesses', NS):
        if node.findtext('m:enabled', namespaces=NS) == 'true':
            classes.add(node.findtext('m:apexClass', namespaces=NS))
    return objects, classes

def flag(objects, obj, key):
    return objects.get(obj, {}).get(key, False)

def expect(condition: bool, message: str):
    if not condition:
        errors.append(message)

receiver, receiver_classes = load('Warehouse_Receiver')
picker, picker_classes = load('Warehouse_Picker')
packer, packer_classes = load('Warehouse_Packer')
logistics, logistics_classes = load('Logistics_Coordinator')
manager, manager_classes = load('Warehouse_Manager')

expect(flag(receiver, 'Receiving_Task__c', 'create') and flag(receiver, 'Putaway_Task__c', 'edit'),
       'Receiver must be able to create receiving tasks and edit putaway tasks.')
expect(not flag(receiver, 'Pick_Task__c', 'create') and not flag(receiver, 'Shipment__c', 'create'),
       'Receiver must not gain picking or shipping creation rights.')

expect(flag(picker, 'Pick_Task__c', 'create') and flag(picker, 'Pick_Task__c', 'edit'),
       'Picker must be able to create and edit pick tasks.')
expect(flag(picker, 'Inventory__c', 'edit'), 'Picker requires inventory edit for physical picks.')
expect(not flag(picker, 'Package__c', 'create') and not flag(picker, 'Shipment__c', 'create'),
       'Picker must not create packages or shipments.')
expect('WarehousePickingService' in picker_classes and 'WarehouseShippingService' not in picker_classes,
       'Picker Apex access must include picking but exclude shipping service.')

expect(flag(packer, 'Package__c', 'create') and flag(packer, 'Package__c', 'edit'),
       'Packer must be able to create and edit packages.')
expect(not flag(packer, 'Pick_Task__c', 'edit') and not flag(packer, 'Shipment__c', 'create'),
       'Packer must not edit pick tasks or create shipments.')

expect(flag(logistics, 'Shipment__c', 'create') and flag(logistics, 'Shipment__c', 'edit'),
       'Logistics Coordinator must be able to create and edit shipments.')
expect(not flag(logistics, 'Inventory__c', 'edit') and not flag(logistics, 'Receiving_Task__c', 'create'),
       'Logistics Coordinator must not write inventory or receiving tasks.')
expect('WarehouseShippingService' in logistics_classes and 'WarehouseReceivingService' not in logistics_classes,
       'Logistics Apex access must include shipping but exclude receiving service.')

for obj in ('Warehouse__c', 'Inventory__c', 'Inbound_Shipment__c', 'Outbound_Order__c', 'Shipment__c'):
    expect(flag(manager, obj, 'read'), f'Manager must retain read access to {obj}.')
expect(not flag(manager, 'Warehouse_Automation_Log__c', 'edit'),
       'Automation audit log must remain read-only to the warehouse manager.')

for name, objects in [('Receiver', receiver), ('Picker', picker), ('Packer', packer), ('Logistics', logistics), ('Manager', manager)]:
    for obj, permissions in objects.items():
        expect(not permissions['modify_all'], f'{name} must not have Modify All on {obj}.')
        expect(not permissions['delete'], f'{name} must not have delete access on {obj}.')

if errors:
    print('\n'.join(f'ERROR: {item}' for item in errors))
    sys.exit(1)
print('Permission check passed: persona boundaries preserve least privilege and no operational persona has delete/Modify All rights.')
