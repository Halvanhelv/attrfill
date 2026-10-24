class Batch::ProcessJob < ApplicationJob
  def perform(batch) = batch.process!
end
