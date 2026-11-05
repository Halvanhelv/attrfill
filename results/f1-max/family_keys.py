"""Conservative product keys without capacity, SIM or generic-title bridges."""
import re,unicodedata
COLORS=r'\b(?:черн\w*|бел\w*|сер\w*|синий|синяя|голуб\w*|красн\w*|зел[её]н\w*|розов\w*|фиолет\w*|ж[её]лт\w*|золот\w*|серебр\w*|графит\w*|бежев\w*|black|white|gr[ae]y|blue|red|green|pink|purple|gold|silver|midnight|starlight)\b'
GENERIC=set('galaxy iphone ipad watch series macbook air pro max plus ultra note redmi poco apple samsung ноутбук смартфон планшет телевизор монитор'.split())
def clean(text):return ' '.join(unicodedata.normalize('NFKC',str(text)).casefold().replace('ё','е').split())
def product(text,category,brand):
 text=re.sub(r'\(.*?\)',' ',clean(text))
 text=re.sub(r'\d+\s*/\s*\d+(?:\s*[gгtт][bб])?|\d+\s*[gгtт][bб]',' ',text)
 text=re.sub(r'\b(?:\d+\s*)?e?sim(?:\s*\+\s*e?sim)?\b',' ',text)
 text=re.sub(r'\b\d+(?:[.,]\d+)?\s*(?:mm|мм|cm|см|hz|гц)\b',' ',text)
 text=re.sub(COLORS,' ',text)
 text=re.sub(r'\b(iphone|ipad)(?=\d)',r'\1 ',text)
 text=re.sub(r'\bgalaxy(?=[a-z]\d)', 'galaxy ',text)
 if category=='smartwatch' and brand=='apple':
  text=re.sub(r'\bwatch\s+series\b','watch',text)
  text=re.sub(r'^series\s+(?=\d)','watch ',text)
 return re.findall(r'[a-zа-я0-9+-]+',text)
def code(word):
 return bool(re.search('[a-zа-я]',word) and re.search('[0-9]',word) and not re.fullmatch(r'\d+(?:mm|мм|cm|см|[gгtт][bб]|hz|гц|sim|esim|[dk])\w*',word))
def identified(words):
 return any(code(w) for w in words) or any(w in ('iphone','ipad','watch') and i+1<len(words) and words[i+1].isdigit() and 1<=int(words[i+1])<=50 for i,w in enumerate(words))
def keys(row):
 category=row['category'];brand=clean(row['brand']);model=product(row['model'],category,brand)
 result=[('input',category,clean(row['title']),clean(row['description']))]
 head=model[:2]
 if identified(head) or (model and not any(re.search(r'\d',w) for w in model) and any(w not in GENERIC and w!=brand for w in head)):
  result.append(('family',category,brand,' '.join(head)))
 codes=[w for w in model if code(w)]
 if codes:result.append(('code',category,brand,codes[0]))
 title=product(row['title'],category,brand)[:5]
 if identified(title):result.append(('title',category,' '.join(title)))
 return result
