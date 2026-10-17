# Turns the text of a product card into normalized attributes, each with a confidence.
# Rules and dictionaries first; a model is asked only for what they could not settle.
module Extraction
  SOURCES = %w[seller title description tagger confirmed reference llm prior].freeze

  # Where catalog, dictionaries and what was learned are read from; pointed elsewhere to try a learning without keeping it.
  mattr_accessor :config_root, default: Rails.root.join("config")

  def self.config_path(*parts) = config_root.join(*parts)

  # The block's results for slices of items, worked out in forked processes when there are many.
  # Each process grows to the parent's size as it reads (copy-on-write gives way), hence few of them: LEARN_WORKERS.
  def self.in_parallel(items, slice: 500, &)
    workers = items.size < 4 * slice ? 0 : ENV.fetch("LEARN_WORKERS", 3).to_i
    Parallel.map(items.each_slice(slice).to_a, in_processes: workers, &)
  end

  # Dictionaries, catalog and calibration are read once; call after changing their files.
  def self.reload!
    Dictionary.reset!
    Catalog.reset!
    Confidence.reset!
    Format.reset!
    Tagger.reset!
    Reference.reset!
    Prior.reset!
    Context.reset!
    Unreliable.reset!
    Learning.reset!
    Confirmed.reset!
  end
end
