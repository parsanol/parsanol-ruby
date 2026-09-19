# frozen_string_literal: true

require "spec_helper"

# GH-67: flattening a repetition must never mutate its input. Slices
# exposed through cached subtrees get flattened repeatedly (Capture
# re-applies on backtracking); joining aliased the first piece's buffer
# and appended into it, duplicating content ("%headerheaderheader").
RSpec.describe "flatten purity" do
  include Parsanol::Atoms::CanFlatten

  it "does not mutate input slices when joining a repetition" do
    first = Parsanol::Slice.new(1, "%header", nil)
    chars = %w[% h e a d e r].each_with_index.map do |c, i|
      Parsanol::Slice.new(2 + i, c, nil)
    end
    list = [first] + chars

    3.times { flatten([:repetition] + list) }

    expect(first.content).to eq("%header")
    chars.each_with_index { |slice, i| expect(slice.content).to eq("%header"[i]) }
  end

  it "joins to the same value on repeated flattens" do
    first = Parsanol::Slice.new(1, "ab", nil)
    second = Parsanol::Slice.new(3, "cd", nil)
    list = [first, second]

    expect(flatten([:repetition] + list).str).to eq("abcd")
    expect(flatten([:repetition] + list).str).to eq("abcd")
  end
end
