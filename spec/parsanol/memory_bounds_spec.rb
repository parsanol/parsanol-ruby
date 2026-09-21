# frozen_string_literal: true

require "spec_helper"

# parsanol-ruby#84: memory must stay bounded across distinct documents.
# Loose thresholds — this is a leak regression guard, not a perf test.
describe "native memory bounds" do
  it "keeps RSS growth bounded across distinct documents" do
    skip "native extension unavailable" unless Parsanol::Native.available?

    rss_mb = -> { `ps -o rss= -p #{Process.pid}`.to_i / 1024.0 }
    GC.start
    before = rss_mb.call

    parser = Class.new(Parsanol::Parser) do
      rule(:line) do
        (match(/[^\n]/).repeat(1) | str("")).as(:body)
      end
      rule(:nl) { dynamic { |_s, _c| str("\n") } }
      rule(:doc) { (line >> nl).repeat(1) }
      root(:doc)

      def self.name
        "MemoryBoundsParser"
      end
    end.new

    8.times do |i|
      doc = ("= Doc #{i}\n\n== Section\n\nparagraph line #{i} text\n" * 150)
      expect { parser.parse(doc, mode: :native) }.not_to raise_error
    end

    GC.start
    after = rss_mb.call
    growth = after - before
    # A cached-program parse of ~10KB docs is well under 30MB; the
    # pre-fix behavior retained megabytes per distinct document.
    expect(growth).to be < 60
  end
end
