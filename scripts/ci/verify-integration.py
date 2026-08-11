#!/usr/bin/env python3
from __future__ import annotations
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT = ROOT / 'force-app' / 'main' / 'default'
NS = {'m': 'http://soap.sforce.com/2006/04/metadata'}
errors: list[str] = []

named = DEFAULT / 'namedCredentials' / 'Warehouse_Postal_API.namedCredential-meta.xml'
external = DEFAULT / 'externalCredentials' / 'Warehouse_Postal_External.externalCredential-meta.xml'
service = DEFAULT / 'classes' / 'WarehousePostalService.cls'
test = DEFAULT / 'classes' / 'WarehousePostalServiceTest.cls'

for path in (named, external, service, test):
    if not path.exists():
        errors.append(f'Missing Week 11 integration artifact: {path.relative_to(ROOT)}')

if named.exists():
    root = ET.parse(named).getroot()
    values = [n.findtext('m:parameterValue', namespaces=NS) for n in root.findall('m:namedCredentialParameters', NS)]
    refs = [n.findtext('m:externalCredential', namespaces=NS) for n in root.findall('m:namedCredentialParameters', NS)]
    if 'https://api.zippopotam.us' not in values:
        errors.append('Warehouse_Postal_API must point to the live Zippopotam.us endpoint.')
    if 'Warehouse_Postal_External' not in refs:
        errors.append('Warehouse_Postal_API must reference Warehouse_Postal_External.')

if external.exists():
    root = ET.parse(external).getroot()
    if root.findtext('m:authenticationProtocol', namespaces=NS) != 'NoAuthentication':
        errors.append('Public postal API external credential must use NoAuthentication.')
    principals = [
        n.findtext('m:parameterName', namespaces=NS)
        for n in root.findall('m:externalCredentialParameters', NS)
        if n.findtext('m:parameterType', namespaces=NS) == 'NamedPrincipal'
    ]
    if 'Anonymous' not in principals:
        errors.append('Warehouse_Postal_External must declare the Anonymous named principal.')

if service.exists():
    text = service.read_text(encoding='utf-8')
    if 'callout:Warehouse_Postal_API/' not in text:
        errors.append('Postal service must call the Named Credential alias, not a raw URL.')
    if 'https://' in text or 'http://' in text:
        errors.append('Runtime postal service must not hard-code an external URL.')

if test.exists():
    text = test.read_text(encoding='utf-8')
    if 'implements HttpCalloutMock' not in text or 'Test.setMock(HttpCalloutMock.class' not in text:
        errors.append('Postal integration tests must isolate live HTTP with HttpCalloutMock.')

principal = 'Warehouse_Postal_External-Anonymous'
allowed = {'Logistics_Coordinator', 'Warehouse_Manager', 'Warehouse_Operator'}
for path in (DEFAULT / 'permissionsets').glob('*.permissionset-meta.xml'):
    root = ET.parse(path).getroot()
    granted = {
        n.findtext('m:externalCredentialPrincipal', namespaces=NS)
        for n in root.findall('m:externalCredentialPrincipalAccesses', NS)
        if n.findtext('m:enabled', namespaces=NS) == 'true'
    }
    if path.name.replace('.permissionset-meta.xml', '') in allowed:
        if principal not in granted:
            errors.append(f'{path.name} must grant the postal external credential principal.')
    elif principal in granted:
        errors.append(f'{path.name} must not grant the postal external credential principal.')

if errors:
    print('\n'.join(f'ERROR: {item}' for item in errors))
    sys.exit(1)
print('Integration check passed: live endpoint is credential-backed, mocked in tests, and principal access is least-privilege.')
