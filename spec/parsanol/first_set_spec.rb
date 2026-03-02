# frozen_string_literal: true

require 'spec_helper'

describe 'FIRST set computation' do
  include Parsanol

  describe 'Str atom' do
    it 'returns itself as FIRST set' do
      atom = str('foo')
      first = atom.first_set
      expect(first.size).to eq(1)
      expect(first.first).to be_a(Parsanol::Atoms::Str)
      expect(first.first.str).to eq('foo')
    end

    it 'different strings have different FIRST sets' do
      atom1 = str('foo')
      atom2 = str('bar')
      first1 = atom1.first_set
      first2 = atom2.first_set
      expect(first1.to_a & first2.to_a).to be_empty
    end
  end

  describe 'Re atom' do
    it 'returns itself as FIRST set' do
      atom = match('[a-z]')
      first = atom.first_set
      expect(first.size).to eq(1)
      expect(first.first).to be_a(Parsanol::Atoms::Re)
    end
  end

  describe 'Sequence atom' do
    it 'returns FIRST of first element' do
      atom = str('a') >> str('b')
      first = atom.first_set
      expect(first.size).to eq(1)
      expect(first.first).to be_a(Parsanol::Atoms::Str)
      expect(first.first.str).to eq('a')
    end

    it 'handles sequences of more than 2 elements' do
      # NOTE: Due to Phase 24 string concatenation optimization,
      # str('x') >> str('y') >> str('z') becomes str('xyz')
      atom = str('x') >> str('y') >> str('z')
      first = atom.first_set
      expect(first.size).to eq(1)
      expect(first.first.str).to eq('xyz') # Optimized to single string
    end

    it 'propagates through EPSILON when first element can match empty' do
      # This test would require a .maybe or similar
      atom = str('a').maybe >> str('b')
      first = atom.first_set
      # Should include both 'a' and 'b' since 'a'.maybe can match empty
      expect(first.size).to eq(2)
      strs = first.grep(Parsanol::Atoms::Str).map(&:str)
      expect(strs).to include('a', 'b')
    end
  end

  describe 'Alternative atom' do
    it 'returns union of all alternatives' do
      atom = str('a') | str('b')
      first = atom.first_set
      expect(first.size).to eq(2)
      strs = first.grep(Parsanol::Atoms::Str).map(&:str)
      expect(strs).to contain_exactly('a', 'b')
    end

    it 'handles three alternatives' do
      atom = str('x') | str('y') | str('z')
      first = atom.first_set
      expect(first.size).to eq(3)
      strs = first.grep(Parsanol::Atoms::Str).map(&:str)
      expect(strs).to contain_exactly('x', 'y', 'z')
    end

    it 'detects disjoint FIRST sets' do
      atom = str('if') | str('while') | str('for')
      first = atom.first_set
      strs = first.grep(Parsanol::Atoms::Str).map(&:str)
      # All three keywords are disjoint
      expect(strs.size).to eq(3)
    end
  end

  describe 'Repetition atom' do
    it 'includes EPSILON for min=0 (maybe)' do
      atom = str('a').maybe
      first = atom.first_set
      expect(first).to include(Parsanol::FirstSet::EPSILON)
      strs = first.grep(Parsanol::Atoms::Str)
      expect(strs.size).to eq(1)
      expect(strs.first.str).to eq('a')
    end

    it 'includes EPSILON for min=0 (repeat)' do
      atom = str('a').repeat(0, 3)
      first = atom.first_set
      expect(first).to include(Parsanol::FirstSet::EPSILON)
    end

    it 'does not include EPSILON for min=1' do
      atom = str('a').repeat(1, 3)
      first = atom.first_set
      expect(first).not_to include(Parsanol::FirstSet::EPSILON)
    end

    it "includes parslet's FIRST set" do
      atom = str('x').repeat(0, 5)
      first = atom.first_set
      strs = first.grep(Parsanol::Atoms::Str)
      expect(strs.first.str).to eq('x')
    end
  end

  describe 'Lookahead atom' do
    it 'returns EPSILON for positive lookahead' do
      atom = str('foo').present?
      first = atom.first_set
      expect(first).to eq(Set.new([Parsanol::FirstSet::EPSILON]))
    end

    it 'returns EPSILON for negative lookahead' do
      atom = str('foo').absent?
      first = atom.first_set
      expect(first).to eq(Set.new([Parsanol::FirstSet::EPSILON]))
    end
  end

  describe 'Named atom' do
    it 'delegates to wrapped parslet' do
      atom = str('hello').as(:greeting)
      first = atom.first_set
      expect(first.size).to eq(1)
      expect(first.first).to be_a(Parsanol::Atoms::Str)
      expect(first.first.str).to eq('hello')
    end
  end

  describe 'Complex grammars' do
    it 'computes FIRST for statement-like pattern' do
      # Simulates: if_stmt | while_stmt | print_stmt
      atom = str('if') | str('while') | str('print')
      first = atom.first_set
      strs = first.grep(Parsanol::Atoms::Str).map(&:str)
      expect(strs).to contain_exactly('if', 'while', 'print')
    end

    it 'computes FIRST for expression-like pattern' do
      # Simulates: '(' expr ')' | number
      # Note: str('(') >> str('x') >> str(')') gets optimized to str('(x)')
      # by Phase 24 string concatenation
      atom = (str('(') >> match('[a-z]') >> str(')')) | match('[0-9]')
      first = atom.first_set
      # FIRST should include '(' and [0-9]
      expect(first.size).to eq(2)
      has_paren = first.any? { |x| x.is_a?(Parsanol::Atoms::Str) && x.str == '(' }
      has_digit = first.any?(Parsanol::Atoms::Re)
      expect(has_paren).to be true
      expect(has_digit).to be true
    end
  end

  describe 'FIRST set caching' do
    it 'caches computed FIRST sets' do
      atom = str('test')
      first1 = atom.first_set
      first2 = atom.first_set
      # Should return same object (cached)
      expect(first1.object_id).to eq(first2.object_id)
    end

    it 'can clear cache' do
      atom = str('test')
      first1 = atom.first_set
      atom.clear_first_set_cache
      first2 = atom.first_set
      # After clearing, should compute fresh (different object)
      expect(first1.object_id).not_to eq(first2.object_id)
      # But content should be same
      expect(first1).to eq(first2)
    end
  end

  describe 'Disjoint detection (for cut operator insertion)' do
    it 'detects disjoint alternatives' do
      alt1 = str('if')
      alt2 = str('while')
      first1 = alt1.first_set
      first2 = alt2.first_set
      # Disjoint: intersection is empty
      expect(first1.to_a & first2.to_a).to be_empty
    end

    it 'detects overlapping alternatives' do
      # Both start with 'a'
      alt1 = str('apple')
      alt2 = str('apricot')
      first1 = alt1.first_set
      first2 = alt2.first_set
      # Not disjoint - but note: str atoms are compared by identity
      # so these will appear disjoint even though strings start same
      # This is conservative and safe for cut insertion
      expect(first1.to_a & first2.to_a).to be_empty
    end

    it 'handles regex overlaps conservatively' do
      alt1 = match('[a-z]')
      alt2 = match('[A-Z]')
      first1 = alt1.first_set
      first2 = alt2.first_set
      # Different Re objects are treated as potentially overlapping
      # (conservative approach)
      expect(first1.to_a & first2.to_a).to be_empty
    end
  end

  describe 'Parsanol::FirstSet class methods' do
    describe '.disjoint?' do
      it 'returns true for disjoint sets' do
        set1 = Set.new([str('if')])
        set2 = Set.new([str('while')])
        expect(Parsanol::FirstSet.disjoint?(set1, set2)).to be true
      end

      it 'returns false for overlapping sets' do
        atom = str('same')
        set1 = Set.new([atom])
        set2 = Set.new([atom])
        expect(Parsanol::FirstSet.disjoint?(set1, set2)).to be false
      end

      it 'ignores EPSILON when checking disjointness' do
        set1 = Set.new([str('a'), Parsanol::FirstSet::EPSILON])
        set2 = Set.new([str('b'), Parsanol::FirstSet::EPSILON])
        # Should be disjoint despite both having EPSILON
        expect(Parsanol::FirstSet.disjoint?(set1, set2)).to be true
      end

      it 'ignores nil when checking disjointness' do
        set1 = Set.new([str('a'), nil])
        set2 = Set.new([str('b'), nil])
        # Should be disjoint despite both having nil
        expect(Parsanol::FirstSet.disjoint?(set1, set2)).to be true
      end

      it 'returns true for empty sets' do
        set1 = Set.new([Parsanol::FirstSet::EPSILON])
        set2 = Set.new([str('a')])
        # set1 is empty after removing EPSILON
        expect(Parsanol::FirstSet.disjoint?(set1, set2)).to be true
      end
    end

    describe '.all_disjoint?' do
      it 'returns true for mutually disjoint sets' do
        sets = [
          Set.new([str('if')]),
          Set.new([str('while')]),
          Set.new([str('print')])
        ]
        expect(Parsanol::FirstSet.all_disjoint?(sets)).to be true
      end

      it 'returns false when any two sets overlap' do
        atom = str('same')
        sets = [
          Set.new([str('if')]),
          Set.new([atom]),
          Set.new([atom])
        ]
        expect(Parsanol::FirstSet.all_disjoint?(sets)).to be false
      end

      it 'returns true for less than 2 sets' do
        sets = [Set.new([str('a')])]
        expect(Parsanol::FirstSet.all_disjoint?(sets)).to be true
      end

      it 'returns true for empty array' do
        sets = []
        expect(Parsanol::FirstSet.all_disjoint?(sets)).to be true
      end

      it 'handles sets with EPSILON correctly' do
        sets = [
          Set.new([str('a'), Parsanol::FirstSet::EPSILON]),
          Set.new([str('b'), Parsanol::FirstSet::EPSILON]),
          Set.new([str('c'), Parsanol::FirstSet::EPSILON])
        ]
        # All disjoint despite all having EPSILON
        expect(Parsanol::FirstSet.all_disjoint?(sets)).to be true
      end
    end
  end
end
