#!/usr/bin/env python3
"""Synchronize src/ into the Roblox XML place, preserving all existing world instances."""
from pathlib import Path
import argparse, hashlib, json, re, subprocess, tempfile, xml.etree.ElementTree as ET
ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--input', type=Path)
p.add_argument('--output', type=Path, default=ROOT/'RagdollSandbox_v3_1.rbxlx')
p.add_argument('--luau-compile', help='Official Luau compiler executable; compiles every exported script')
p.add_argument('--luau', help='Official Luau interpreter executable; runs regenerated regression tests')
args=p.parse_args()
source=args.input or (args.output if args.output.exists() else ROOT/'RagdollSandbox_v3_0.rbxlx')
ET.register_namespace('xsi','http://www.w3.org/2001/XMLSchema-instance')
tree=ET.parse(source);root=tree.getroot()
items={};refs={}
def name(item):return item.findtext('./Properties/string[@name="Name"]')
def walk(item,parent=''):
    path=parent+'/'+name(item);items[path]=item;refs[item.get('referent')]=item
    for child in item.findall('Item'):walk(child,path)
for item in root.findall('Item'):walk(item)
def non_source(item):
    copy=ET.fromstring(ET.tostring(item.find('Properties')))
    for prop in list(copy):
        if prop.get('name')=='Source':copy.remove(prop)
    return ET.tostring(copy)
before={ref:non_source(item) for ref,item in refs.items()}
manifest=[];changed=0;added=0
for file in sorted((ROOT/'src').rglob('*.luau')):
    path='/'+file.relative_to(ROOT/'src').with_suffix('').as_posix()
    item=items.get(path)
    if item is None:
        parent, leaf=path.rsplit('/',1)
        assert parent in items,f'Missing Studio parent: {parent}'
        ref='RBX_V31_'+hashlib.sha256(path.encode()).hexdigest()[:20]
        assert ref not in refs
        item=ET.SubElement(items[parent],'Item',{'class':'ModuleScript','referent':ref})
        props=ET.SubElement(item,'Properties')
        ET.SubElement(props,'string',{'name':'Name'}).text=leaf
        ET.SubElement(props,'ProtectedString',{'name':'Source'})
        items[path]=item;refs[ref]=item;added+=1
    prop=item.find('./Properties/ProtectedString[@name="Source"]')
    assert prop is not None,f'Not a script: {path}'
    text=file.read_text()
    changed+=int(prop.text!=text);prop.text=text
    manifest.append({'path':path,'file':file.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(text.encode()).hexdigest()})
args.output.parent.mkdir(parents=True,exist_ok=True)
tree.write(args.output,encoding='UTF-8',xml_declaration=True)
exported=ET.parse(args.output).getroot();actual=list(exported.iter('Item'))
refmap={i.get('referent'):i for i in actual}
assert len(refmap)==len(actual),'Duplicate referents'
for ref,props in before.items():assert non_source(refmap[ref])==props,f'World property changed: {ref}'
for prop in exported.iter('Ref'):assert prop.text in (None,'null','nil') or prop.text in refmap,prop.text
actual_scripts=exported.findall('.//ProtectedString[@name="Source"]')
assert len(actual_scripts)==len(manifest),'Untracked or missing script sources'
with tempfile.TemporaryDirectory() as d:
    for n,row in enumerate(manifest):
        item=refmap[items[row['path']].get('referent')]
        text=item.findtext('./Properties/ProtectedString[@name="Source"]')
        assert text==(ROOT/row['file']).read_text(),row['path']
        if args.luau_compile:
            temp=Path(d)/f'{n}.luau';temp.write_text(text)
            result=subprocess.run([args.luau_compile,str(temp)],capture_output=True,text=True)
            assert result.returncode==0,(row['path'],result.stderr)
report={'place':args.output.name,'scripts':len(manifest),'instances':len(actual),'new_modules_this_export':added,'changed_sources_this_export':changed,'sha256':hashlib.sha256(args.output.read_bytes()).hexdigest(),'xml_and_references':'PASS','original_world_properties':'PASS','source_place_match':'PASS','luau_compile':'PASS' if args.luau_compile else 'NOT RUN','roblox_studio_multiplayer_visual_test':'NOT RUN: Studio unavailable in this environment'}
if args.luau:
    import sys
    for builder in ('build_tests.py','build_freecam_tests.py'):
        subprocess.run([sys.executable,str(ROOT/'tests'/builder)],check=True)
    counts=[]
    for filename in ('gameplay_tests.luau','freecam_tests.luau'):
        result=subprocess.run([args.luau,str(ROOT/'tests'/filename)],capture_output=True,text=True)
        assert result.returncode==0,result.stdout+result.stderr
        counts.append(int(re.findall(r'PASS: (\d+)',result.stdout)[-1]))
        print(result.stdout.strip())
    report['regression_assertions']=sum(counts);report['regression_tests']='PASS (current sources; mocked Roblox services)'
(ROOT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(ROOT/'Pruefbericht.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
