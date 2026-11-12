"""Meat, eggs and sweets. Egg breed names checked against primary poultry references."""
import json
from local_image_catalog_common import *

SOURCES={
 'chicken_breeds':'https://livestockconservancy.org/wp-content/uploads/2023/07/PickaBreedCHICKEN_FINAL2023.pdf',
 'chicken_shell_colors':'https://publications.mgcafe.uky.edu/sites/publications.ca.uky.edu/files/ASC190.pdf',
 'duck_breeds':'https://livestockconservancy.org/wp-content/uploads/2026/03/PickaBreedDucks2026.pdf',
 'goose_breeds':'https://livestockconservancy.org/wp-content/uploads/2026/03/PickaBreedGeese2026.pdf',
 'turkey_breeds':'https://livestockconservancy.org/wp-content/uploads/2026/03/PickaBreedTurkeys2026.pdf',
}

def meat():
    fish=pairs('Rohu|రోహు;Catla|కట్లా;Tilapia|తిలాపియా;Basa|బాసా;Seer Fish|వంజరం;Salmon|సాల్మన్;Tuna|ట్యూనా;Sea Bass|సీ బాస్;Red Snapper|రెడ్ స్నాపర్;Grouper|గ్రూపర్;Pomfret|చందువ;Cod|కాడ్;Haddock|హ్యాడక్;Hake|హేక్;Pollock|పోలాక్;Halibut|హాలిబట్;Mahi Mahi|మాహి మాహి;Swordfish|స్వోర్డ్‌ఫిష్;Trout|ట్రౌట్;Common Carp|కామన్ కార్ప్')
    cuts=[(f'{en} {form}',f'{te} {teform}') for form,teform in pairs('Whole Fish|పూర్తి చేప;Fish Fillet|చేప ఫిల్లెట్;Fish Steak|చేప ముక్క') for en,te in fish]
    cuts=[(en.replace('Fish Whole Fish','Whole Fish').replace('Fish Fish','Fish'),te) for en,te in cuts]
    poultry=rows('Chicken Thigh|కోడి తొడ;Chicken Whole Leg|పూర్తి కోడి కాలు;Whole Chicken|పూర్తి కోడి;Chicken Tenderloin|చికెన్ టెండర్‌లాయిన్;Chicken Liver|కోడి కాలేయం;Chicken Gizzard|కోడి గిజార్డ్;Chicken Heart|కోడి గుండె;Chicken Neck|కోడి మెడ;Chicken Foot|కోడి పాదం;Chicken Boneless Cube|ఎముకలేని చికెన్ ముక్క;Goat Shank|మేక కాలి ముక్క;Goat Shoulder|మేక భుజం ముక్క;Goat Liver|మేక కాలేయం;Goat Kidney|మేక మూత్రపిండం;Goat Boneless Cube|ఎముకలేని మేక మాంసం ముక్క;Lamb Chop|లాంబ్ చాప్;Lamb Shank|లాంబ్ షాంక్;Duck Breast|బాతు బ్రెస్ట్;Duck Leg|బాతు కాలు;Turkey Breast|టర్కీ బ్రెస్ట్')
    seafood=rows('Whiteleg Shrimp|వైట్‌లెగ్ రొయ్య;Banana Shrimp|బనానా రొయ్య;Brown Shrimp|బ్రౌన్ రొయ్య;Red Shrimp|ఎర్ర రొయ్య;Spot Prawn|స్పాట్ రొయ్య;Giant Freshwater Prawn|పెద్ద మంచినీటి రొయ్య;Langoustine|లాంగుస్టీన్;Mud Crab|మడ పీత;Blue Swimmer Crab|నీలి పీత;Snow Crab|స్నో క్రాబ్;King Crab|కింగ్ క్రాబ్;Dungeness Crab|డంజెనెస్ పీత;Spiny Lobster|స్పైనీ లాబ్‌స్టర్;American Lobster|అమెరికన్ లాబ్‌స్టర్;Slipper Lobster|స్లిప్పర్ లాబ్‌స్టర్;Crayfish|క్రేఫిష్;Mussel|మస్సెల్;Clam|క్లామ్;Oyster|ఆయిస్టర్;Scallop|స్కాలప్;Squid|స్క్విడ్;Cuttlefish|కటిల్‌ఫిష్;Octopus|ఆక్టోపస్')
    return [(en,te) for en,te in interleave([cuts,poultry,seafood]) if en not in ['Rohu Whole Fish','Pomfret Whole Fish']]

