require "test_helper"

class DriftTest < ActiveSupport::TestCase
  def write(rows)
    path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-predictions.csv")
    path.write("id,category,attribute,value,confidence,status,source\n" + rows.join("\n") + "\n")
    @paths = [ *@paths, path ]
    path
  end

  teardown { Array(@paths).each(&:delete) }

  def cards(count, status:, category: "tv")
    Array.new(count) { |index| "#{category}#{index},#{category},color,черный,#{status == 'accepted' ? 0.9 : 0.5},#{status},title" }
  end

  test "reports a field that stopped being filled and a category that came in" do
    before = write(cards(40, status: "accepted"))
    after = write(cards(20, status: "accepted") + cards(20, status: "missing", category: "laptop"))

    changes = Drift.new(before, after).changes.to_h { |change| [ [ change.subject, change.measure ], change.after ] }

    assert_equal 0.5, changes[[ "color", :filled ]]
    assert_equal 0.5, changes[[ "laptop", :share ]]
  end

  test "is quiet when nothing moved" do
    assert_empty Drift.new(write(cards(40, status: "accepted")), write(cards(40, status: "accepted"))).changes
  end
end
