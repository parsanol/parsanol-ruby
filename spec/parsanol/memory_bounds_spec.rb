# frozen_string_literal: true

require "spec_helper"

# parsanol-ruby#84 + #93: memory must stay bounded across distinct
# documents AND across repeated parses of the same document (dynamic
# fragments mint capture-derived grammars every parse, which used to
# accumulate unbounded compiled programs — 2+ GB observed).
# Loose thresholds — this is a leak regression guard, not a perf test.
describe "native memory bounds" do
  def rss_mb
    `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
  end

  def blocky_parser
    Class.new(Parsanol::Parser) do
      rule(:line) do
        (match(/[^\n]/).repeat(1) | str("")).as(:body)
      end
      rule(:nl) { dynamic { |_s, _c| str("\n") } }
      rule(:block) do
        dynamic { |_s, _c| str("== ") >> match(/[^\n]/).repeat(1).as(:title) >> str("\n") }
      end
      rule(:doc) { (block | (line >> nl)).repeat(1) }
      root(:doc)

      def self.name
        "MemoryBoundsParser"
      end
    end.new
  end

  it "keeps RSS growth bounded across distinct documents" do
    skip "native extension unavailable" unless Parsanol::Native.available?

    parser = blocky_parser
    GC.start
    before = rss_mb

    60.times do |i|
      doc = ("= Doc #{i}\n\n== Section #{i}\n\nparagraph line #{i} text\n" * 150)
      expect { parser.parse(doc, mode: :native) }.not_to raise_error
    end

    GC.start
    growth = rss_mb - before
    # Pre-fix behavior retained megabytes per distinct document
    # (~4-5 MB x 60 = 300 MB+).
    expect(growth).to be < 150
  end

  it "keeps RSS growth bounded across repeated parses of one document" do
    skip "native extension unavailable" unless Parsanol::Native.available?

    parser = blocky_parser
    doc = ("= Doc\n\n== Section\n\nparagraph line text\n" * 150)
    expect { parser.parse(doc, mode: :native) }.not_to raise_error

    GC.start
    before = rss_mb

    60.times do
      expect { parser.parse(doc, mode: :native) }.not_to raise_error
    end

    GC.start
    growth = rss_mb - before
    # Pre-fix, every parse of the same doc minted fresh fragment
    # grammars + compiled programs and never freed them (2+ GB).
    expect(growth).to be < 150
  end
end
