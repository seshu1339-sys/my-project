"""Catalog helpers; no external services, no website integration."""
import json,sys
from pathlib import Path
sys.dont_write_bytecode=True
ROOT=Path('G:/Locamarket HD Images/library')
def pairs(s):return [tuple(p.split('|')) for p in s.strip().split(';')]
FLAVORS=pairs('Almond|బాదం;Pistachio|పిస్తా;Cashew|జీడిపప్పు;Coconut|కొబ్బరి;Chocolate|చాక్లెట్;Vanilla|వెనిల్లా;Strawberry|స్ట్రాబెర్రీ;Mango|మామిడి;Banana|అరటి;Blueberry|బ్లూబెర్రీ;Raspberry|రాస్ప్‌బెర్రీ;Orange|నారింజ;Lemon|నిమ్మ;Pineapple|అనాస;Peach|పీచ్;Cherry|చెర్రీ;Apple|ఆపిల్;Walnut|అక్రోట్;Honey|తేనె;Caramel|కారమెల్;Coffee|కాఫీ;Rose|రోజా;Saffron|కుంకుమపువ్వు;Cardamom|యాలకులు;Dates|ఖర్జూరం;Fig|అత్తి;Apricot|ఆప్రికాట్;Hazelnut|హేజల్‌నట్;Butterscotch|బటర్‌స్కాచ్;Blackberry|బ్లాక్‌బెర్రీ')
def rows(data,suffix='',te_suffix=''):
    return [(en+suffix,te+te_suffix) for en,te in pairs(data)]
def flavored(roots,flavors):
    return [(f'{enf} {en}',f'{tef} {te}') for enf,tef in flavors for en,te in pairs(roots)]
def interleave(groups):
    return [g[i] for i in range(max(map(len,groups),default=0)) for g in groups if i<len(g)]
def canonical(s,slug):
    s=slug(s)
    for word in ['-pouch','-packet','-bottle','-jar','-block']:
        s=s.replace(word,'')
    return {'whole-wheat-flour':'whole-wheat-atta','refined-wheat-flour':'maida','semolina':'sooji','mobile-desk-stand':'phone-stand','mobile-grip-holder':'phone-grip','usb-wall-charger':'phone-charger','wired-earphones':'wired-earphone','tempered-glass-screen-protector':'screen-protector'}.get(s,s)
def save_candidates(category,candidates,batch):
    sys.path.insert(0,str(ROOT));import build_library as lib
    existing=lib.catalog();known={(r['category'],r['file name']) for r in existing}
    ready_names={(r['category'],canonical(r['item name'],lib.slug)) for r in existing if (ROOT/r['category']/r['file name']).exists() or r.get('catalog_batch')==batch}
    saved=len(list((ROOT/category).glob('*.png')))
    reserved=sum(r['category']==category and r.get('catalog_batch')==batch and not (ROOT/category/r['file name']).exists() for r in existing)
    need=max(0,100-saved-reserved)
    added=[]
    for en,te in candidates:
        filename=lib.slug(en)+'.png'
        if (category,filename) in known or (category,canonical(en,lib.slug)) in ready_names:continue
        if need==0:break
        prompt=lib.SPEC.format(subject=en)
        prompt+=' Every surface must be completely unprinted: no labels, pictures, lettering, digits, graphics or ingredient illustrations. Exactly one retail item or one single plain sealed transparent container of the named loose food, liquid or powder. Never use a bowl, plate, serving glass, spoon, garnish, ingredient prop or any object outside the one retail product. No whole fruit, ice cubes or decorative solids inside drink bottles. No bags, clusters or assortments of unwrapped whole produce. A single piece of a cooked snack or sweet is one item. No multiple varieties.'
        if category=='meat-and-fish':prompt+=' Clean commercially prepared RAW meat or seafood only, never a cooked meal. Exactly one named cut, fillet, steak, whole fish, shellfish or piece; no blood splashes, ice, packaging, herbs, citrus wedges or garnish.'
        added.append({'item name':en,'Telugu name':te,'category':category,'file name':filename,'prompt':prompt,'catalog_batch':batch})
        known.add((category,filename));ready_names.add((category,canonical(en,lib.slug)));need-=1
    if need:raise RuntimeError(f'{category}: need {need} more named candidates')
    path=ROOT/'existing-items.json';extra=json.loads(path.read_text(encoding='utf-8'))
    extra.extend(added);path.write_text(json.dumps(extra,ensure_ascii=False,indent=2),encoding='utf-8');lib.refresh()
    return {'category':category,'added':len(added),'saved':saved,'already_reserved':reserved}
