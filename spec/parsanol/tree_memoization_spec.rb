# frozen_string_literal: true

require "spec_helper"

describe "Tree Memoization" do
  let(:context) { Parsanol::Atoms::Context.new(nil, interval_cache: true) }
  let(:counting_atom_class) do
    Class.new(Parsanol::Atoms::Base) do
      attr_reader :calls

      def initialize(char)
        super()
        @char = char
        @calls = 0
      end

      def try(source, context, _consume_all)
        @calls += 1
        pos = source.bytepos
        slice = source.consume(1)
        return ok(slice) if slice.content == @char

        source.bytepos = pos
        context.err(self, source, "miss")
      end

      def cached?
        false
      end

      def to_s_inner(_prec)
        "counting"
      end
    end
  end

  describe "Repetition with tree memoization" do
    it "caches repeated parsing of same element" do
      parser = Parsanol::Atoms::Str.new("a").repeat(1, 3)
      source = Parsanol::Source.new("aaa")

      result = parser.apply(source, context, false)
      expect(result.first).to be true
      expect(result.last).to eq([:repetition, "a", "a", "a"])
    end

    it "reuses cached prefix for repetitions" do
      parser = Parsanol::Atoms::Str.new("x").repeat(2, 5)
      source = Parsanol::Source.new("xxxxx")

      # First parse
      result1 = parser.apply(source, context, false)
      expect(result1.first).to be true

      # Reset source and parse again - should hit cache
      source = Parsanol::Source.new("xxxxx")
      result2 = parser.apply(source, context, false)
      expect(result2.first).to be true
      expect(result2.last).to eq(result1.last)
    end

    it "reuses cached repetition results without reparsing the inner atom" do
      atom = counting_atom_class.new("x")
      parser = atom.repeat(2, 5)

      result1 = parser.try(Parsanol::Source.new("xxxxx"), context, false)
      calls_after_first_parse = atom.calls
      result2 = parser.try(Parsanol::Source.new("xxxxx"), context, false)

      expect(result1.first).to be true
      expect(result2.first).to be true
      expect(result2.last).to eq(result1.last)
      expect(atom.calls).to eq(calls_after_first_parse)
    end

    it "rechecks consume-all on cached repetition hits" do
      parser = Parsanol::Atoms::Str.new("r").repeat(1, 2)

      result1 = parser.try(Parsanol::Source.new("rrr"), context, false)
      result2 = parser.try(Parsanol::Source.new("rrr"), context, true)

      expect(result1.first).to be true
      expect(result2.first).to be false
    end

    it "does not cache repetitions that fail the minimum bound" do
      atom = counting_atom_class.new("r")
      parser = atom.repeat(3, 5)

      result1 = parser.try(Parsanol::Source.new("rr"), context, false)
      calls_after_first_parse = atom.calls
      result2 = parser.try(Parsanol::Source.new("rr"), context, false)

      expect(result1.first).to be false
      expect(result2.first).to be false
      expect(atom.calls).to be > calls_after_first_parse
    end

    it "ignores stale cache entries that point past the end of the input" do
      parser = Parsanol::Atoms::Str.new("a").repeat(2, 5)

      result1 = parser.try(Parsanol::Source.new("aaaaa"), context, false)
      result2 = parser.try(Parsanol::Source.new("ab"), context, false)

      expect(result1.first).to be true
      expect(result2.first).to be false
    end

    it "evicts stale cache entries so later parses can replay fresh results" do
      atom = counting_atom_class.new("a")
      parser = atom.repeat(1, 5)

      parser.try(Parsanol::Source.new("aaaaa"), context, false)
      parser.try(Parsanol::Source.new("ab"), context, false)
      calls_after_recache = atom.calls
      result = parser.try(Parsanol::Source.new("ab"), context, false)

      expect(result.first).to be true
      expect(result.last).to eq([:repetition, "a"])
      expect(atom.calls).to eq(calls_after_recache)
    end

    it "keeps child causes when a cached replay fails consume-all" do
      reporting = Parsanol::Atoms::Context.new(
        Parsanol::ErrorReporter::Tree.new, interval_cache: true
      )
      parser = Parsanol::Atoms::Str.new("r").repeat(1)

      first = parser.try(Parsanol::Source.new("rrb"), reporting, false)
      success, cause = parser.try(Parsanol::Source.new("rrb"), reporting, true)

      expect(first.first).to be true
      expect(success).to be false
      expect(cause.ascii_tree).to include('Expected "r", but got "b"')
    end

    it "renders replayed consume-all failures of max-bounded repetitions" do
      reporting = Parsanol::Atoms::Context.new(
        Parsanol::ErrorReporter::Tree.new, interval_cache: true
      )
      parser = Parsanol::Atoms::Str.new("r").repeat(1, 2)

      first = parser.try(Parsanol::Source.new("rrr"), reporting, false)
      success, cause = parser.try(Parsanol::Source.new("rrr"), reporting, true)

      expect(first.first).to be true
      expect(success).to be false
      expect(cause.ascii_tree).to include("Extra input after last repetition")
    end

    it "does not tree-memoize repetitions across dynamic evaluations" do
      calls = 0
      dyn = Parsanol.dynamic do |_source, _context|
        calls += 1
        Parsanol.str("x")
      end
      parser = dyn.repeat(1, 2)

      parser.try(Parsanol::Source.new("xx"), context, false)
      calls_after_first_parse = calls
      parser.try(Parsanol::Source.new("xx"), context, false)

      expect(calls).to be > calls_after_first_parse
    end

    it "handles variable repetitions with .maybe" do
      parser = Parsanol::Atoms::Str.new("b").maybe
      source = Parsanol::Source.new("b")

      result = parser.apply(source, context, false)
      expect(result.first).to be true
      expect(result.last).to eq([:maybe, "b"])
    end

    it "handles empty repetitions" do
      parser = Parsanol::Atoms::Str.new("c").repeat(0, 2)
      source = Parsanol::Source.new("")

      result = parser.apply(source, context, false)
      expect(result.first).to be true
      expect(result.last).to eq([:repetition])
    end

    it "respects min bound in tree memoization" do
      parser = Parsanol::Atoms::Str.new("d").repeat(2, 4)
      source = Parsanol::Source.new("d")

      result = parser.apply(source, context, false)
      expect(result.first).to be false
    end

    it "respects max bound in tree memoization" do
      parser = Parsanol::Atoms::Str.new("e").repeat(1, 3)
      source = Parsanol::Source.new("eeeee")

      result = parser.apply(source, context, false)
      expect(result.first).to be true
      # Should stop at max=3
      expect(result.last).to eq([:repetition, "e", "e", "e"])
      expect(source.chars_left).to eq(2) # 2 'e's left unparsed
    end
  end

  describe "Context tree memoization methods" do
    it "returns true for use_tree_memoization? when enabled" do
      expect(context.use_tree_memoization?).to be true
    end

    it "returns false for use_tree_memoization? when disabled" do
      context_no_tree = Parsanol::Atoms::Context.new
      expect(context_no_tree.use_tree_memoization?).to be false
    end

    it "retrieves tree memo entries by exact start position" do
      context.store_tree_memo(:rule, 2, ["value"], 5)

      expect(context.query_tree_memo(:rule, 2)).to eq([["value"], 5])
      expect(context.query_tree_memo(:rule, 3)).to be_nil
    end
  end

  describe "Integration with complex parsers" do
    it "handles nested repetitions" do
      inner = Parsanol::Atoms::Str.new("a")
      outer = inner.repeat(1, 2).repeat(1, 2)
      source = Parsanol::Source.new("aaaa")

      result = outer.apply(source, context, false)
      expect(result.first).to be true
    end
  end

  describe "Performance characteristics" do
    it "benefits from caching on repeated parses at same position" do
      parser = Parsanol::Atoms::Str.new("m").repeat(3, 5)
      source = Parsanol::Source.new("mmmmm")

      # First parse - miss
      result1 = parser.apply(source, context, false)

      # Second parse at same position - should hit cache
      source2 = Parsanol::Source.new("mmmmm")
      result2 = parser.apply(source2, context, false)

      expect(result1.first).to be true
      expect(result2.first).to be true
      expect(result1.last).to eq(result2.last)
    end

    it "handles large repetitions efficiently" do
      parser = Parsanol::Atoms::Str.new("z").repeat(10, 50)
      input = "z" * 50
      source = Parsanol::Source.new(input)

      result = parser.apply(source, context, false)
      expect(result.first).to be true
      expect(result.last.size).to eq(51) # [:repetition] + 50 'z's
    end
  end

  describe "Error handling" do
    it "returns proper errors when min not met" do
      parser = Parsanol::Atoms::Str.new("q").repeat(3, 5)
      source = Parsanol::Source.new("qq")

      result = parser.apply(source, context, false)
      expect(result.first).to be false
    end

    it "handles unconsumed input errors" do
      parser = Parsanol::Atoms::Str.new("r").repeat(1, 2)
      source = Parsanol::Source.new("rrr")

      result = parser.apply(source, context, true) # consume_all=true
      # Should fail because not all input consumed
      expect(result.first).to be false
    end
  end

  describe "Backward compatibility" do
    it "works without tree memoization enabled" do
      context_no_tree = Parsanol::Atoms::Context.new
      parser = Parsanol::Atoms::Str.new("t").repeat(2, 4)
      source = Parsanol::Source.new("tttt")

      result = parser.apply(source, context_no_tree, false)
      expect(result.first).to be true
      expect(result.last).to eq([:repetition, "t", "t", "t", "t"])
    end
  end
end
