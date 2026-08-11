#!/usr/bin/env python3
from __future__ import annotations
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT = ROOT / 'force-app' / 'main' / 'default'
MANIFEST = ROOT / 'manifest' / 'package.xml'
NS = {'m': 'http://soap.sforce.com/2006/04/metadata'}
errors: list[str] = []

for path in ROOT.rglob('*.xml'):
    if '.git' in path.parts:
        continue
    try:
        ET.parse(path)
    except ET.ParseError as exc:
        errors.append(f'Invalid XML {path.relative_to(ROOT)}: {exc}')

for path in ROOT.rglob('*.json'):
    if '.git' in path.parts:
        continue
    try:
        json.loads(path.read_text(encoding='utf-8'))
    except Exception as exc:
        errors.append(f'Invalid JSON {path.relative_to(ROOT)}: {exc}')

for cls in (DEFAULT / 'classes').glob('*.cls'):
    meta = cls.with_name(cls.name + '-meta.xml')
    if not meta.exists():
        errors.append(f'Missing Apex metadata pair for {cls.name}')

for meta in (DEFAULT / 'classes').glob('*.cls-meta.xml'):
    cls = meta.with_name(meta.name.replace('-meta.xml', ''))
    if not cls.exists():
        errors.append(f'Missing Apex source pair for {meta.name}')

for bundle in (DEFAULT / 'lwc').iterdir():
    if not bundle.is_dir():
        continue
    name = bundle.name
    for suffix in ('.js', '.html', '.js-meta.xml'):
        if not (bundle / f'{name}{suffix}').exists():
            errors.append(f'LWC bundle {name} missing {name}{suffix}')

mapping = {
    'ApexClass': lambda n: (DEFAULT / 'classes' / f'{n}.cls').exists(),
    'ApexTestSuite': lambda n: (DEFAULT / 'testSuites' / f'{n}.testSuite-meta.xml').exists(),
    'CustomApplication': lambda n: (DEFAULT / 'applications' / f'{n}.app-meta.xml').exists(),
    'CustomObject': lambda n: (DEFAULT / 'objects' / n / f'{n}.object-meta.xml').exists(),
    'Flow': lambda n: (DEFAULT / 'flows' / f'{n}.flow-meta.xml').exists(),
    'PermissionSet': lambda n: (DEFAULT / 'permissionsets' / f'{n}.permissionset-meta.xml').exists(),
    'CustomTab': lambda n: (DEFAULT / 'tabs' / f'{n}.tab-meta.xml').exists(),
    'LightningComponentBundle': lambda n: (DEFAULT / 'lwc' / n).is_dir(),
}

tree = ET.parse(MANIFEST)
root = tree.getroot()
for type_node in root.findall('m:types', NS):
    type_name = type_node.findtext('m:name', namespaces=NS)
    checker = mapping.get(type_name)
    if checker is None:
        continue
    for member in type_node.findall('m:members', NS):
        name = member.text or ''
        if not checker(name):
            errors.append(f'package.xml references missing {type_name}: {name}')

for suite in (DEFAULT / 'testSuites').glob('*.testSuite-meta.xml'):
    suite_root = ET.parse(suite).getroot()
    for node in suite_root.findall('m:testClassName', NS):
        name = node.text or ''
        source = DEFAULT / 'classes' / f'{name}.cls'
        if not source.exists():
            errors.append(f'{suite.name} references missing test class {name}')
        elif '@IsTest' not in source.read_text(encoding='utf-8'):
            errors.append(f'{suite.name} references non-test class {name}')

if errors:
    print('\n'.join(f'ERROR: {item}' for item in errors))
    sys.exit(1)

print('Metadata check passed: XML/JSON, manifest references, Apex pairs, LWC bundles, and test suites are consistent.')
