import copy,unittest
import train as training
class TrainingTest(unittest.TestCase):
 def setUp(self):self.assertTrue(callable(getattr(training,'build',None)),'The portable context trainer is missing')
 def rows(self):
  return [dict(id=str(i),category='vacuum',title=('Мощный' if i<6 else 'Тихий')+' пылесос Q'+str(i),description='',attributes=['power'],labels={'power':'2000 Вт' if i<6 else '500 Вт'}) for i in range(12)]
 def policy(self,method='svc1'):
  return {'power':dict(method=method,desc_chars=0,threshold=0.5,confidence=0.7,replace_prior=False)}
 def test_features_use_only_text_and_match_unicode_normalization(self):
  row=self.rows()[0];row.update(title='МОЩНЫЙ\u3000Q7',description='СЕКРЕТ',labels={'power':'GOLDSECRET'})
  words=training.features(row,0)
  self.assertEqual(3,words.count('t:w:мощный'));self.assertIn('t:b:мощный/q7',words)
  self.assertNotIn('d:w:секрет',words);self.assertFalse(any('goldsecret' in s for s in words))
 def test_linear_export_is_finite_and_does_not_read_labels_as_features(self):
  rows=self.rows();original=copy.deepcopy(rows);model=training.build(rows,self.policy())
  self.assertEqual(original,rows);self.assertEqual(1,model['version']);self.assertEqual(12,model['metadata']['training_cards'])
  item=model['models']['vacuum']['power'];self.assertEqual(['2000 Вт','500 Вт'],item['classes']);self.assertEqual('margin',item['activation'])
  space=model['spaces'][item['space']];self.assertEqual(len(space['features']),len(space['idf']))
  self.assertFalse(any('2000' in s for s in space['features']))
  self.assertTrue(all(len(w)==2 for w in item['weights'].values()))
 def test_neighbors_contain_training_labels_and_normalized_vectors(self):
  model=training.build(self.rows(),self.policy('knn3'));item=model['models']['vacuum']['power'];self.assertEqual('knn',item['method'])
  rows=model['spaces'][item['space']]['neighbors']['vacuum'];self.assertEqual(12,len(rows))
  for row in rows:self.assertAlmostEqual(1.0,sum(w*w for _,w in row['vector']),places=5)
 def test_sparse_export_preserves_unpruned_probabilities(self):
  rows=self.rows()
  for i in range(4,8):rows[i]['labels']['power']='1000 Вт'
  for method in ['svc1','sgd-a0001']:
   dense=training.build(rows,self.policy(method),queries=rows)
   sparse=training.build(rows,self.policy(method),queries=rows,terms=10000)
   self.assertEqual('sparse',sparse['models']['vacuum']['power']['weight_format'])
   for a,b in zip(dense['checks'],sparse['checks']):
    self.assertEqual(set(a['expected']),set(b['expected']))
    for key in a['expected']:
     self.assertEqual(a['expected'][key]['value'],b['expected'][key]['value'])
     self.assertAlmostEqual(a['expected'][key]['score'],b['expected'][key]['score'],places=6)
 def test_sparse_export_bounds_the_coefficients_per_class(self):
  model=training.build(self.rows(),self.policy(),terms=4)['models']['vacuum']['power']
  counts={}
  for pairs in model['weights'].values():
   for label,weight in pairs:counts[label]=counts.get(label,0)+1
  self.assertTrue(all(n<=4 for n in counts.values()))
 def test_margin_ties_use_the_same_last_class_as_ruby(self):
  scores=training.np.array([[1.,0.]*10]);classes=training.np.array([str(i) for i in range(20)])
  self.assertEqual([("18",0.5)],training.score_predictions(scores,classes,"margin"))
  estimator=training.LinearSVC();estimator.decision_function=lambda matrix:scores
  self.assertEqual([("18",0.5)],training.predictions(estimator,None,classes))
 def test_policy_can_keep_exact_weights_for_selected_fields(self):
  policy=self.policy();policy["power"]["terms"]=0
  model=training.build(self.rows(),policy,queries=self.rows(),terms=4)
  self.assertNotIn("weight_format",model["models"]["vacuum"]["power"])
  self.assertEqual(training.build(self.rows(),policy,queries=self.rows())["checks"],model["checks"])
 def test_identity_and_insufficient_support_are_never_trained(self):
  policy=self.policy();policy['brand']=dict(method='svc1',desc_chars=0,threshold=0.5,confidence=0.7,replace_prior=False)
  model=training.build(self.rows()[:7],policy)
  self.assertFalse(model['models'])
if __name__=='__main__':unittest.main()
