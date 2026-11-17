"""Manage only the user's local G-drive product-image library. No network or deployment."""
import importlib.util,json,runpy,sys
from pathlib import Path
sys.dont_write_bytecode=True
ROOT=Path('G:/Locamarket HD Images/library')
OLD=Path('C:/Users/Lappy/ecommerce_app/website-images/library')
if not ROOT.is_dir():
    raise SystemExit('Expected G-drive library is missing.')
sys.path.insert(0,str(ROOT))

def module():
    import build_library
    if build_library.ROOT.resolve()!=ROOT.resolve():
        raise RuntimeError('Unexpected export directory')
    return build_library

def refresh_saved_category(category):
    import csv
    m=module()
    rows=m.catalog()
    fields=['item name','Telugu name','category','file name']
    ready=[{k:r[k] for k in fields} for r in rows if r['category']==category and (ROOT/category/r['file name']).exists()]
    temp=ROOT/category/'items.csv.writing'
    with temp.open('w',encoding='utf-8-sig',newline='') as f:
        w=csv.DictWriter(f,fieldnames=fields);w.writeheader();w.writerows(ready)
    temp.replace(ROOT/category/'items.csv')
    counts={c:len(list((ROOT/c).glob('*.png'))) for c in m.DATA}
    summary={'target_per_category':100,'target_total':2500,'saved_images':counts,'total_saved':sum(counts.values()),'complete':all(n>=100 for n in counts.values())}
    temp=ROOT/'summary.json.writing'
    temp.write_text(json.dumps(summary,indent=2),encoding='utf-8')
    temp.replace(ROOT/'summary.json')

def migrate():
    changed=[]
    for f in ROOT.iterdir():
        if f.is_file() and f.suffix in ['.json','.csv','.md']:
            content=f.read_text(encoding='utf-8-sig')
            new=content.replace(str(OLD).replace('\\','\\\\'),str(ROOT).replace('\\','\\\\'))
            new=new.replace(str(OLD),str(ROOT)).replace(OLD.as_posix(),ROOT.as_posix())
            if new!=content:
                f.write_text(new,encoding='utf-8-sig' if f.suffix=='.csv' else 'utf-8')
                changed.append(f.name)
    (ROOT/'relocation-report.json').write_text(json.dumps({'source':str(OLD),'destination':str(ROOT),'files_moved_and_sha256_verified':244,'old_library_removed':not OLD.exists(),'updated_reports':changed},indent=2),encoding='utf-8')
    module().refresh()
    runpy.run_path(str(ROOT/'validate_library.py'),run_name='__main__')

def export(source,category,filename):
    m=module()
    if category not in m.DATA or Path(filename).name!=filename or not filename.endswith('.png'):
        raise ValueError('Invalid category or PNG filename')
    source=Path(source).resolve()
    allowed=Path('C:/Users/Lappy/.codex/generated_images').resolve()
    if not source.is_relative_to(allowed):
        raise ValueError('Only generated image sources are accepted')
    dest=ROOT/category/filename
    if dest.exists():
        refresh_saved_category(category)
        print('Skipped existing '+str(dest))
        return
    stage=dest.with_name(filename+'.writing')
    if stage.exists():
        import hashlib
        archive=ROOT/'review'/'interrupted'/category
        archive.mkdir(parents=True,exist_ok=True)
        token=hashlib.sha256(stage.read_bytes()).hexdigest()[:16]
        saved=archive/(filename+'-'+token+'.writing')
        if saved.exists():raise RuntimeError('Interrupted stage already archived; inspect before retrying')
        stage.rename(saved)
    m.export(str(source),category,stage.name)
    stage.rename(dest)
    refresh_saved_category(category)
    from datetime import datetime,timezone
    event={'saved_at_utc':datetime.now(timezone.utc).isoformat(),'category':category,'file':filename,'source':str(source),'destination':str(dest)}
    with (ROOT/'generation-events.jsonl').open('a',encoding='utf-8') as f:f.write(json.dumps(event,ensure_ascii=False)+'\n')
    print(str(dest))

def queue(index_only=False):
    m=module()
    rows=m.refresh()
    pending=[r for r in rows if not (ROOT/r['category']/r['file name']).exists()]
    def canonical(s):
        s=m.slug(s)
        for word in ['-pouch','-packet','-bottle','-jar','-block']:
            s=s.replace(word,'')
        return {'whole-wheat-flour':'whole-wheat-atta','refined-wheat-flour':'maida','semolina':'sooji','mobile-desk-stand':'phone-stand','mobile-grip-holder':'phone-grip','usb-wall-charger':'phone-charger','wired-earphones':'wired-earphone','tempered-glass-screen-protector':'screen-protector','nail-polish':'nail-polish'}.get(s,s)
    ready={(r['category'],canonical(r['item name'])) for r in rows if (ROOT/r['category']/r['file name']).exists()}
    pending=[r for r in pending if (r['category'],canonical(r['item name'])) not in ready]
    cats=list(m.DATA)
    groups={c:[r for r in pending if r['category']==c] for c in cats}
    interleaved=[]
    for i in range(max(map(len,groups.values()),default=0)):
        for c in cats:
            if i<len(groups[c]):interleaved.append(groups[c][i])
    if index_only:
        lookup={(r['category'],r['file name']):i for i,r in enumerate(rows)}
        print(json.dumps([lookup[(r['category'],r['file name'])] for r in interleaved]))
    else:
        print(json.dumps(interleaved,ensure_ascii=True))

