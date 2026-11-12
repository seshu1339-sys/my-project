"""Curated single-item produce catalog expansion; writes only the G-drive library."""
import json,sys
from pathlib import Path
sys.dont_write_bytecode=True
ROOT=Path('G:/Locamarket HD Images/library')
sys.path.insert(0,str(ROOT))
import build_library as lib

VEGETABLES='''Spinach Leaf|పాలకూర ఆకు
Amaranth Leaf|తోటకూర ఆకు
Red Amaranth Leaf|ఎర్ర తోటకూర ఆకు
Coriander Leaf|కొత్తిమీర ఆకు
Curry Leaf|కరివేపాకు
Mint Leaf|పుదీనా ఆకు
Fenugreek Leaf|మెంతికూర ఆకు
Sorrel Leaf|గోంగూర ఆకు
Purslane Leaf|గంగవాయలి ఆకు
Dill Leaf|సోయికూర ఆకు
Malabar Spinach Leaf|బచ్చలి ఆకు
Drumstick Leaf|మునగ ఆకు
Mustard Greens Leaf|ఆవ ఆకు
Kale Leaf|కేల్ ఆకు
Romaine Lettuce Leaf|రోమైన్ లెట్యూస్ ఆకు
Iceberg Lettuce Head|ఐస్‌బర్గ్ లెట్యూస్
Butterhead Lettuce Head|బటర్‌హెడ్ లెట్యూస్
Red Lettuce Leaf|ఎర్ర లెట్యూస్ ఆకు
Celery Stalk|సెలరీ కాడ
Spring Onion|ఉల్లికాడ
Leek|లీక్
Chive Stalk|చైవ్ కాడ
Basil Leaf|బేసిల్ ఆకు
Broccoli|బ్రోకలీ
Brussels Sprout|బ్రస్సెల్స్ స్ప్రౌట్
Artichoke|ఆర్టిచోక్
Asparagus Spear|ఆస్పరాగస్ కాడ
Green Zucchini|పచ్చ జుక్కిని
Yellow Zucchini|పసుపు జుక్కిని
Red Capsicum|ఎర్ర క్యాప్సికం
Yellow Capsicum|పసుపు క్యాప్సికం
Orange Capsicum|నారింజ రంగు క్యాప్సికం
White Onion|తెల్ల ఉల్లిపాయ
Yellow Onion|పసుపు ఉల్లిపాయ
Shallot|చిన్న ఉల్లిపాయ
Red Potato|ఎర్ర బంగాళాదుంప
Purple Potato|ఊదా బంగాళాదుంప
Fingerling Potato|ఫింగర్‌లింగ్ బంగాళాదుంప
Purple Carrot|ఊదా క్యారెట్
Yellow Carrot|పసుపు క్యారెట్
White Carrot|తెల్ల క్యారెట్
Golden Beetroot|బంగారు బీట్‌రూట్
Purple Cauliflower|ఊదా కాలీఫ్లవర్
Romanesco|రోమనెస్కో
Red Cabbage|ఎర్ర క్యాబేజీ
Savoy Cabbage|సవాయ్ క్యాబేజీ
Napa Cabbage|నాపా క్యాబేజీ
Bok Choy|బోక్ చోయ్
Button Mushroom|బటన్ పుట్టగొడుగు
Oyster Mushroom|ఆయిస్టర్ పుట్టగొడుగు
Shiitake Mushroom|షీటాకే పుట్టగొడుగు
Portobello Mushroom|పోర్టోబెల్లో పుట్టగొడుగు
Turnip|టర్నిప్
Rutabaga|రుటబాగా
Cassava|కర్రపెండలం
Red Radish|ఎర్ర ముల్లంగి
Black Radish|నల్ల ముల్లంగి
Watermelon Radish|వాటర్‌మెలన్ ముల్లంగి
Baby Corn|బేబీ కార్న్
Snow Pea Pod|స్నో బఠాణీ కాయ
Sugar Snap Pea Pod|షుగర్ స్నాప్ బఠాణీ కాయ
French Bean Pod|ఫ్రెంచ్ చిక్కుడు కాయ
Cluster Bean Pod|గోరు చిక్కుడు కాయ
Broad Bean Pod|చిక్కుడు కాయ
Yardlong Bean Pod|అలసంద కాయ
Green Chilli|పచ్చి మిరపకాయ
Red Chilli|ఎర్ర మిరపకాయ'''

