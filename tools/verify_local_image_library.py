"""Verify only local product files, CSVs and metadata in the authorized G folder."""
import csv,hashlib,json,re,sys
from pathlib import Path
from PIL import Image
sys.dont_write_bytecode=True
ROOT=Path('G:/Locamarket HD Images/library')
sys.path.insert(0,str(ROOT))
import build_library as lib
from local_image_catalog_common import canonical

def verify():
    rows=lib.refresh()
    reused={str(Path(p).resolve()) for p in json.loads((ROOT/'reuse-report.json').read_text(encoding='utf-8'))['imported']}
    files=[];counts=[];errors=[];hashes={}
    for category in lib.DATA:
        folder=ROOT/category;images=sorted(folder.glob('*.png'))
        csvrows=list(csv.DictReader((folder/'items.csv').open(encoding='utf-8-sig')))
        if {r['file name'] for r in csvrows}!={p.name for p in images}:errors.append({'category':category,'error':'CSV and PNG names differ'})
        if any(not r['item name'] or not r['Telugu name'] or r['category']!=category for r in csvrows):errors.append({'category':category,'error':'Missing or incorrect CSV fields'})
        for p in images:
            try:
                with Image.open(p) as im:
                    im.load()
                    if im.format!='PNG' or im.mode!='RGB' or im.size!=(1024,1024):raise ValueError('Expected 1024x1024 RGB PNG')
                    if not all(im.getpixel(xy)==(255,255,255) for xy in [(0,0),(1023,0),(0,1023),(1023,1023)]):raise ValueError('Non-white corner pixel')
                if not re.fullmatch('[a-z0-9]+(?:-[a-z0-9]+)*\\.png',p.name):raise ValueError('Filename does not match convention')
                digest=hashlib.sha256(p.read_bytes()).hexdigest()
                if digest in hashes:errors.append({'file':str(p.relative_to(ROOT)),'error':'Duplicate image hash','other':hashes[digest]})
                hashes[digest]=str(p.relative_to(ROOT))
                files.append({'file':str(p.relative_to(ROOT)),'size':[1024,1024],'format':'PNG','white_corners':True,'sha256':digest,'origin':'reused' if str(p.resolve()) in reused else 'newly-generated'})
            except Exception as exc:errors.append({'file':str(p.relative_to(ROOT)),'error':str(exc)})
        old=sum(str(p.resolve()) in reused for p in images)
        counts.append({'category':category,'newly generated':len(images)-old,'reused existing':old,'total images':len(images),'folder':str(folder)})
    ready={(r['category'],canonical(r['item name'],lib.slug)) for r in rows if (ROOT/r['category']/r['file name']).exists()}
    pending=[r for r in rows if not (ROOT/r['category']/r['file name']).exists() and (r['category'],canonical(r['item name'],lib.slug)) not in ready]
    total=sum(c['total images'] for c in counts)
    complete=not errors and all(c['total images']>=100 for c in counts) and not pending
    report={'complete':complete,'requested_target':2500,'total_saved':total,'newly_generated':sum(c['newly generated'] for c in counts),'reused_existing':sum(c['reused existing'] for c in counts),'remaining_to_target':max(0,2500-total),'validation_failures':errors,'known_pending_items':len(pending),'categories':counts,'files':files}
    for name,value in [('verification.json',report),('pending-items.json',pending)]:
        (ROOT/name).write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf-8')
    with (ROOT/'category-summary.csv').open('w',encoding='utf-8-sig',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(counts[0]));w.writeheader();w.writerows(counts)
    lines=[f'# Product image library — {"COMPLETE" if complete else "INCOMPLETE"}','',f'{total} product images saved: {report["newly_generated"]} newly generated with built-in image_gen; {report["reused_existing"]} suitable existing local photos reused.',f'Target: approximately 2,500 images across 25 categories. Remaining to target: {report["remaining_to_target"]}.','',f'Library folder: {ROOT}','Every category has items.csv with item name, Telugu name, category and file name. CSVs contain only saved files and use UTF-8 with BOM.','Includes distinct product types and named color, material, flavor, source-breed and preparation variants.','', 'Verification checks PNG decoding, dimensions, RGB mode, filenames, four pure-white corners, unique hashes and CSV-to-file matching. Export uses a white 1024x1024 canvas and a maximum 768-pixel product bounding dimension. Visual review sheets are in review/.','No website changes, uploads or deployment were performed.','', '| Category | New | Reused | Total |','|---|---:|---:|---:|']
    lines += [f'| {c["category"]} | {c["newly generated"]} | {c["reused existing"]} | {c["total images"]} |' for c in counts]
    lines += ['', 'Exact catalog prompts: generation-prompts.json. Reviewed correction prompts: qa-correction-prompts.json. Existing-photo provenance: reuse-report.json. Pending named items: pending-items.json. Egg naming reference URLs: egg-catalog-reference-sources.json.']
    (ROOT/'README.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k not in ['files','categories']},indent=2))
    if errors:raise SystemExit(1)
if __name__=='__main__':verify()
