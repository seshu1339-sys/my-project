"""Named retail variants for the local image library. Does not generate or deploy."""
import json,sys
from pathlib import Path
sys.dont_write_bytecode=True
ROOT=Path('G:/Locamarket HD Images/library')

def pairs(s):return [tuple(p.split('|')) for p in s.split(';')]
COLORS=pairs('Red|ఎర్ర;Blue|నీలం;Green|ఆకుపచ్చ;Black|నలుపు;White|తెలుపు')
VIVID=pairs('Red|ఎర్ర;Green|ఆకుపచ్చ;Orange|నారింజ రంగు;Yellow|పసుపు రంగు;Purple|ఊదా రంగు')
METALS=pairs('Brass|ఇత్తడి;Copper|రాగి;Bronze|కంచు;Silver|వెండి;Stainless Steel|స్టెయిన్‌లెస్ స్టీల్')
JEWEL=pairs('Gold Tone|బంగారు రంగు;Silver Tone|వెండి రంగు;Rose Gold Tone|రోజ్ గోల్డ్ రంగు;Black|నలుపు;Red|ఎర్ర')
BOTANICALS=pairs('Aloe Vera|కలబంద;Neem|వేప;Rose|రోజా;Cucumber|కీరా;Tea Tree|టీ ట్రీ')
SCENTS=pairs('Lemon|నిమ్మ;Rose|రోజా;Jasmine|మల్లె;Lavender|లావెండర్;Sandalwood|గంధం')