FRUITS='''Gala Apple|గాలా ఆపిల్
Fuji Apple|ఫుజి ఆపిల్
Granny Smith Apple|గ్రానీ స్మిత్ ఆపిల్
Golden Delicious Apple|గోల్డెన్ డెలిషియస్ ఆపిల్
Red Delicious Apple|రెడ్ డెలిషియస్ ఆపిల్
Pink Lady Apple|పింక్ లేడీ ఆపిల్
Honeycrisp Apple|హనీక్రిస్ప్ ఆపిల్
Ambrosia Apple|అంబ్రోసియా ఆపిల్
Red Banana|ఎర్ర అరటిపండు
Yelakki Banana|ఏలక్కి అరటిపండు
Nendran Banana|నేంద్రం అరటిపండు
Rasthali Banana|రసతాళి అరటిపండు
Poovan Banana|పూవన్ అరటిపండు
Robusta Banana|రోబస్టా అరటిపండు
Cavendish Banana|కావెండిష్ అరటిపండు
Karpuravalli Banana|కర్పూరవల్లి అరటిపండు
Banganapalli Mango|బంగినపల్లి మామిడి పండు
Alphonso Mango|అల్ఫాన్సో మామిడి పండు
Dasheri Mango|దసేరి మామిడి పండు
Langra Mango|లాంగ్రా మామిడి పండు
Totapuri Mango|తోతాపురి మామిడి పండు
Kesar Mango|కేసర్ మామిడి పండు
Neelam Mango|నీలం మామిడి పండు
Rasalu Mango|రసాలు మామిడి పండు
Mallika Mango|మల్లిక మామిడి పండు
Himsagar Mango|హిమసాగర్ మామిడి పండు
Green Grape|పచ్చ ద్రాక్ష పండు
Black Grape|నల్ల ద్రాక్ష పండు
Red Grape|ఎర్ర ద్రాక్ష పండు
Muscat Grape|మస్కట్ ద్రాక్ష పండు
Concord Grape|కాంకార్డ్ ద్రాక్ష పండు
Cotton Candy Grape|కాటన్ క్యాండీ ద్రాక్ష పండు
Blueberry|బ్లూబెర్రీ
Raspberry|రాస్ప్‌బెర్రీ
Blackberry|బ్లాక్‌బెర్రీ
Cranberry|క్రాన్‌బెర్రీ
Blackcurrant|బ్లాక్‌కరెంట్
Redcurrant|రెడ్‌కరెంట్
Whitecurrant|వైట్‌కరెంట్
European Gooseberry|యూరోపియన్ గూస్‌బెర్రీ
Peach|పీచ్ పండు
Nectarine|నెక్టరిన్ పండు
Apricot|ఆప్రికాట్ పండు
Cherry|చెర్రీ పండు
Persimmon|పర్సిమన్ పండు
Quince|క్విన్స్ పండు
Pomelo|పంపర పనస
Mandarin|మాండరిన్ పండు
Tangerine|టాంజరిన్ పండు
Clementine|క్లెమెంటైన్ పండు
Blood Orange|బ్లడ్ ఆరెంజ్
Navel Orange|నావెల్ నారింజ
Valencia Orange|వాలెన్సియా నారింజ
Kumquat|కుమ్‌క్వాట్ పండు
Yuzu|యుజు పండు
Bergamot|బెర్గమాట్ పండు
Medjool Date|మెడ్జూల్ ఖర్జూరం
Ajwa Date|అజ్వా ఖర్జూరం
Deglet Noor Date|డెగ్లెట్ నూర్ ఖర్జూరం
Barhi Date|బర్హి ఖర్జూరం
Litchi|లిచీ పండు
Rambutan|రాంబుటాన్ పండు
Longan|లాంగన్ పండు
Mangosteen|మాంగోస్టీన్ పండు
Passion Fruit|ప్యాషన్ ఫ్రూట్
Avocado|అవకాడో
Star Fruit|కమరాక్షి పండు
Wood Apple|వెలగపండు
Bael Fruit|మారేడు పండు
Karonda|వాక్కాయ
Feijoa|ఫెజోవా పండు
Breadfruit|బ్రెడ్‌ఫ్రూట్
Durian|డ్యూరియన్ పండు'''

def extend():
    path=ROOT/'existing-items.json'
    extra=json.loads(path.read_text(encoding='utf-8'))
    known={(r['category'],r['file name']) for r in lib.catalog()}
    added=[]
    for category,data,expected in [('vegetables',VEGETABLES,67),('fruits',FRUITS,73)]:
        values=data.strip().splitlines()
        assert len(values)==expected,(category,len(values))
        for value in values:
            en,te=value.split('|');filename=lib.slug(en)+'.png'
            if (category,filename) in known:continue
            prompt=lib.SPEC.format(subject=en)
            prompt+=' Show exactly ONE whole specimen, never a bunch, cluster, pile, collection or assortment. No cultivar labels, stickers or writing. For a leaf, show just one leaf; for a pod, one closed pod; for a grape or berry, just one single fruit. No cut-open fruit or garnish.'
            row={'item name':en,'Telugu name':te,'category':category,'file name':filename,'prompt':prompt}
            extra.append(row);added.append(row);known.add((category,filename))
    path.write_text(json.dumps(extra,ensure_ascii=False,indent=2),encoding='utf-8')
    lib.refresh()
    print(json.dumps({'catalog_items_added':len(added),'vegetables_added':sum(r['category']=='vegetables' for r in added),'fruits_added':sum(r['category']=='fruits' for r in added)}))

if __name__=='__main__':extend()