def egg_data():
    # Colors describe a representative natural shell, never plumage or dyed eggs.
    uk=[('Araucana','అరౌకానా','pale blue'),('Ameraucana','అమెరౌకానా','pale blue-green'),('Australorp','ఆస్ట్రలార్ప్','light brown'),('Barnevelder','బార్నెవెల్డర్','dark brown'),('Brahma','బ్రహ్మా','light brown'),('Lamona','లమోనా','white'),('Orpington','ఓర్పింగ్టన్','light brown'),('Plymouth Rock','ప్లిమత్ రాక్','brown'),('Rhode Island Red','రోడ్ ఐలాండ్ రెడ్','brown'),('Welsummer','వెల్సమ్మర్','dark brown'),('Naked Neck','నేకెడ్ నెక్','brown')]
    white=pairs('Ancona|అన్కోనా;Andalusian|ఆండలూషియన్;Buttercup|బటర్‌కప్;Campine|క్యాంపైన్;Crevecoeur|క్రేవ్‌కూర్;Cubalaya|క్యూబలయా;Dorking|డార్కింగ్;Hamburg|హాంబర్గ్;Holland|హాలండ్;Houdan|హౌడాన్;La Fleche|లా ఫ్లెష్;Lakenvelder|లాకెన్‌వెల్డర్;Leghorn|లెగ్‌హార్న్;Minorca|మినోర్కా;Polish|పోలిష్;Redcap|రెడ్‌క్యాప్;White Faced Black Spanish|వైట్ ఫేస్డ్ బ్లాక్ స్పానిష్;Spitzhauben|స్పిట్జ్‌హౌబెన్;Sultan|సుల్తాన్;Sumatra|సుమత్రా')
    cream=pairs('Aseel|అసీల్;Belgian Bearded Duccle Bantam|బెల్జియన్ డ్యూకిల్ బాంటమ్;Booted Bantam|బూటెడ్ బాంటమ్;Catalana|కటలానా;Cornish|కార్నిష్;Faverolles|ఫేవరోల్స్;Icelandic|ఐస్‌లాండిక్;Japanese Bantam|జపనీస్ బాంటమ్;Modern Game|మోడర్న్ గేమ్;Nankin|నాంకిన్;Old English Game|ఓల్డ్ ఇంగ్లీష్ గేమ్;Phoenix|ఫీనిక్స్;Russian Orloff|రష్యన్ ఓర్లోఫ్;Sebright|సీబ్రైట్;Shamo|షామో;Yokohama|యోకోహామా')
    brown=pairs('Buckeye|బకాయ్;Chantecler|షాంటెక్లేర్;Cochin|కోచిన్;Delaware|డెలావేర్;Dominique|డొమినిక్;Java|జావా;Jersey Giant|జెర్సీ జెయింట్;Langshan|లాంగ్షాన్;Malay|మలయ్;New Hampshire|న్యూ హాంప్‌షైర్;Rhode Island White|రోడ్ ఐలాండ్ వైట్;Sussex|ససెక్స్')
    chicken=uk+[(en,te,'white') for en,te in white]+[(en,te,'pale cream') for en,te in cream]+[(en,te,'brown') for en,te in brown]
    ducks=[('Ancona','అన్కోనా','pale blue-green'),('Aylesbury','అయిల్స్‌బరీ','white'),('Australian Spotted','ఆస్ట్రేలియన్ స్పాటెడ్','pale green'),('Buff Orpington','బఫ్ ఓర్పింగ్టన్','cream'),('Campbell','క్యాంప్‌బెల్','white'),('Cayuga','కయుగా','natural dark charcoal gray'),('Dutch Hookbill','డచ్ హుక్‌బిల్','pale blue-green'),('Magpie','మ్యాగ్‌పై','white'),('Rouen','రూయెన్','white'),('Indian Runner','ఇండియన్ రన్నర్','pale green'),('Saxony','సాక్సనీ','pale green'),('Silver Appleyard','సిల్వర్ ఆపిల్‌యార్డ్','white'),('Swedish','స్వీడిష్','pale green'),('Welsh Harlequin','వెల్ష్ హార్లెక్విన్','cream')]
    geese=pairs('African|ఆఫ్రికన్;American Buff|అమెరికన్ బఫ్;Chinese|చైనీస్;Cotton Patch|కాటన్ ప్యాచ్;Pilgrim|పిల్‌గ్రిమ్;Pomeranian|పొమెరేనియన్;Roman|రోమన్;Sebastopol|సెబాస్టోపోల్;Shetland|షెట్‌లాండ్;Steinbacher|స్టైన్‌బాచర్;Toulouse|టూలూజ్')
    turkeys=pairs('Beltsville Small White|బెల్ట్స్‌విల్ స్మాల్ వైట్;Black|బ్లాక్;Bourbon Red|బోర్బన్ రెడ్;Standard Bronze|స్టాండర్డ్ బ్రాంజ్;Chocolate|చాక్లెట్;Jersey Buff|జెర్సీ బఫ్;Lavender|లావెండర్;Midget White|మిడ్జెట్ వైట్;Narragansett|నారగన్‌సెట్;Royal Palm|రాయల్ పామ్;Slate|స్లేట్;White Holland|వైట్ హాలండ్')
    groups=[]
    for name,tename,data in [('Chicken','కోడి',chicken),('Duck','బాతు',ducks),('Goose','గూస్',[(en,te,'white') for en,te in geese]),('Turkey','టర్కీ',[(en,te,'cream with fine natural brown speckles') for en,te in turkeys])]:
        groups.append([(f'{en} {name} Egg',f'{te} {tename} గుడ్డు',color) for en,te,color in data])
    return interleave(groups)

