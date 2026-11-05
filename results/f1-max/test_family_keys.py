import unittest
import family_keys as grouping
class FamilyKeysTest(unittest.TestCase):
 def setUp(self):self.assertTrue(callable(getattr(grouping,'keys',None)),'Product identity key generator is missing')
 def row(self,title,model,category='smartphone',brand='Apple',description=''):
  return dict(title=title,model=model,category=category,brand=brand,description=description)
 def shared(self,a,b):return set(grouping.keys(a))&set(grouping.keys(b))
 def test_capacity_and_sim_are_not_identity(self):
  a=self.row('Смартфон Apple iPhone 16 Pro 256GB 2SIM','iPhone 16 Pro 256 2SIM')
  b=self.row('Смартфон Apple iPhone 17 Pro 256GB 2SIM','iPhone 17 Pro 256 2SIM')
  self.assertFalse(self.shared(a,b))
 def test_same_generation_variants_share_identity(self):
  a=self.row('Смартфон Apple iPhone17 Pro 128GB черный','iPhone17 Pro 128GB')
  b=self.row('Смартфон Apple iPhone 17 Pro Max 256GB белый','iPhone 17 Pro Max 256GB')
  self.assertTrue(self.shared(a,b))
 def test_watch_size_does_not_join_generations(self):
  a=self.row('Смарт-часы Apple Watch Series 10 46mm','Watch Series 10 46mm','smartwatch')
  b=self.row('Смарт-часы Apple Watch Series 11 46mm','Watch Series 11 46mm','smartwatch')
  c=self.row('Смарт-часы Apple Watch 11 42mm','Watch 11 42mm','smartwatch')
  self.assertFalse(self.shared(a,b));self.assertTrue(self.shared(b,c))
 def test_generic_title_prefix_does_not_join_samsung(self):
  a=self.row('Смартфон Samsung трансгран Samsung Galaxy S24 256GB','Galaxy S24 256','smartphone','Samsung')
  b=self.row('Смартфон Samsung трансгран Samsung Galaxy S25 256GB','Galaxy S25 256','smartphone','Samsung')
  self.assertFalse(self.shared(a,b))
 def test_duplicate_input_is_always_joined(self):
  a=self.row('Смартфон Samsung S24','S24','smartphone','Samsung')
  b=self.row('Смартфон  Samsung S24','SM-S921','smartphone','SAMSUNG')
  self.assertTrue(self.shared(a,b))
if __name__=='__main__':unittest.main()
