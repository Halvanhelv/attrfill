# Nightly: what reviewers decided becomes what the pipeline trusts (Extraction::ReviewLearning).
class LearnFromReviewsJob < ApplicationJob
  queue_as :default

  def perform
    summary = Extraction::ReviewLearning.call
    Rails.logger.info("Learned from reviews: #{summary.to_h}")
  end
end
