"""Audit the bundled historical split; this does not run or tune predictions."""
import csv,gzip,hashlib,json
from pathlib import Path
from family_keys import keys
root=Path(__file__).resolve().parent
mapping=json.loads((root/'category-map.json').read_text())
def rows(name):
 path=root/name
 with (gzip.open(path,'rt',newline='') if path.suffix=='.gz' else path.open(newline='')) as stream:return list(csv.DictReader(stream))
def identities(data):
 return {key for row in data for key in keys({**row,'category':mapping.get(row['category'],row['category'])})}
train,test,development,validation=[rows(n) for n in ['train.csv.gz','test.csv','development-train.csv.gz','validation.csv.gz']]
manifest=json.loads((root/'split-manifest.json').read_text())
expected=manifest['test_sha256_unchanged'];actual=hashlib.sha256((root/'test.csv').read_bytes()).hexdigest()
assert actual==expected,'Test content changed'
assert len({r['id'] for r in train})==len(train),'Duplicate train IDs'
assert len({r['id'] for r in test})==len(test),'Duplicate test IDs'
assert not identities(train)&identities(test),'Family/text overlap'
assert not identities(development)&identities(validation),'Development family/text overlap'
assert {r['id'] for r in train}=={r['id'] for r in development+validation},'Final fit differs from development union'
assert not {r['id'] for r in train+test}&set(manifest['quarantined_ids']),'Quarantined aliases in fit/test'
assert len(train)+len(test)+manifest['quarantined_aliases_of_test']==manifest['source_cards']
print(json.dumps(dict(ok=True,training_cards=len(train),test_cards=len(test),development_train=len(development),validation=len(validation),quarantined=manifest['quarantined_aliases_of_test'],cross_split_key_overlap=0,test_sha256=actual),indent=2))
