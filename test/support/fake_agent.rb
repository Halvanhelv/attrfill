# Stands in for the agent: answers every question with the items it was given and counts how often it was asked.
class FakeAgent
  Response = Struct.new(:content, :tokens)
  Tokens = Struct.new(:input, :output)

  attr_reader :questions

  def initialize(items = [], error: nil)
    @items = items
    @error = error
    @questions = []
  end

  # The fallback calls agent.new.ask, so the fake is its own instance.
  def new = self

  def ask(question)
    @questions << question
    raise @error if @error

    Response.new({ "attributes" => @items }, Tokens.new(120, 30))
  end
end
