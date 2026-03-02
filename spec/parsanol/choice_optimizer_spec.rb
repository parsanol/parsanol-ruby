# frozen_string_literal: true

require 'spec_helper'

describe Parsanol::Optimizer, '.simplify_choices' do
  let(:str_a) { Parsanol::Atoms::Str.new('a') }
  let(:str_b) { Parsanol::Atoms::Str.new('b') }
  let(:str_c) { Parsanol::Atoms::Str.new('c') }

  describe 'unwrapping single alternatives' do
    it 'unwraps Alternative with single element' do
      alt = Parsanol::Atoms::Alternative.new(str_a)
      result = Parsanol::Optimizer.simplify_choices(alt)

      expect(result).to eq(str_a)
    end

    it 'leaves Alternative with multiple elements unchanged' do
      alt = Parsanol::Atoms::Alternative.new(str_a, str_b)
      result = Parsanol::Optimizer.simplify_choices(alt)

      expect(result).to be_a(Parsanol::Atoms::Alternative)
      expect(result.alternatives.size).to eq(2)
    end
  end

  describe 'flattening nested alternatives' do
    it 'flattens Alternative(Alternative(a, b), c)' do
      inner = Parsanol::Atoms::Alternative.new(str_a, str_b)
      outer = Parsanol::Atoms::Alternative.new(inner, str_c)

      result = Parsanol::Optimizer.simplify_choices(outer)

      expect(result).to be_a(Parsanol::Atoms::Alternative)
      expect(result.alternatives.size).to eq(3)
      expect(result.alternatives).to eq([str_a, str_b, str_c])
    end

    it 'flattens Alternative(a, Alternative(b, c))' do
      inner = Parsanol::Atoms::Alternative.new(str_b, str_c)
      outer = Parsanol::Atoms::Alternative.new(str_a, inner)

      result = Parsanol::Optimizer.simplify_choices(outer)

      expect(result).to be_a(Parsanol::Atoms::Alternative)
      expect(result.alternatives.size).to eq(3)
      expect(result.alternatives).to eq([str_a, str_b, str_c])
    end

    it 'flattens Alternative(Alternative(a, b), Alternative(c, d))' do
      inner1 = Parsanol::Atoms::Alternative.new(str_a, str_b)
      inner2 = Parsanol::Atoms::Alternative.new(str_c, Parsanol::Atoms::Str.new('d'))
      outer = Parsanol::Atoms::Alternative.new(inner1, inner2)

      result = Parsanol::Optimizer.simplify_choices(outer)

      expect(result).to be_a(Parsanol::Atoms::Alternative)
      expect(result.alternatives.size).to eq(4)
    end

    it 'flattens deeply nested alternatives' do
      # Alternative(Alternative(Alternative(a, b), c), d)
      inner1 = Parsanol::Atoms::Alternative.new(str_a, str_b)
      inner2 = Parsanol::Atoms::Alternative.new(inner1, str_c)
      outer = Parsanol::Atoms::Alternative.new(inner2, Parsanol::Atoms::Str.new('d'))

      result = Parsanol::Optimizer.simplify_choices(outer)

      expect(result).to be_a(Parsanol::Atoms::Alternative)
      expect(result.alternatives.size).to eq(4)
    end
  end

  describe 'deduplicating alternatives' do
    it 'removes duplicate alternatives' do
      alt = Parsanol::Atoms::Alternative.new(str_a, str_a, str_b)
      result = Parsanol::Optimizer.simplify_choices(alt)

      expect(result).to be_a(Parsanol::Atoms::Alternative)
      expect(result.alternatives.size).to eq(2)
      expect(result.alternatives).to eq([str_a, str_b])
    end

    it 'removes all duplicates keeping first occurrence' do
      alt = Parsanol::Atoms::Alternative.new(str_a, str_b, str_a, str_c, str_b, str_a)
      result = Parsanol::Optimizer.simplify_choices(alt)

      expect(result).to be_a(Parsanol::Atoms::Alternative)
      expect(result.alternatives.size).to eq(3)
      expect(result.alternatives).to eq([str_a, str_b, str_c])
    end

    it 'unwraps when deduplication leaves single alternative' do
      alt = Parsanol::Atoms::Alternative.new(str_a, str_a, str_a)
      result = Parsanol::Optimizer.simplify_choices(alt)

      expect(result).to eq(str_a)
    end
  end

  describe 'combined optimizations' do
    it 'flattens and deduplicates in one pass' do
      # Alternative(Alternative(a, b), a, b)
      inner = Parsanol::Atoms::Alternative.new(str_a, str_b)
      outer = Parsanol::Atoms::Alternative.new(inner, str_a, str_b)

      result = Parsanol::Optimizer.simplify_choices(outer)

      expect(result).to be_a(Parsanol::Atoms::Alternative)
      expect(result.alternatives.size).to eq(2)
      expect(result.alternatives).to eq([str_a, str_b])
    end

    it 'flattens, deduplicates, and unwraps' do
      # Alternative(Alternative(a, a), a) => a
      inner = Parsanol::Atoms::Alternative.new(str_a, str_a)
      outer = Parsanol::Atoms::Alternative.new(inner, str_a)

      result = Parsanol::Optimizer.simplify_choices(outer)

      expect(result).to eq(str_a)
    end
  end

  describe 'recursive optimization' do
    it 'optimizes alternatives nested in sequences' do
      # Sequence(Alternative(a, a), b) => Sequence(a, b)
      alt = Parsanol::Atoms::Alternative.new(str_a, str_a)
      seq = Parsanol::Atoms::Sequence.new(alt, str_b)

      result = Parsanol::Optimizer.simplify_choices(seq)

      expect(result).to be_a(Parsanol::Atoms::Sequence)
      expect(result.parslets[0]).to eq(str_a)
      expect(result.parslets[1]).to eq(str_b)
    end

    it 'optimizes alternatives nested in repetitions' do
      # Repetition(Alternative(a, a)) => Repetition(a)
      alt = Parsanol::Atoms::Alternative.new(str_a, str_a)
      rep = Parsanol::Atoms::Repetition.new(alt, 0, nil, nil)

      result = Parsanol::Optimizer.simplify_choices(rep)

      expect(result).to be_a(Parsanol::Atoms::Repetition)
      expect(result.parslet).to eq(str_a)
    end

    it 'optimizes alternatives nested in lookaheads' do
      # Lookahead(Alternative(a, a)) => Lookahead(a)
      alt = Parsanol::Atoms::Alternative.new(str_a, str_a)
      la = Parsanol::Atoms::Lookahead.new(alt, true)

      result = Parsanol::Optimizer.simplify_choices(la)

      expect(result).to be_a(Parsanol::Atoms::Lookahead)
      expect(result.bound_parslet).to eq(str_a)
    end

    it 'optimizes alternatives nested in named atoms' do
      # Named(Alternative(a, a)) => Named(a)
      alt = Parsanol::Atoms::Alternative.new(str_a, str_a)
      named = Parsanol::Atoms::Named.new(alt, :test)

      result = Parsanol::Optimizer.simplify_choices(named)

      expect(result).to be_a(Parsanol::Atoms::Named)
      expect(result.parslet).to eq(str_a)
    end
  end

  describe 'preserving semantics' do
    it 'does not modify leaf atoms' do
      result = Parsanol::Optimizer.simplify_choices(str_a)
      expect(result).to eq(str_a)
    end

    it 'preserves alternative order' do
      alt = Parsanol::Atoms::Alternative.new(str_a, str_b, str_c)
      result = Parsanol::Optimizer.simplify_choices(alt)

      expect(result.alternatives).to eq([str_a, str_b, str_c])
    end

    it 'works with empty alternatives array (edge case)' do
      # This shouldn't happen in practice, but test robustness
      alt = Parsanol::Atoms::Alternative.new
      result = Parsanol::Optimizer.simplify_choices(alt)

      # Should return something reasonable (empty alternative or nil)
      # The exact behavior depends on how Alternative handles empty case
    end
  end

  describe 'functional test with parser' do
    it 'correctly parses after optimization' do
      # Create an alternative with duplicate choices
      alt = str_a | str_b | str_a | str_c | str_b

      # Optimize it
      optimized = Parsanol::Optimizer.simplify_choices(alt)

      # Should have 3 unique alternatives instead of 5
      expect(optimized).to be_a(Parsanol::Atoms::Alternative)
      expect(optimized.alternatives.size).to eq(3)

      # Should still parse correctly
      expect(optimized.parse('a')).to eq('a')
      expect(optimized.parse('b')).to eq('b')
      expect(optimized.parse('c')).to eq('c')
    end

    it 'correctly parses nested alternatives after optimization' do
      # Create nested alternatives
      alt = (str_a | str_b) | (str_c | Parsanol::Atoms::Str.new('d'))

      # Optimize it
      optimized = Parsanol::Optimizer.simplify_choices(alt)

      # Should be flattened to 4 alternatives
      expect(optimized).to be_a(Parsanol::Atoms::Alternative)
      expect(optimized.alternatives.size).to eq(4)

      # Should still parse all options
      expect(optimized.parse('a')).to eq('a')
      expect(optimized.parse('b')).to eq('b')
      expect(optimized.parse('c')).to eq('c')
      expect(optimized.parse('d')).to eq('d')
    end
  end
end
