require 'zlib'
model_path, config_path, output=ARGV
Extraction.config_root=Pathname(config_path);Extraction.reload!
data=JSON.parse(Zlib.gunzip(File.binread(model_path)))
predictor=Extraction::Context.new(data)
spaces=predictor.instance_variable_get(:@spaces);models=predictor.instance_variable_get(:@models)
checked=0;maximum_error=0.0;differences=[];typed_rejections=0
Array(data['checks']).each_with_index do |query, index|
 card=Extraction::Card.build(title: query['title'], description: query['description'], category: query['category'])
 category=Extraction::Catalog.current.categories.fetch(query['category'])
 actual=predictor.candidates(card, category, category.attributes).to_h { |c|[ c.attribute, c ] }
 (models[category.name]||{}).each do |name, spec|
  attribute=Extraction::Catalog.current.attributes.fetch(name)
  vector=predictor.send(:vectorize, card, spaces.fetch(spec['space']))
  raw, score=if vector.empty?
   nil
  elsif spec['method']=='knn'
   scores=predictor.send(:neighbor_scores, spec['space'], category.name, vector)
   predictor.send(:nearest, spec, spaces.fetch(spec['space']), category.name, name, scores)
  else
   predictor.send(:linear, spec, vector)
  end
  expected=query.fetch('expected')[name]
  if expected
   checked+=1
   error=score ? (score-expected['score']).abs : Float::INFINITY
   maximum_error=[ maximum_error, error ].max
   differences<<{ query: index, attribute: name, expected: expected, raw: raw, score: score } if raw!=expected['value'] || error>0.0002
   value=attribute.kind.normalize(expected['value'], category: category)||(expected['value'] if attribute.kind.open?)
   if value
    differences<<{ query: index, attribute: name, expected_value: value, actual_value: actual[name]&.value } unless actual[name] && attribute.kind.same?(value, actual[name].value)
    raise 'Context was auto-published' if actual[name] && Extraction::Resolver.call([ attribute ], [ actual[name] ], category: category.name).first.accepted?
   else
    typed_rejections+=1
    differences<<{ query: index, attribute: name, error: 'Invalid typed value was retained' } if actual[name]
   end
  elsif actual[name]
   differences<<{ query: index, attribute: name, error: 'Unexpected prediction', raw: raw, score: score }
  end
 end
end
report={ ok: differences.empty?, queries: Array(data['checks']).size, checked_predictions: checked, maximum_score_error: maximum_error, typed_rejections: typed_rejections, differences: differences.first(30) }
File.write(output, JSON.pretty_generate(report)) if output
puts JSON.pretty_generate(report)
raise 'Python/Ruby prediction mismatch' unless differences.empty? && checked.positive?
