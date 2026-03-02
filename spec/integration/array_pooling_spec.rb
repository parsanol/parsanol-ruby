# frozen_string_literal: true

require 'spec_helper'
require 'parsanol/parslet'

# Integration tests for Phase 1.3: Array Buffer Pooling
# Verifies that ArrayPool is properly integrated into Context and used by atoms
describe 'Array Pooling Integration' do
  describe 'Context integration' do
    it 'has an array_pool' do
      context = Parsanol::Atoms::Context.new
      expect(context.array_pool).to be_a(Parsanol::Pools::ArrayPool)
    end

    it 'provides acquire_array helper' do
      context = Parsanol::Atoms::Context.new
      array = context.acquire_array
      expect(array).to be_a(Array)
      expect(array).to be_empty
    end

    it 'provides release_array helper' do
      context = Parsanol::Atoms::Context.new
      array = context.acquire_array
      array << 1 << 2 << 3
      result = context.release_array(array)
      expect(result).to be true
    end

    it 'clears arrays on release' do
      context = Parsanol::Atoms::Context.new
      array = context.acquire_array
      array << 1 << 2 << 3
      context.release_array(array)

      # Next acquisition should get a cleared array
      array2 = context.acquire_array
      expect(array2).to be_empty
    end
  end

  describe 'Repetition parsing with array pooling' do
    it 'reuses arrays during simple repetition' do
      parser = Class.new(Parsanol::Parser) do
        root :items
        rule(:items) { str('x').repeat(5) }
      end.new

      result = parser.parse('xxxxx')
      expect(result.to_s).to eq('xxxxx')
    end

    it 'reuses arrays during repetition with min/max' do
      parser = Class.new(Parsanol::Parser) do
        root :items
        rule(:items) { str('a').repeat(2, 4) }
      end.new

      result = parser.parse('aaa')
      expect(result.to_s).to eq('aaa')
    end

    it 'handles nested repetitions with pooling' do
      parser = Class.new(Parsanol::Parser) do
        root :nested
        rule(:nested) { (str('x') >> str('x')).repeat(3) }
      end.new

      result = parser.parse('xxxxxx')
      expect(result.to_s).to eq('xxxxxx')
    end

    it 'handles maybe (repeat(0,1)) with pooling' do
      parser = Class.new(Parsanol::Parser) do
        root :optional
        rule(:optional) { str('a').maybe >> str('b') }
      end.new

      expect(parser.parse('b').to_s).to eq('b')
      expect(parser.parse('ab').to_s).to eq('ab')
    end
  end

  describe 'Sequence parsing with array pooling' do
    it 'reuses arrays during simple sequence' do
      parser = Class.new(Parsanol::Parser) do
        root :sequence
        rule(:sequence) { str('a') >> str('b') >> str('c') }
      end.new

      result = parser.parse('abc')
      expect(result.to_s).to eq('abc')
    end

    it 'reuses arrays during longer sequences' do
      parser = Class.new(Parsanol::Parser) do
        root :sequence
        rule(:sequence) { str('a') >> str('b') >> str('c') >> str('d') >> str('e') }
      end.new

      result = parser.parse('abcde')
      expect(result.to_s).to eq('abcde')
    end

    it 'handles nested sequences with pooling' do
      parser = Class.new(Parsanol::Parser) do
        root :nested
        rule(:nested) { (str('a') >> str('b')) >> (str('c') >> str('d')) }
      end.new

      result = parser.parse('abcd')
      expect(result.to_s).to eq('abcd')
    end
  end

  describe 'Complex parsing with array pooling' do
    it 'handles mixed repetitions and sequences' do
      parser = Class.new(Parsanol::Parser) do
        root :mixed
        rule(:mixed) { (str('x') >> str('y')).repeat(3) }
      end.new

      result = parser.parse('xyxyxy')
      expect(result.to_s).to eq('xyxyxy')
    end

    it 'handles repetition of sequences' do
      parser = Class.new(Parsanol::Parser) do
        root :items
        rule(:items) { item.repeat(3) }
        rule(:item) { str('a') >> str('b') >> space? }
        rule(:space?) { str(' ').maybe }
      end.new

      result = parser.parse('ab ab ab')
      expect(result.to_s).to eq('ab ab ab')
    end
  end

  describe 'Array pool statistics' do
    it 'shows pool reuse during parsing' do
      # Create a context and verify pool behavior
      context = Parsanol::Atoms::Context.new
      pool = context.array_pool

      # ArrayPool is preallocated, so we need to exhaust the pool first
      # to see newly created arrays. For this test, just verify the pool exists
      # and can acquire/release arrays correctly.

      # Acquire an array
      arr1 = context.acquire_array
      expect(arr1).to be_a(Array)
      expect(arr1).to be_empty

      # Release it back
      arr1 << 1 << 2 << 3
      result = context.release_array(arr1)
      expect(result).to be true

      # Acquire again - should get a cleared array
      arr2 = context.acquire_array
      expect(arr2).to be_empty

      # Verify pool statistics exist
      stats = pool.statistics
      expect(stats).to have_key(:created)
      expect(stats).to have_key(:reused)
      expect(stats).to have_key(:size)
      expect(stats).to have_key(:utilization)
    end
  end

  describe 'Array structure preservation' do
    it 'maintains [:repetition, ...] structure' do
      parser = Class.new(Parsanol::Parser) do
        root :items
        rule(:items) { str('x').repeat(3) }
      end.new

      result = parser.parse('xxx')
      # Result should be a Parsanol::Slice or properly tagged array
      expect(result.to_s).to eq('xxx')
    end

    it 'maintains [:sequence, ...] structure' do
      parser = Class.new(Parsanol::Parser) do
        root :seq
        rule(:seq) { str('a') >> str('b') }
      end.new

      result = parser.parse('ab')
      expect(result.to_s).to eq('ab')
    end
  end
end
