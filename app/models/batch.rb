# One uploaded file of cards and the run over it.
class Batch < ApplicationRecord
  UPLOADS = Rails.root.join("storage/uploads")
  CHUNK = 200
  # A larger file would hold the disk and the job for hours on the 2 CPU / 4 GB target; split it instead.
  MAX_BYTES = ENV.fetch("MAX_UPLOAD_MB", 100).to_i.megabytes

  has_many :cards, dependent: :delete_all
  has_many :attribute_values, through: :cards

  enum :status, %w[pending processing done failed].index_by(&:itself)

  def self.upload!(file)
    UPLOADS.mkpath
    path = UPLOADS.join("#{SecureRandom.hex(6)}-#{File.basename(file.original_filename).gsub(/[^\w.\-]/, '_')}")
    FileUtils.cp(file.path, path)

    create!(name: file.original_filename, source_path: path.to_s).tap(&:process_later)
  end

  def process_later = ProcessJob.perform_later(self)

  def process!
    update!(status: "processing", error: nil)
    cards.destroy_all

    Extraction::Runner.new.each(Dataset.new(source_path)).each_slice(CHUNK) do |slice|
      transaction { slice.each { |row, result| Card.record!(result, batch: self, category: row.card.category) } }
      update!(cards_count: cards.count)
    end

    update!(status: "done")
  rescue StandardError => error
    # Nothing to retry: the file is what it is. The page shows the reason.
    Rails.logger.error("[Batch #{id}] #{error.class}: #{error.message}")
    update!(status: "failed", error: "#{error.class}: #{error.message}".truncate(500))
  end

  # The predictions file, rebuilt from what is stored so that a reviewer's corrections are in it.
  def write_results(path, spreadsheet_safe: false)
    Dataset::Writer.open(path, spreadsheet_safe: spreadsheet_safe) do |writer|
      cards.includes(:attribute_values).find_each { |card| writer << card.to_result }
    end
  end
end