def eggs():return [(en,te) for en,te,color in egg_data()]

def sweets():
    laddu=rows('Besan|శనగపిండి;Boondi|బూంది;Motichoor|మోతీచూర్;Wheat|గోధుమ;Sooji|రవ్వ;Coconut|కొబ్బరి;Ragi|రాగి;Millet|చిరుధాన్యాల;Jaggery|బెల్లం;Sesame|నువ్వుల;Peanut|పల్లీ;Dry Fruit|డ్రై ఫ్రూట్;Dates|ఖర్జూరం;Oat|ఓట్;Moong Dal|పెసరపప్పు;Urad Dal|మినపప్పు;Chana Dal|శనగపప్పు;Almond|బాదం;Pistachio|పిస్తా;Cashew|జీడిపప్పు',' Laddu',' లడ్డు')
    barfi=rows('Coconut|కొబ్బరి;Milk|పాల;Besan|శనగపిండి;Almond|బాదం;Pistachio|పిస్తా;Chocolate|చాక్లెట్;Banana|అరటి;Mango|మామిడి;Fig|అత్తి;Dates|ఖర్జూరం;Dry Fruit|డ్రై ఫ్రూట్;Walnut|అక్రోట్;Peanut|పల్లీ;Rose|రోజా;Vanilla|వెనిల్లా;Saffron|కుంకుమపువ్వు;Cashew|జీడిపప్పు;Sesame|నువ్వుల;Ragi|రాగి;Coffee|కాఫీ',' Barfi',' బర్ఫీ')
    halwa=rows('Carrot|క్యారెట్;Beetroot|బీట్‌రూట్;Bottle Gourd|సొరకాయ;Pumpkin|గుమ్మడి;Ash Gourd|బూడిద గుమ్మడి;Almond|బాదం;Cashew|జీడిపప్పు;Wheat|గోధుమ;Sooji|రవ్వ;Karachi|కరాచీ;Bombay|బాంబే;Tirunelveli|తిరునెల్వేలి;Moong Dal|పెసరపప్పు;Corn Flour|మొక్కజొన్న పిండి;Pineapple|అనాస;Banana|అరటి;Papaya|బొప్పాయి;Ragi|రాగి;Sweet Potato|చిలగడదుంప;Dates|ఖర్జూరం',' Halwa Cup',' హల్వా కప్పు')
    peda=rows('Dharwad Peda|ధార్వాడ్ పేడా;Mathura Peda|మథుర పేడా;Saffron Peda|కుంకుమపువ్వు పేడా;Pistachio Peda|పిస్తా పేడా;Chocolate Peda|చాక్లెట్ పేడా;Rose Peda|రోజా పేడా;Mango Peda|మామిడి పేడా;Almond Peda|బాదం పేడా;Malai Peda|మలై పేడా;Cardamom Peda|యాలకుల పేడా')
    regional=rows('Madatha Kaja|మడత కాజా;Gottam Kaja|గొట్టం కాజా;Chandrakala|చంద్రకళ;Suryakala|సూర్యకళ;Kajjikaya|కజ్జికాయ;Sugar Gavvalu|పంచదార గవ్వలు;Jaggery Gavvalu|బెల్లం గవ్వలు;Jaggery Kommulu|బెల్లం కొమ్ములు;Poornam Boorelu|పూర్ణం బూరె;Puran Poli|బొబ్బట్టు;Chiroti|చిరోటి;Soan Papdi|సోన్ పాప్డీ;Bal Mithai|బాల్ మిఠాయి;Kalakand|కలాకండ్;Malpua|మాల్పువా;Ghevar|ఘేవర్;Imarti|ఇమర్తి;Rasmalai Cup|రసమలై కప్పు;Cham Cham|చమ్ చమ్;Chhena Poda|చెన్నా పోడా;Sandesh|సందేశ్;Rajbhog|రాజ్‌భోగ్;Pantua|పంతువా;Kala Jamun|కాలా జామున్;Dry Fruit Gulab Jamun|డ్రై ఫ్రూట్ గులాబ్ జామున్;Badam Katli|బాదం కట్లీ;Pista Katli|పిస్తా కట్లీ;Kesar Katli|కేసర్ కట్లీ;Milk Cake Piece|మిల్క్ కేక్ ముక్క;Coconut Roll Sweet|కొబ్బరి రోల్ మిఠాయి')
    return interleave([laddu,barfi,halwa,peda,regional])

def extend():
    reports=[save_candidates(cat,fn(),'food-d-100-v1') for cat,fn in [('meat-and-fish',meat),('eggs',eggs),('sweets',sweets)]]
    # Add species-appropriate shell-color instructions to the newly cataloged egg variants.
    colors={en:color for en,te,color in egg_data()}
    path=ROOT/'existing-items.json';items=json.loads(path.read_text(encoding='utf-8'))
    for item in items:
        if item['category']=='eggs' and item['item name'] in colors:
            item['prompt']+=f' Show only one whole unbroken raw egg, no bird, chick, nest, feather, carton, label or shell fragment. Natural unpainted {colors[item["item name"]]} eggshell. The name refers to the source breed, not the shell dye or the bird plumage.'
            item['reference_sources']=SOURCES
    path.write_text(json.dumps(items,ensure_ascii=False,indent=2),encoding='utf-8')
    (ROOT/'egg-catalog-reference-sources.json').write_text(json.dumps(SOURCES,indent=2),encoding='utf-8')
    import sys;sys.path.insert(0,str(ROOT));import build_library;build_library.refresh()
    print(json.dumps(reports,indent=2))

if __name__=='__main__':extend()
