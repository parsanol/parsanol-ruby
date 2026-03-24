# frozen_string_literal: true

require "spec_helper"

describe Parsanol::Optimizer, ".simplify_lookaheads" do
  let(:str_a) { Parsanol::Atoms::Str.new("a") }
  let(:str_b) { Parsanol::Atoms::Str.new("b") }

  describe "double negation simplification" do
    it "simplifies !(!x) to &x" do
      inner = Parsanol::Atoms::Lookahead.new(str_a, false)  # !a
      outer = Parsanol::Atoms::Lookahead.new(inner, false)  # !(!a)

      result = described_class.simplify_lookaheads(outer)

      expect(result).to be_a(Parsanol::Atoms::Lookahead)
      expect(result.positive).to be true
      expect(result.bound_parslet).to eq(str_a)
    end

    it "simplifies triple negation !(!(!x)) to !x" do
      inner1 = Parsanol::Atoms::Lookahead.new(str_a, false) # !a
      inner2 = Parsanol::Atoms::Lookahead.new(inner1, false) # !(!a)
      outer = Parsanol::Atoms::Lookahead.new(inner2, false) # !(!(!a))

      result = described_class.simplify_lookaheads(outer)

      expect(result).to be_a(Parsanol::Atoms::Lookahead)
      expect(result.positive).to be false
      expect(result.bound_parslet).to eq(str_a)
    end
  end

  describe "idempotent positive lookahead" do
    it "simplifies &(&x) to &x" do
      inner = Parsanol::Atoms::Lookahead.new(str_a, true)  # &a
      outer = Parsanol::Atoms::Lookahead.new(inner, true)  # &(&a)

      result = described_class.simplify_lookaheads(outer)

      expect(result).to be_a(Parsanol::Atoms::Lookahead)
      expect(result.positive).to be true
      expect(result.bound_parslet).to eq(str_a)
    end

    it "simplifies &(&(&x)) to &x" do
      inner1 = Parsanol::Atoms::Lookahead.new(str_a, true) # &a
      inner2 = Parsanol::Atoms::Lookahead.new(inner1, true) # &(&a)
      outer = Parsanol::Atoms::Lookahead.new(inner2, true)  # &(&(&a))

      result = described_class.simplify_lookaheads(outer)

      expect(result).to be_a(Parsanol::Atoms::Lookahead)
      expect(result.positive).to be true
      expect(result.bound_parslet).to eq(str_a)
    end
  end

  describe "negative of positive simplification" do
    it "simplifies !(&x) to !x" do
      inner = Parsanol::Atoms::Lookahead.new(str_a, true)   # &a
      outer = Parsanol::Atoms::Lookahead.new(inner, false)  # !(&a)

      result = described_class.simplify_lookaheads(outer)

      expect(result).to be_a(Parsanol::Atoms::Lookahead)
      expect(result.positive).to be false
      expect(result.bound_parslet).to eq(str_a)
    end
  end

  describe "positive of negative simplification" do
    it "simplifies &(!x) to !x" do
      inner = Parsanol::Atoms::Lookahead.new(str_a, false)  # !a
      outer = Parsanol::Atoms::Lookahead.new(inner, true)   # &(!a)

      result = described_class.simplify_lookaheads(outer)

      expect(result).to be_a(Parsanol::Atoms::Lookahead)
      expect(result.positive).to be false
      expect(result.bound_parslet).to eq(str_a)
    end
  end

  describe "recursive optimization" do
    it "optimizes lookaheads nested in sequences" do
      # Sequence(!(!a), b) => Sequence(&a, b)
      inner = Parsanol::Atoms::Lookahead.new(str_a, false)
      outer = Parsanol::Atoms::Lookahead.new(inner, false)
      seq = Parsanol::Atoms::Sequence.new(outer, str_b)

      result = described_class.simplify_lookaheads(seq)

      expect(result).to be_a(Parsanol::Atoms::Sequence)
      expect(result.parslets[0]).to be_a(Parsanol::Atoms::Lookahead)
      expect(result.parslets[0].positive).to be true
      expect(result.parslets[1]).to eq(str_b)
    end

    it "optimizes lookaheads nested in alternatives" do
      # Alternative(!(!a), b) => Alternative(&a, b)
      inner = Parsanol::Atoms::Lookahead.new(str_a, false)
      outer = Parsanol::Atoms::Lookahead.new(inner, false)
      alt = Parsanol::Atoms::Alternative.new(outer, str_b)

      result = described_class.simplify_lookaheads(alt)

      expect(result).to be_a(Parsanol::Atoms::Alternative)
      expect(result.alternatives[0]).to be_a(Parsanol::Atoms::Lookahead)
      expect(result.alternatives[0].positive).to be true
      expect(result.alternatives[1]).to eq(str_b)
    end

    it "optimizes lookaheads nested in repetitions" do
      # Repetition(!(!a)) => Repetition(&a)
      inner = Parsanol::Atoms::Lookahead.new(str_a, false)
      outer = Parsanol::Atoms::Lookahead.new(inner, false)
      rep = Parsanol::Atoms::Repetition.new(outer, 0, nil, nil)

      result = described_class.simplify_lookaheads(rep)

      expect(result).to be_a(Parsanol::Atoms::Repetition)
      expect(result.parslet).to be_a(Parsanol::Atoms::Lookahead)
      expect(result.parslet.positive).to be true
    end

    it "optimizes lookaheads nested in named atoms" do
      # Named(!(!a)) => Named(&a)
      inner = Parsanol::Atoms::Lookahead.new(str_a, false)
      outer = Parsanol::Atoms::Lookahead.new(inner, false)
      named = Parsanol::Atoms::Named.new(outer, :test)

      result = described_class.simplify_lookaheads(named)

      expect(result).to be_a(Parsanol::Atoms::Named)
      expect(result.parslet).to be_a(Parsanol::Atoms::Lookahead)
      expect(result.parslet.positive).to be true
    end
  end

  describe "preserving semantics" do
    it "does not modify leaf atoms" do
      result = described_class.simplify_lookaheads(str_a)
      expect(result).to eq(str_a)
    end

    it "does not modify single lookahead" do
      la = Parsanol::Atoms::Lookahead.new(str_a, true)
      result = described_class.simplify_lookaheads(la)

      expect(result).to eq(la)
    end

    it "does not modify negative single lookahead" do
      la = Parsanol::Atoms::Lookahead.new(str_a, false)
      result = described_class.simplify_lookaheads(la)

      expect(result).to eq(la)
    end
  end

  describe "structural verification" do
    it "double negation creates correct structure" do
      # !(!str('a')) => &str('a')
      inner = Parsanol::Atoms::Lookahead.new(str_a, false)
      outer = Parsanol::Atoms::Lookahead.new(inner, false)

      optimized = described_class.simplify_lookaheads(outer)

      # Optimized version should be positive lookahead
      expect(optimized).to be_a(Parsanol::Atoms::Lookahead)
      expect(optimized.positive).to be true
      expect(optimized.bound_parslet).to eq(str_a)
    end

    it "idempotent positive lookahead creates correct structure" do
      # &(&str('a')) => &str('a')
      inner = Parsanol::Atoms::Lookahead.new(str_a, true)
      outer = Parsanol::Atoms::Lookahead.new(inner, true)

      optimized = described_class.simplify_lookaheads(outer)

      # Should be simplified to single positive lookahead
      expect(optimized).to be_a(Parsanol::Atoms::Lookahead)
      expect(optimized.positive).to be true
      expect(optimized.bound_parslet).to eq(str_a)
    end

    it "negative of positive creates correct structure" do
      # !(&str('a')) => !str('a')
      inner = Parsanol::Atoms::Lookahead.new(str_a, true)
      outer = Parsanol::Atoms::Lookahead.new(inner, false)

      optimized = described_class.simplify_lookaheads(outer)

      # Should be simplified to negative lookahead
      expect(optimized).to be_a(Parsanol::Atoms::Lookahead)
      expect(optimized.positive).to be false
      expect(optimized.bound_parslet).to eq(str_a)
    end

    it "complex nested lookaheads create correct structure" do
      # Sequence(&(!(!str('a'))), str('a')) => Sequence(&str('a'), str('a'))
      inner1 = Parsanol::Atoms::Lookahead.new(str_a, false)
      inner2 = Parsanol::Atoms::Lookahead.new(inner1, false)
      outer = Parsanol::Atoms::Lookahead.new(inner2, true)
      seq = Parsanol::Atoms::Sequence.new(outer, str_a)

      optimized = described_class.simplify_lookaheads(seq)

      # Should have optimized lookahead in sequence
      expect(optimized).to be_a(Parsanol::Atoms::Sequence)
      expect(optimized.parslets[0]).to be_a(Parsanol::Atoms::Lookahead)
      expect(optimized.parslets[0].positive).to be true
      expect(optimized.parslets[1]).to eq(str_a)
    end
  end

  describe "complex optimization scenarios" do
    it "handles alternating positive and negative lookaheads" do
      # !(&(!(&a))) => &a
      la1 = Parsanol::Atoms::Lookahead.new(str_a, true)   # &a
      la2 = Parsanol::Atoms::Lookahead.new(la1, false)    # !(&a) => !a
      la3 = Parsanol::Atoms::Lookahead.new(la2, true)     # &(!a) => !a
      la4 = Parsanol::Atoms::Lookahead.new(la3, false)    # !(!a) => &a

      result = described_class.simplify_lookaheads(la4)

      expect(result).to be_a(Parsanol::Atoms::Lookahead)
      expect(result.positive).to be true
      expect(result.bound_parslet).to eq(str_a)
    end

    it "optimizes lookaheads at multiple levels" do
      # Sequence(Alternative(!(!a), &(&b)), str('c'))
      la1 = Parsanol::Atoms::Lookahead.new(str_a, false)
      la2 = Parsanol::Atoms::Lookahead.new(la1, false)  # Should become &a
      la3 = Parsanol::Atoms::Lookahead.new(str_b, true)
      la4 = Parsanol::Atoms::Lookahead.new(la3, true)   # Should become &b
      alt = Parsanol::Atoms::Alternative.new(la2, la4)
      seq = Parsanol::Atoms::Sequence.new(alt, Parsanol::Atoms::Str.new("c"))

      result = described_class.simplify_lookaheads(seq)

      expect(result).to be_a(Parsanol::Atoms::Sequence)
      alt_result = result.parslets[0]
      expect(alt_result).to be_a(Parsanol::Atoms::Alternative)
      expect(alt_result.alternatives[0].positive).to be true
      expect(alt_result.alternatives[1].positive).to be true
    end
  end
end