GROUPS=[
('personal-care',BOTANICALS,'Shampoo Bottle|షాంపూ సీసా;Conditioner Bottle|కండిషనర్ సీసా;Hair Oil Bottle|జుట్టు నూనె సీసా;Hair Mask Jar|హెయిర్ మాస్క్ సీసా;Face Wash Tube|ఫేస్ వాష్ ట్యూబ్;Body Wash Bottle|బాడీ వాష్ సీసా;Body Lotion Bottle|బాడీ లోషన్ సీసా;Hand Wash Bottle|హ్యాండ్ వాష్ సీసా;Soap Bar|సబ్బు;Lip Balm Tube|లిప్ బామ్ ట్యూబ్','ingredient'),
('personal-care',COLORS,'Toothbrush|టూత్ బ్రష్;Comb|దువ్వెన;Hair Brush|హెయిర్ బ్రష్;Razor|రేజర్;Tongue Cleaner|నాలుక శుభ్రపరిచే పరికరం;Nail Clipper|గోళ్ల కట్టర్;Tweezers|ట్వీజర్స్;Loofah|లోఫా;Bath Brush|స్నానపు బ్రష్;Soap Case|సబ్బు పెట్టె','color'),
('household-cleaning',SCENTS,'Floor Cleaner Bottle|ఫ్లోర్ క్లీనర్ సీసా;Dishwashing Liquid Bottle|గిన్నెల సబ్బు ద్రవం సీసా;Laundry Liquid Bottle|బట్టల సబ్బు ద్రవం సీసా;Fabric Softener Bottle|ఫ్యాబ్రిక్ సాఫ్టెనర్ సీసా;Glass Cleaner Bottle|గ్లాస్ క్లీనర్ సీసా;Toilet Cleaner Bottle|టాయిలెట్ క్లీనర్ సీసా;Surface Disinfectant Bottle|ఉపరితల శుభ్రపరిచే ద్రవం సీసా;Bathroom Cleaner Bottle|బాత్‌రూమ్ క్లీనర్ సీసా;Kitchen Degreaser Bottle|వంటగది డీగ్రీజర్ సీసా;Air Freshener Bottle|ఎయిర్ ఫ్రెషనర్ సీసా','fragrance'),
('household-cleaning',COLORS,'Broom|చీపురు;Mop|తుడుపు కర్ర;Dustpan|చెత్త చేట;Toilet Brush|టాయిలెట్ బ్రష్;Floor Scrub Brush|నేల రుద్దే బ్రష్;Dish Scrub Brush|గిన్నెల బ్రష్;Microfiber Cloth|మైక్రోఫైబర్ గుడ్డ;Scrub Pad|స్క్రబ్ ప్యాడ్;Cleaning Sponge|శుభ్రపరిచే స్పాంజ్;Window Squeegee|కిటికీ స్క్వీజీ','color'),
('pooja-items',METALS,'Diya|దీపం;Pooja Bell|పూజ గంట;Kalash|కలశం;Pooja Plate|పూజ పళ్ళెం;Incense Holder|అగరుబత్తి స్టాండ్;Camphor Burner|కర్పూర హారతి పాత్ర;Deepam Stand|దీపం స్టాండ్;Panchapatra|పంచపాత్ర;Uddharani|ఉద్ధరిణి;Arati Lamp|హారతి దీపం;Five Wick Lamp|పంచముఖ దీపం;Lotus Lamp|కమలం దీపం;Lakshmi Idol|లక్ష్మీదేవి విగ్రహం;Ganesha Idol|వినాయక విగ్రహం;Krishna Idol|కృష్ణ విగ్రహం;Shiva Lingam|శివలింగం;Nandi Idol|నంది విగ్రహం;Tulsi Pot|తులసి కోట;Temple Gong|దేవాలయ జేగంట;Kumkum Container|కుంకుమ భరిణ','material'),
('baby-and-kids',COLORS,'Baby Feeding Bottle|పిల్లల పాల సీసా;Baby Sippy Cup|పిల్లల సిప్పీ కప్పు;Baby Training Cup|పిల్లల ట్రైనింగ్ కప్పు;Baby Silicone Bowl|పిల్లల సిలికాన్ గిన్నె;Baby Silicone Spoon|పిల్లల సిలికాన్ చెంచా;Baby Bib|పిల్లల బిబ్;Baby Pacifier|పిల్లల పాసిఫైయర్;Baby Teether|పిల్లల టీథర్;Baby Rattle|పిల్లల గిలక్కాయ;Baby Bathtub|పిల్లల స్నానపు టబ్;Baby Potty Seat|పిల్లల పాటీ సీటు;Baby Bath Mug|పిల్లల స్నానపు మగ్గు;Baby Nail Clipper|పిల్లల గోళ్ల కట్టర్;Baby Hair Brush|పిల్లల హెయిర్ బ్రష్;Baby Comb|పిల్లల దువ్వెన;Baby Bottle Drying Rack|పాల సీసాల డ్రైయింగ్ ర్యాక్;Baby Bottle Brush|పాల సీసాల బ్రష్;Baby Soap Case|పిల్లల సబ్బు పెట్టె;Baby Changing Mat|పిల్లల ఛేంజింగ్ మ్యాట్;Baby Blanket|పిల్లల దుప్పటి','color'),
('stationery',COLORS,'Pencil|పెన్సిల్;Ballpoint Pen|బాల్‌పాయింట్ పెన్;Gel Pen|జెల్ పెన్;Fountain Pen|ఫౌంటెన్ పెన్;Highlighter|హైలైటర్;Marker Pen|మార్కర్ పెన్;Crayon|క్రేయాన్;Pencil Sharpener|పెన్సిల్ షార్పనర్;Eraser|రబ్బరు;Ruler|స్కేలు;Scissors|కత్తెర;Stapler|స్టెప్లర్;Notebook|నోటు పుస్తకం;Document Folder|డాక్యుమెంట్ ఫోల్డర్;Binder Clip|బైండర్ క్లిప్;Paper Clip|పేపర్ క్లిప్;Glue Stick|జిగురు స్టిక్;Tape Dispenser|టేప్ డిస్పెన్సర్;Pencil Case|పెన్సిల్ పెట్టె;Clipboard|క్లిప్‌బోర్డ్','color'),
('plastic-items',VIVID,'Plastic Bucket|ప్లాస్టిక్ బకెట్;Plastic Mug|ప్లాస్టిక్ మగ్గు;Plastic Basin|ప్లాస్టిక్ బేసిన్;Plastic Basket|ప్లాస్టిక్ బుట్ట;Plastic Storage Box|ప్లాస్టిక్ నిల్వ పెట్టె;Plastic Chair|ప్లాస్టిక్ కుర్చీ;Plastic Stool|ప్లాస్టిక్ స్టూల్;Plastic Dustbin|ప్లాస్టిక్ చెత్త బుట్ట;Plastic Hanger|ప్లాస్టిక్ హ్యాంగర్;Plastic Funnel|ప్లాస్టిక్ గరాటు;Plastic Plate|ప్లాస్టిక్ పళ్ళెం;Plastic Bowl|ప్లాస్టిక్ గిన్నె;Plastic Tumbler|ప్లాస్టిక్ గ్లాసు;Plastic Food Jar|ప్లాస్టిక్ ఆహార నిల్వ డబ్బా;Plastic Water Bottle|ప్లాస్టిక్ నీటి సీసా;Plastic Jug|ప్లాస్టిక్ జగ్;Plastic Colander|ప్లాస్టిక్ జల్లెడ;Plastic Tray|ప్లాస్టిక్ ట్రే;Plastic Spice Box|ప్లాస్టిక్ మసాలా డబ్బా;Plastic Laundry Basket|ప్లాస్టిక్ బట్టల బుట్ట','color'),
('kitchenware',COLORS,'Ceramic Cup|సెరామిక్ కప్పు;Ceramic Mug|సెరామిక్ మగ్గు;Ceramic Plate|సెరామిక్ పళ్ళెం;Ceramic Bowl|సెరామిక్ గిన్నె;Ceramic Serving Dish|సెరామిక్ వడ్డించే పాత్ర;Ceramic Soup Bowl|సెరామిక్ సూప్ గిన్నె;Ceramic Ramekin|సెరామిక్ రామెకిన్;Ceramic Teapot|సెరామిక్ టీపాట్;Ceramic Milk Creamer|సెరామిక్ పాల పాత్ర;Ceramic Storage Jar|సెరామిక్ నిల్వ డబ్బా','color'),
('kitchenware',VIVID,'Silicone Spatula|సిలికాన్ అట్లకాడ;Silicone Ladle|సిలికాన్ గరిటె;Kitchen Whisk|వంట విస్క్;Kitchen Tongs|వంట పటకారు;Vegetable Peeler|కూరగాయల పీలర్;Kitchen Knife|వంట కత్తి;Pastry Brush|పేస్ట్రీ బ్రష్;Silicone Trivet|సిలికాన్ పాత్ర స్టాండ్;Silicone Oven Mitt|సిలికాన్ ఓవెన్ గ్లోవ్;Silicone Rolling Pin|సిలికాన్ అప్పడాల కర్ర','color'),
('fancy-and-cosmetics',JEWEL,'Hair Clip|జుట్టు క్లిప్;Hair Claw Clip|జుట్టు క్లా క్లిప్;Hair Band|హెయిర్ బ్యాండ్;Hair Pin|జుట్టు పిన్ను;Scrunchie|స్క్రంచీ;Hair Elastic|జుట్టు రబ్బరు;Bangle|గాజు;Bracelet|బ్రేస్‌లెట్;Earring|చెవిపోగు;Finger Ring|వేలి ఉంగరం;Necklace|హారం;Pendant|లాకెట్;Anklet|పట్టీ;Brooch|బ్రోచ్;Bindi Sheet|బొట్టు షీట్;Hand Mirror|చేతి అద్దం;Coin Purse|చిల్లర పర్సు;Handbag|హ్యాండ్‌బ్యాగ్;Keychain|కీచైన్;Makeup Brush|మేకప్ బ్రష్','color'),
('electronics',COLORS,'USB Desk Fan|యూఎస్‌బీ డెస్క్ ఫ్యాన్;Handheld Fan|చేతి ఫ్యాన్;Neck Fan|నెక్ ఫ్యాన్;Clip On Fan|క్లిప్ ఫ్యాన్;Ring Light|రింగ్ లైట్;Table Lamp|టేబుల్ ల్యాంప్;Rechargeable Night Light|రీచార్జబుల్ నైట్ లైట్;Mosquito Bat|దోమల బ్యాట్;Kitchen Weighing Scale|వంటగది తూకం పరికరం;Luggage Scale|లగేజ్ తూకం పరికరం;Electric Chopper|ఎలక్ట్రిక్ చాపర్;Juicer|జ్యూసర్;Stand Mixer|స్టాండ్ మిక్సర్;Food Processor|ఫుడ్ ప్రాసెసర్;Air Fryer|ఎయిర్ ఫ్రయర్;Rice Cooker|రైస్ కుక్కర్;Induction Cooktop|ఇండక్షన్ స్టవ్;Electric Lunchbox|ఎలక్ట్రిక్ లంచ్‌బాక్స్;Heating Pad|హీటింగ్ ప్యాడ్;Hair Dryer|హెయిర్ డ్రయర్','color'),
('mobile-accessories',COLORS,'Silicone Phone Case|సిలికాన్ ఫోన్ కవర్;Rugged Phone Case|రగ్గడ్ ఫోన్ కవర్;Flip Phone Case|ఫ్లిప్ ఫోన్ కవర్;Wallet Phone Case|వాలెట్ ఫోన్ కవర్;Waterproof Phone Pouch|వాటర్‌ప్రూఫ్ ఫోన్ పౌచ్;Magnetic Car Phone Holder|మ్యాగ్నెటిక్ కార్ ఫోన్ హోల్డర్;Bicycle Phone Holder|సైకిల్ ఫోన్ హోల్డర్;Running Armband Phone Holder|ఆర్మ్‌బ్యాండ్ ఫోన్ హోల్డర్;Phone Finger Loop|ఫోన్ ఫింగర్ లూప్;Phone Lanyard|ఫోన్ లాన్యార్డ్;Camera Lens Protector|కెమెరా లెన్స్ గార్డ్;USB C Audio Adapter|యూఎస్‌బీ సీ ఆడియో అడాప్టర్;Lightning Audio Adapter|లైట్నింగ్ ఆడియో అడాప్టర్;USB C Hub|యూఎస్‌బీ సీ హబ్;Dual Port Phone Charger|డ్యూయల్ పోర్ట్ ఫోన్ ఛార్జర్;Wireless Charging Pad|వైర్‌లెస్ ఛార్జింగ్ ప్యాడ్;Wireless Charging Stand|వైర్‌లెస్ ఛార్జింగ్ స్టాండ్;Car Phone Charger|కార్ ఫోన్ ఛార్జర్;Retractable USB Cable|రిట్రాక్టబుల్ యూఎస్‌బీ కేబుల్;USB Cable Organizer|యూఎస్‌బీ కేబుల్ ఆర్గనైజర్','color'),
('clothing-and-footwear',COLORS,'Polo Shirt|పోలో చొక్కా;Hoodie|హూడీ;Sweatshirt|స్వెట్‌షర్ట్;Sweater|స్వెటర్;Cardigan|కార్డిగన్;Jacket|జాకెట్;Track Pants|ట్రాక్ ప్యాంటు;Chinos|చినో ప్యాంటు;Shorts|షార్ట్స్;Cargo Pants|కార్గో ప్యాంటు;Leggings|లెగ్గింగ్స్;Long Skirt|పొడవాటి స్కర్ట్;Kurti|కుర్తీ;Blouse|బ్లౌజు;Palazzo Pants|పలాజో ప్యాంటు;Vest|బనియన్;Nightgown|నైటీ;Dress|డ్రెస్;Flat Shoe|ఫ్లాట్ షూ;Loafer Shoe|లోఫర్ షూ','color'),
]

