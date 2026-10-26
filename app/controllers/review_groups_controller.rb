class ReviewGroupsController < ApplicationController
  rescue_from ReviewGroup::Conflict, with: :conflict

  def show
    seed = AttributeValue.includes(:card).find(params[:id])
    preview = ReviewGroup.preview(seed)
    render locals: { seed: seed, values: preview[:values], token: preview[:token] }
  end

  def create
    result = ReviewGroup.apply(params[:token], decision: params[:decision], replacement: params[:value])
    render :done, locals: result
  end

  def undo
    count = ReviewGroup.undo(params[:token])
    redirect_to reviews_path, notice: "Decision undone for #{count} #{count == 1 ? "value" : "values"}. #{count == 1 ? "It is" : "They are"} waiting for review again."
  end

  private

  def conflict(error)
    redirect_to reviews_path, alert: error.message
  end
end
