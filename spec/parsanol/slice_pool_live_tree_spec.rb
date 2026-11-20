# frozen_string_literal: true

require "spec_helper"

describe "the slice pool vs the live AST (ruby#535)" do
  include Parsanol

  # The regression: Source#match handed out POOLED slices (reset on
  # reuse once the pool wrapped at size 5000), and match results live
  # in the AST the builder walks AFTER the parse — a reset clobbered a
  # stored span, truncating construct source spans on inputs past the
  # pool size (the concatenated-oracle fixture: a 286-byte entity span
  # ending mid-WHERE instead of at END_ENTITY;).
  #
  # The pin: parse enough word matches to wrap the pool several times
  # and require the FIRST stored slice to survive byte-exactly.
  def word_list_parser
    Class.new(Parsanol::Parser) do
      # Named captures: bare char-runs compact to a single span by
      # design; the named forms stay as one hash per match, each
      # holding a live slice — exactly what the pool used to clobber.
      rule(:char) { match("[a-zA-Z0-9_ ]").as(:char) }
      rule(:chars) { char.repeat }
      root(:chars)
    end
  end

  it "keeps the first stored slice intact after the pool wraps" do
    input = "w #{'x' * 40_000} tail"
    tree = word_list_parser.new.parse(input)

    expect(tree.size).to be > 5_000,
                         "the pin needs more slices than the pool holds: #{tree.respond_to?(:size) ? tree.size : tree.class}"
    first = tree.first
    expect(first[:char]).to be_a(Parsanol::Slice)
    expect(first[:char].content).to eq("w")
    expect(first[:char].offset).to eq(0)
    # And a late one — past every pool wrap.
    expect(tree.last[:char].offset).to eq(input.bytesize - 1)
  end
end