def extend():
    sys.path.insert(0,str(ROOT));import build_library as lib
    existing=lib.catalog();known={(r['category'],r['file name']) for r in existing}
    extra_path=ROOT/'existing-items.json';extra=json.loads(extra_path.read_text(encoding='utf-8'))
    groups={}
    for category,palette,roots,kind in GROUPS:
        roots=pairs(roots)
        assert len(roots) in [10,20],(category,len(roots))
        rows=[]
        for envar,tevar in palette:
            for en,te in roots:
                name=f'{envar} {en}';filename=lib.slug(name)+'.png'
                prompt=lib.SPEC.format(subject=name)
                prompt+=' Every surface is unprinted: no text, digits, symbols, labels, logos, brand marks, pictures, packaging graphics or measuring numerals. One assembled product only; no separate accessories, food, contents used as decoration, hands, person, mannequin or hanger. Electronic screens must be powered off and entirely blank, with blank unmarked buttons. Containers and tools must be empty, except for the named personal-care or cleaning product in its single retail container.'
                if kind=='color':prompt+=f' The product is the {envar.lower()} retail color variant; apply this color to the housing, fabric, handle or accents while keeping natural metal and functional materials realistic.'
                if kind=='material':prompt+=f' The one item is made from {envar.lower()}, unlit, empty, with no offerings, oil, flowers or separate decorative objects.'
                if kind in ['ingredient','fragrance']:prompt+=' Use one plain blank sealed unbranded container, with no pictures of ingredients and no ingredients or garnish outside it.'
                rows.append({'item name':name,'Telugu name':f'{tevar} {te}','category':category,'file name':filename,'prompt':prompt,'variant':{kind:envar,'product_type':en},'catalog_batch':'nonfood-100-v1'})
        groups.setdefault(category,[]).append(rows)
    added=[];counts={}
    for cat,lists in groups.items():
        saved=len(list((ROOT/cat).glob('*.png')))
        reserved=sum(r['category']==cat and r.get('catalog_batch')=='nonfood-100-v1' and not (ROOT/cat/r['file name']).exists() for r in existing)
        need=max(0,100-saved-reserved)
        candidates=[]
        for i in range(max(map(len,lists))):
            for rows in lists:
                if i<len(rows):candidates.append(rows[i])
        for row in candidates:
            key=(cat,row['file name'])
            if key in known:continue
            if cat=='pooja-items' and row['file name']=='brass-pooja-bell.png':continue
            if cat=='fancy-and-cosmetics' and row['file name'].startswith('gold-tone-') and row['variant']['product_type'] in ['Bangle','Bracelet','Earring','Finger Ring','Necklace','Pendant','Anklet']:continue
            if need==0:break
            extra.append(row);added.append(row);known.add(key);need-=1
        if need:raise RuntimeError(f'Insufficient named variants for {cat}: {need}')
        counts[cat]=sum(r['category']==cat for r in added)
    extra_path.write_text(json.dumps(extra,ensure_ascii=False,indent=2),encoding='utf-8')
    lib.refresh()
    print(json.dumps({'added':len(added),'categories':counts},indent=2))

if __name__=='__main__':extend()
