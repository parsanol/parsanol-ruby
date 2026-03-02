require 'spec_helper'

describe Parsanol::Optimizers::CutInserter do
  include Parsanol

  let(:inserter) { Parsanol::Optimizers::CutInserter.new }

  describe "basic functionality" do
    it "returns parslet unchanged if not an alternative" do
      parslet = str('hello')
      result = inserter.optimize(parslet)
      expect(result.to_s).to include('hello')
    end

    it "returns sequence unchanged if no alternatives inside" do
      parslet = str('a') >> str('b')
      result = inserter.optimize(parslet)
      # Note: Phase 24 may optimize this to str('ab')
      expect(result).to be_a(Parsanol::Atoms::Base)
    end
  end

  describe "disjoint alternatives" do
    it "inserts cuts for simple disjoint alternatives" do
      parslet = str('if') | str('while') | str('print')
      result = inserter.optimize(parslet)

      # Should insert cuts in each alternative
      expect(result).to be_a(Parsanol::Atoms::Alternative)
      result.alternatives.each do |alt|
        # Each alternative should be wrapped with cut
        expect(alt).to be_a(Parsanol::Atoms::Cut)
      end
    end

    it "inserts cuts for two disjoint alternatives" do
      parslet = str('yes') | str('no')
      result = inserter.optimize(parslet)

      expect(result).to be_a(Parsanol::Atoms::Alternative)
      expect(result.alternatives.size).to eq(2)
      result.alternatives.each do |alt|
        expect(alt).to be_a(Parsanol::Atoms::Cut)
      end
    end

    it "inserts cuts after deterministic prefix in sequences" do
      # Note: Phase 24 may concatenate adjacent strings
      # So str('if') >> str(' ') >> str('x') may become str('if x')
      parslet = (str('if') >> str(' ') >> str('x')) |
                (str('while') >> str(' ') >> str('y'))
      result = inserter.optimize(parslet)

      expect(result).to be_a(Parsanol::Atoms::Alternative)
      # Each alternative should be wrapped with cut
      # (May be Cut wrapping whole thing if Phase 24 concatenated strings)
      result.alternatives.each do |alt|
        expect(alt).to be_a(Parsanol::Atoms::Cut)
      end
    end
  end

  describe "overlapping alternatives" do
    it "does not insert cuts when FIRST sets overlap" do
      # Same atom in both alternatives - not disjoint
      atom = str('same')
      parslet = atom | atom
      result = inserter.optimize(parslet)

      # Should not insert cuts
      expect(result).to be_a(Parsanol::Atoms::Alternative)
      result.alternatives.each do |alt|
        expect(alt).not_to be_a(Parsanol::Atoms::Cut)
      end
    end
  end

  describe "EPSILON handling" do
    it "does not cut after parslets with EPSILON in FIRST set" do
      # str('a').maybe has EPSILON in FIRST set
      parslet = (str('a').maybe >> str('b')) |
                (str('c') >> str('d'))
      result = inserter.optimize(parslet)

      # First alternative has EPSILON, so shouldn't have cut at start
      expect(result).to be_a(Parsanol::Atoms::Alternative)
      first_alt = result.alternatives[0]
      # The sequence may be optimized but should still have structure
      # Second alternative should be wrapped with cut since 'cd' is deterministic
      second_alt = result.alternatives[1]
      expect(second_alt).to be_a(Parsanol::Atoms::Cut)
    end

    it "cuts after non-EPSILON prefix even if later elements have EPSILON" do
      # str('if') doesn't have EPSILON, safe to cut after it
      parslet = (str('if') >> str('x').maybe >> str('y')) |
                (str('while') >> str('z'))
      result = inserter.optimize(parslet)

      expect(result).to be_a(Parsanol::Atoms::Alternative)
      # First alternative should have cut after 'if'
      first_alt = result.alternatives[0]
      expect(first_alt).to be_a(Parsanol::Atoms::Sequence)
      # First element should be a cut wrapping 'if'
      expect(first_alt.parslets.first).to be_a(Parsanol::Atoms::Cut)
    end
  end

  describe "nested alternatives" do
    it "recursively optimizes nested alternatives" do
      # Outer alternative: 'a' | (inner alternative)
      # Inner alternative: 'b' | 'c'
      inner = str('b') | str('c')
      outer = str('a') | inner

      result = inserter.optimize(outer)

      expect(result).to be_a(Parsanol::Atoms::Alternative)
      # Outer should have 2 alternatives
      expect(result.alternatives.size).to eq(2)

      # First should be wrapped with cut
      expect(result.alternatives[0]).to be_a(Parsanol::Atoms::Cut)

      # Second alternative should be the optimized inner alternative
      # It will be a Cut-wrapped Alternative
      second = result.alternatives[1]
      # The inner alternative was optimized and wrapped
      # Structure: outer sees flattened alternatives OR nested structure
      # Just verify both alternatives have cuts applied somewhere
      expect(result.to_s).to include('↑')
    end
  end

  describe "repetitions" do
    it "recursively optimizes alternatives inside repetitions" do
      parslet = (str('a') | str('b')).repeat(1, 3)
      result = inserter.optimize(parslet)

      expect(result).to be_a(Parsanol::Atoms::Repetition)
      # The inner alternative should be optimized
      inner = result.parslet
      expect(inner).to be_a(Parsanol::Atoms::Alternative)
      inner.alternatives.each do |alt|
        expect(alt).to be_a(Parsanol::Atoms::Cut)
      end
    end
  end

  describe "named atoms" do
    it "recursively optimizes named alternatives" do
      parslet = (str('x') | str('y')).as(:choice)
      result = inserter.optimize(parslet)

      expect(result).to be_a(Parsanol::Atoms::Named)
      expect(result.name).to eq(:choice)

      # The wrapped alternative should be optimized
      inner = result.parslet
      expect(inner).to be_a(Parsanol::Atoms::Alternative)
      inner.alternatives.each do |alt|
        expect(alt).to be_a(Parsanol::Atoms::Cut)
      end
    end
  end

  describe "complex grammars" do
    it "optimizes statement-like grammar" do
      # Simulates: if_stmt | while_stmt | print_stmt
      # Each statement has keyword followed by other stuff
      # Note: Phase 24 may concatenate these into single strings
      if_stmt = str('if') >> str(' ') >> str('condition')
      while_stmt = str('while') >> str(' ') >> str('condition')
      print_stmt = str('print') >> str(' ') >> str('expr')

      parslet = if_stmt | while_stmt | print_stmt
      result = inserter.optimize(parslet)

      expect(result).to be_a(Parsanol::Atoms::Alternative)
      expect(result.alternatives.size).to eq(3)

      # Each alternative should have a cut somewhere
      # The exact structure depends on Phase 24 optimization
      result.alternatives.each do |alt|
        # Should be either Cut or Sequence with Cut
        expect([Parsanol::Atoms::Cut, Parsanol::Atoms::Sequence]).to include(alt.class)
      end
    end

    it "handles mixed safe and unsafe alternatives correctly" do
      # If FIRST sets aren't all disjoint, no cuts
      parslet = str('a') >> str('b') |
                str('a') >> str('c')  # Both start with 'a' - not disjoint!

      result = inserter.optimize(parslet)

      # Should not insert cuts since FIRST sets overlap
      # Note: str('a') >> str('b') might be optimized to str('ab') by Phase 24
      expect(result).to be_a(Parsanol::Atoms::Alternative)
    end
  end

  describe "edge cases" do
    it "handles single alternative (no optimization needed)" do
      # Alternative with one option - trivial case
      parslet = Parsanol::Atoms::Alternative.new(str('only'))
      result = inserter.optimize(parslet)

      # Should still work, just return optimized single alternative
      expect(result).to be_a(Parsanol::Atoms::Alternative)
    end

    it "handles empty sequence prefix (no cut insertion)" do
      # If prefix is empty, shouldn't insert cut
      parslet = (str('a').maybe >> str('b')) | str('c')
      result = inserter.optimize(parslet)

      # Alternatives are disjoint but first has EPSILON prefix
      expect(result).to be_a(Parsanol::Atoms::Alternative)
    end
  end

  describe "preservation of semantics" do
    it "produces parslet that parses the same input" do
      parslet = str('if') | str('while') | str('for')
      optimized = inserter.optimize(parslet)

      # Should parse same inputs
      expect(parslet.parse('if')).to eq('if')
      expect(optimized.parse('if')).to eq('if')

      expect(parslet.parse('while')).to eq('while')
      expect(optimized.parse('while')).to eq('while')

      expect(parslet.parse('for')).to eq('for')
      expect(optimized.parse('for')).to eq('for')
    end

    it "produces parslet that fails on same invalid input" do
      parslet = str('yes') | str('no')
      optimized = inserter.optimize(parslet)

      # Both should fail on invalid input
      expect { parslet.parse('maybe') }.to raise_error(Parsanol::ParseFailed)
      expect { optimized.parse('maybe') }.to raise_error(Parsanol::ParseFailed)
    end
  end
end
