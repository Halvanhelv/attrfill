class BatchesController < ApplicationController
  SHOWN = 50

  def index
    render locals: { batches: Batch.order(id: :desc) }
  end

  def create
    file = params[:file]
    return redirect_to batches_path, alert: "Choose a CSV, TSV, JSON or JSONL file." if file.blank?
    if file.size > Batch::MAX_BYTES
      return redirect_to batches_path, alert: "The file is larger than #{Batch::MAX_BYTES / 1.megabyte} MB. Split it into parts."
    end

    redirect_to Batch.upload!(file)
  end

  def show
    batch = Batch.find(params[:id])
    render locals: { batch: batch, cards: batch.cards.includes(:attribute_values).order(:id).limit(SHOWN),
                     statuses: batch.attribute_values.group(:status).count }
  end

  def download
    batch = Batch.find(params[:id])
    format = params[:format] == "json" ? "json" : "csv"
    path = Rails.root.join("tmp", "batch-#{batch.id}-#{SecureRandom.hex(4)}.#{format}")

    batch.write_results(path, spreadsheet_safe: format == "csv")
    send_data path.read, filename: "predictions-#{batch.id}.#{format}", type: Mime[format]
  ensure
    path&.delete if path&.exist?
  end
end
