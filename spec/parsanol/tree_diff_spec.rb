# frozen_string_literal: true

require "spec_helper"
require "parsanol/slice"

RSpec.describe Parsanol::TreeDiff do
  describe ".why" do
    it "returns nil for equal trees" do
      tree = { lines: [{ text: "a", line_break: "\n" }] }
      expect(described_class.why(tree, tree.dup)).to be_nil
    end

    it "reports kind mismatch with the divergent path (#83 shape)" do
      ruby = { paragraph: { lines: [{ text: "a", line_break: "\n" }] } }
      native = { paragraph: { lines: { text: "a", line_break: "\n" } } }

      diff = described_class.why(ruby, native)
      expect(diff[:path]).to eq("paragraph.lines")
      expect(diff[:why]).to include("kind mismatch")
      expect(diff[:ruby]).to eq("Array(1)")
      expect(diff[:native]).to include("Hash{text, line_break}")
    end

    it "reports size mismatches in arrays" do
      diff = described_class.why({ xs: [1, 2] }, { xs: [1] })
      expect(diff[:path]).to eq("xs")
      expect(diff[:why]).to include("size mismatch: ruby 2 vs native 1")
    end

    it "reports missing keys" do
      diff = described_class.why({ a: 1, b: 2 }, { a: 1 })
      expect(diff[:why]).to include("ruby-only [:b]")
      expect(diff[:why]).to include("native-only []")
    end

    it "compares slice content and flags offset drift" do
      same = described_class.why(
        { t: Parsanol::Slice.new(5, "hi") },
        { t: Parsanol::Slice.new(5, "hi") },
      )
      expect(same).to be_nil

      content = described_class.why(
        { t: Parsanol::Slice.new(5, "hi") },
        { t: Parsanol::Slice.new(6, "bye") },
      )
      expect(content[:why]).to include("content mismatch")
    end

    it "flags offset drift with position info in the why line" do
      drift = described_class.why(
        { t: Parsanol::Slice.new(5, "hi") },
        { t: Parsanol::Slice.new(6, "hi") },
      )
      expect(drift[:path]).to eq("t")
      expect(drift[:why]).to include("offset drift: 5 vs 6")
      expect(drift[:ruby]).to include('Slice("hi"@5)')
    end

    it "indexes into arrays along the path" do
      diff = described_class.why(
        { lines: [{ text: "a" }, { text: "b" }] },
        { lines: [{ text: "a" }, { text: "c" }] },
      )
      expect(diff[:path]).to eq("lines[1].text")
      expect(diff[:ruby]).to include("String")
    end
  end
end
