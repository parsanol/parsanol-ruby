require 'spec_helper'

describe "Tree Memoization" do
  let(:context) { Parsanol::Atoms::Context.new(nil, interval_cache: true) }

  describe "Repetition with tree memoization" do
    it "caches repeated parsing of same element" do
      parser = Parsanol::Atoms::Str.new('a').repeat(1, 3)
      source = Parsanol::Source.new('aaa')

      result = parser.apply(source, context, false)
      expect(result.first).to be true
      expect(result.last).to eq([:repetition, 'a', 'a', 'a'])
    end

    it "reuses cached prefix for repetitions" do
      parser = Parsanol::Atoms::Str.new('x').repeat(2, 5)
      source = Parsanol::Source.new('xxxxx')

      # First parse
      result1 = parser.apply(source, context, false)
      expect(result1.first).to be true

      # Reset source and parse again - should hit cache
      source = Parsanol::Source.new('xxxxx')
      result2 = parser.apply(source, context, false)
      expect(result2.first).to be true
      expect(result2.last).to eq(result1.last)
    end

    it "handles variable repetitions with .maybe" do
      parser = Parsanol::Atoms::Str.new('b').maybe
      source = Parsanol::Source.new('b')

      result = parser.apply(source, context, false)
      expect(result.first).to be true
      expect(result.last).to eq([:maybe, 'b'])
    end

    it "handles empty repetitions" do
      parser = Parsanol::Atoms::Str.new('c').repeat(0, 2)
      source = Parsanol::Source.new('')

      result = parser.apply(source, context, false)
      expect(result.first).to be true
      expect(result.last).to eq([:repetition])
    end

    it "respects min bound in tree memoization" do
      parser = Parsanol::Atoms::Str.new('d').repeat(2, 4)
      source = Parsanol::Source.new('d')

      result = parser.apply(source, context, false)
      expect(result.first).to be false
    end

    it "respects max bound in tree memoization" do
      parser = Parsanol::Atoms::Str.new('e').repeat(1, 3)
      source = Parsanol::Source.new('eeeee')

      result = parser.apply(source, context, false)
      expect(result.first).to be true
      # Should stop at max=3
      expect(result.last).to eq([:repetition, 'e', 'e', 'e'])
      expect(source.chars_left).to eq(2)  # 2 'e's left unparsed
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
  end

  describe "Integration with complex parsers" do
    it "handles nested repetitions" do
      inner = Parsanol::Atoms::Str.new('a')
      outer = inner.repeat(1, 2).repeat(1, 2)
      source = Parsanol::Source.new('aaaa')

      result = outer.apply(source, context, false)
      expect(result.first).to be true
    end
  end

  describe "Performance characteristics" do
    it "benefits from caching on repeated parses at same position" do
      parser = Parsanol::Atoms::Str.new('m').repeat(3, 5)
      source = Parsanol::Source.new('mmmmm')

      # First parse - miss
      result1 = parser.apply(source, context, false)

      # Second parse at same position - should hit cache
      source2 = Parsanol::Source.new('mmmmm')
      result2 = parser.apply(source2, context, false)

      expect(result1.first).to be true
      expect(result2.first).to be true
      expect(result1.last).to eq(result2.last)
    end

    it "handles large repetitions efficiently" do
      parser = Parsanol::Atoms::Str.new('z').repeat(10, 50)
      input = 'z' * 50
      source = Parsanol::Source.new(input)

      result = parser.apply(source, context, false)
      expect(result.first).to be true
      expect(result.last.size).to eq(51)  # [:repetition] + 50 'z's
    end
  end

  describe "Error handling" do
    it "returns proper errors when min not met" do
      parser = Parsanol::Atoms::Str.new('q').repeat(3, 5)
      source = Parsanol::Source.new('qq')

      result = parser.apply(source, context, false)
      expect(result.first).to be false
    end

    it "handles unconsumed input errors" do
      parser = Parsanol::Atoms::Str.new('r').repeat(1, 2)
      source = Parsanol::Source.new('rrr')

      result = parser.apply(source, context, true)  # consume_all=true
      # Should fail because not all input consumed
      expect(result.first).to be false
    end
  end

  describe "Backward compatibility" do
    it "works without tree memoization enabled" do
      context_no_tree = Parsanol::Atoms::Context.new
      parser = Parsanol::Atoms::Str.new('t').repeat(2, 4)
      source = Parsanol::Source.new('tttt')

      result = parser.apply(source, context_no_tree, false)
      expect(result.first).to be true
      expect(result.last).to eq([:repetition, 't', 't', 't', 't'])
    end
  end
end