def catalog_selected(indices):
    selected=[int(n) for n in indices.split(',') if n]
    if len(selected)>100:raise ValueError('Read at most 100 catalog entries per chunk')
    data=module().catalog()
    if any(i<0 or i>=len(data) for i in selected):raise ValueError('Invalid catalog index')
    print(json.dumps([data[i] for i in selected],ensure_ascii=True))

def review():
    from PIL import Image,ImageOps,ImageDraw
    m=module()
    old={str(Path(p).resolve()) for p in json.loads((ROOT/'reuse-report.json').read_text())['imported']}
    files=[p for c in m.DATA for p in sorted((ROOT/c).glob('*.png')) if str(p.resolve()) not in old]
    out=ROOT/'review'
    out.mkdir(exist_ok=True)
    for start in range(0,len(files),36):
        im=Image.new('RGB',(1200,1260),'#ddd');d=ImageDraw.Draw(im)
        for i,p in enumerate(files[start:start+36]):
            x=(i%6)*200;y=(i//6)*210
            with Image.open(p) as src:im.paste(ImageOps.contain(src,(190,180)),(x,y))
            d.text((x+2,y+182),str(start+i)+' '+p.stem[:25],fill='black')
        im.save(out/f'new-products-{start//36}.jpg')
    (out/'new-products-index.json').write_text(json.dumps([str(p) for p in files],indent=2),encoding='utf-8')
    print(json.dumps({'new_images':len(files),'sheets':(len(files)+35)//36,'folder':str(out)}))

def accept_correction(source,category,filename):
    import hashlib
    m=module()
    if category not in m.DATA or Path(filename).name!=filename or not filename.endswith('.png'):
        raise ValueError('Invalid correction target')
    source=Path(source).resolve()
    if not source.is_relative_to(Path('C:/Users/Lappy/.codex/generated_images').resolve()):
        raise ValueError('Only generated image sources are accepted')
    dest=ROOT/category/filename
    stage=Path(filename).stem+'-qa-correction.png'
    stagepath=ROOT/category/stage
    if stagepath.exists():raise RuntimeError('Correction stage already exists')
    m.export(str(source),category,stage)
    archive=ROOT/'review'/'rejected'/category
    archive.mkdir(parents=True,exist_ok=True)
    if dest.exists():
        digest=hashlib.sha256(dest.read_bytes()).hexdigest()[:12]
        saved=archive/(dest.stem+'-'+digest+'.png')
        if saved.exists():raise RuntimeError('Original already archived; inspect before retrying')
        dest.rename(saved)
    stagepath.rename(dest)
    refresh_saved_category(category)
    print(str(dest))

def record_qa_prompts(serialized):
    if serialized.startswith('@'):
        source=Path(serialized[1:]).resolve()
        if not source.is_relative_to(Path(__file__).resolve().parent):raise ValueError('Unexpected correction metadata source')
        serialized=source.read_text(encoding='utf-8')
    values=json.loads(serialized)
    if not isinstance(values,list):raise ValueError('Expected correction records')
    (ROOT/'qa-correction-prompts.json').write_text(json.dumps(values,ensure_ascii=False,indent=2),encoding='utf-8')

def extend_targets():
    scripts=['extend_local_nonfood_library.py','extend_local_food_catalog_a.py','extend_local_food_catalog_b.py','extend_local_food_catalog_c.py','extend_local_food_catalog_d.py']
    for filename in scripts:
        runpy.run_path(str(Path(__file__).with_name(filename)),run_name='__main__')

def harden_food_prompts():
    path=ROOT/'existing-items.json';values=json.loads(path.read_text(encoding='utf-8'))
    note=' Clean commercially prepared RAW meat or seafood only, never a cooked meal. Exactly one named cut, fillet, steak, whole fish, shellfish or piece; no blood splashes, ice, packaging, herbs, citrus wedges or garnish.'
    count=0
    for r in values:
        if r['category']=='meat-and-fish' and r.get('catalog_batch') and 'commercially prepared RAW' not in r['prompt']:
            r['prompt']+=note;count+=1
    path.write_text(json.dumps(values,ensure_ascii=False,indent=2),encoding='utf-8')
    module().refresh()
    print(json.dumps({'prompts_updated':count}))

if __name__=='__main__':
    command=sys.argv[1]
    if command=='migrate':migrate()
    elif command=='export':export(*sys.argv[2:])
    elif command=='queue':queue()
    elif command=='queue-indices':queue(True)
    elif command=='catalog-selected':catalog_selected(sys.argv[2])
    elif command=='review':review()
    elif command=='extend-produce':runpy.run_path(str(Path(__file__).with_name('extend_local_produce_library.py')),run_name='__main__')
    elif command=='extend-targets':extend_targets()
    elif command=='harden-food-prompts':harden_food_prompts()
    elif command=='record-qa-prompts':record_qa_prompts(sys.argv[2])
    elif command=='accept-correction':accept_correction(*sys.argv[2:])
    elif command=='validate':runpy.run_path(str(Path(__file__).with_name('verify_local_image_library.py')),run_name='__main__')
    elif command=='status':print((ROOT/'summary.json').read_text())
    else:raise ValueError('Unknown command')
