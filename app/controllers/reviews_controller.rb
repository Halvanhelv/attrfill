# The manual check: values the pipeline was not sure of or did not find, least sure first.
class ReviewsController < ApplicationController
  PER_PAGE = 30
  CONFLICT = "Another reviewer or a group decision has already changed this value. Their decision was saved, yours was not. " \
             "Reload the page and check the value again."

  def index
    render locals: { values: AttributeValue.waiting.includes(:card).limit(PER_PAGE), waiting: AttributeValue.waiting.count }
  end

  # A decision is about the value the person saw. The form carries its version (seen); if someone else changed
  # the value since (another reviewer, a group decision or its undo), nothing is written. The check and the write
  # are one transaction (SQLite takes the write lock at BEGIN IMMEDIATE), so two decisions cannot interleave.
  def update
    value = nil
    changed = AttributeValue.transaction do
      value = AttributeValue.find(params[:id])
      next true if changed_since_shown?(value)

      case params[:decision]
      when "approve" then value.approve!
      when "reject" then value.reject!
      else value.correct!(params[:value])
      end
      false
    end
    return conflict if changed

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [ turbo_stream.remove(value), turbo_stream.update("waiting", AttributeValue.waiting.count.to_s) ]
      end
      format.html { redirect_to reviews_path }
    end
  end

  private

  # Forms made before this check (and API-like callers) send no version: they keep the old behaviour.
  def changed_since_shown?(value)
    params[:seen].present? && params[:seen] != value.version
  end

  def conflict
    respond_to do |format|
      format.turbo_stream { render plain: CONFLICT, status: :conflict }
      format.html { redirect_back fallback_location: reviews_path, alert: CONFLICT }
    end
  end
end
