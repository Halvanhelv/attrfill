require "csv"

# Whether the cards changed since a run that was checked: two predictions files compared by what needs no
# labels (how much of each field is filled, how much goes to review, how sure the values are, which categories come).
class Drift
  THRESHOLD = 0.1
  MIN_VALUES = 30

  Change = Data.define(:subject, :measure, :before, :after) do
    def shift = (after - before).round(3)
  end

  def self.profile(path)
    fields = Hash.new { |hash, name| hash[name] = { values: 0, filled: 0, review: 0, confidence: 0.0 } }
    categories = Hash.new { |hash, name| hash[name] = Set.new }
    CSV.foreach(path, headers: true) do |row|
      field = fields[row["attribute"]]
      field[:values] += 1
      field[:filled] += 1 unless row["status"] == "missing"
      field[:review] += 1 if row["status"] == "review"
      field[:confidence] += row["confidence"].to_f
      categories[row["category"]] << row["id"]
    end

    cards = categories.values.sum(&:size).nonzero? || 1
    { fields: fields.to_h { |name, field| [ name, measures(field) ] },
      categories: categories.to_h { |name, ids| [ name, (ids.size.to_f / cards).round(3) ] } }
  end

  def self.measures(field)
    { values: field[:values], filled: (field[:filled].to_f / field[:values]).round(3),
      review: (field[:review].to_f / field[:values]).round(3), confidence: (field[:confidence] / field[:values]).round(3) }
  end

  def initialize(before, after, threshold: THRESHOLD)
    @before = self.class.profile(before)
    @after = self.class.profile(after)
    @threshold = threshold
  end

  # Fields and categories that moved by the threshold or more, largest shift first.
  def changes
    fields = @after[:fields].flat_map do |name, now|
      was = @before[:fields][name]
      next [] if was.nil? || [ was, now ].any? { |measured| measured[:values] < MIN_VALUES }

      %i[filled review confidence].map { |measure| Change.new(name, measure, was[measure], now[measure]) }
    end
    categories = (@before[:categories].keys | @after[:categories].keys).map do |name|
      Change.new(name, :share, @before[:categories].fetch(name, 0.0), @after[:categories].fetch(name, 0.0))
    end

    (fields + categories).select { |change| change.shift.abs >= @threshold }.sort_by { |change| -change.shift.abs }
  end

  def new_fields = @after[:fields].keys - @before[:fields].keys
end
