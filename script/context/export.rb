# bin/rails runner script/context/export.rb TRAIN_INPUT NEW_OUTPUT.jsonl [BASE_MODEL_DIR]
# Labels are exported separately from input-only text. The context trainer never
# uses those labels as features. Only the handwritten case categories are fitted.
require "digest"

input, output, model_root = ARGV
abort "Usage: export.rb TRAIN_INPUT NEW_OUTPUT.jsonl [BASE_MODEL_DIR]" unless input && output
output = Pathname(output).expand_path
abort "Output must be new" if output.exist?
Extraction.config_root = Pathname(model_root).expand_path if model_root
Extraction.reload!
Regexp.timeout = 10
catalog = Extraction::Catalog.current
manual = YAML.load_file(Extraction.config_path("catalog.yml")).fetch("categories").keys - [ "generic" ]
counts = Hash.new(0)
labels = Hash.new(0)
output.dirname.mkpath
File.open(output, "w") do |file|
  Dataset.new(input).each do |row|
    category = catalog.detect(row.card)
    next unless manual.include?(category.name)

    names = category.attributes.map(&:name)
    gold = row.labels.slice(*names).to_h do |name, raw|
      kind = catalog.attributes.fetch(name).kind
      [ name, kind.normalize(raw, category: category) || raw ]
    end
    counts[category.name] += 1
    gold.each_key { |name| labels[name] += 1 }
    file.puts(JSON.generate(id: row.card.id, category: category.name, title: row.card.heading,
                           description: row.card.description.to_s, attributes: names, labels: gold))
  end
end
manifest = { input_sha256: Digest::SHA256.file(input).hexdigest, cards: counts.values.sum,
             by_category: counts, labelled_values: labels, output_sha256: Digest::SHA256.file(output).hexdigest,
             scope: "Input-only title/description/category; training labels in a separate map; handwritten categories only." }
output.sub_ext(".manifest.json").write(JSON.pretty_generate(manifest))
puts JSON.pretty_generate(manifest.except(:labelled_values))
