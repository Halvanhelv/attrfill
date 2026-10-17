module Extraction
  # Runs the pipeline over many cards, a few at a time: the rules are quick, a model answers slowly,
  # so waiting on several answers at once is what makes a run fit its window.
  class Runner
    def initialize(pipeline: Pipeline.new, threads: ENV.fetch("EXTRACT_THREADS", 6).to_i, fail_fast: false)
      @pipeline = pipeline
      @threads = threads.clamp(1, 12)
      @fail_fast = fail_fast
    end

    # Yields each item with its result, in the order given. Items answer to #card.
    def each(items)
      return to_enum(:each, items) unless block_given?

      items.each_slice(@threads * 8) do |slice|
        # Marketplace exports commonly repeat the same product. Extract its
        # text once per portion, then attach the result to every source row.
        grouped = slice.group_by { |item| card_key(item.card) }
        groups = grouped.values
        queue = Queue.new
        groups.each_with_index { |group, index| queue << [ group.first, index ] }
        results = Array.new(groups.size)

        Array.new([ @threads, groups.size ].min) do
          Thread.new do
            loop do
              item, index = queue.pop(true)
              results[index] = read(item.card)
            rescue ThreadError
              break
            end
          end
        end.each(&:join)

        by_key = grouped.keys.zip(results).to_h
        slice.each { |item| yield item, result_for(by_key.fetch(card_key(item.card)), item.card) }
      end
    end

    private

    def card_key(card) = [ card.title, card.description, card.seller_attributes, card.category ]

    def result_for(result, card)
      return result if result.card.equal?(card)

      Pipeline::Result.new(card: card, category: result.category, findings: result.findings, asked_model: result.asked_model)
    end

    # One card that cannot be read must not stop the run: it is written out empty and logged.
    def read(card)
      @pipeline.call(card)
    rescue StandardError => error
      raise if @fail_fast

      Rails.logger.error("[Runner] card #{card.id}: #{error.class}: #{error.message}")
      @pipeline.unread(card)
    end
  end
end
