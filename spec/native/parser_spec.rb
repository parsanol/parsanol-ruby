# frozen_string_literal: true

require 'spec_helper'
require 'parsanol/native'
require 'parsanol/parslet'

RSpec.describe Parsanol::Native::Parser do
  include Parsanol::Parslet

  describe '.available?' do
    it 'returns true when native extension is loaded' do
      skip 'Native extension not built' unless described_class.available?
      expect(described_class.available?).to be true
    end
  end

  describe '.parse', :native do
    before do
      skip 'Native extension not available' unless described_class.available?
    end

    it 'returns a Hash with symbol keys' do
      result = described_class.parse(str('hello').as(:greeting), 'hello')
      expect(result).to be_a(Hash)
      expect(result.keys).to all(be_a(Symbol))
    end

    it 'returns Slice objects with correct content' do
      result = described_class.parse(str('hello').as(:greeting), 'hello')
      expect(result[:greeting]).to be_a(Parsanol::Slice)
      expect(result[:greeting].content).to eq('hello')
    end

    it 'returns Slice objects with correct offset' do
      result = described_class.parse(str('hello').as(:greeting), 'hello')
      expect(result[:greeting].offset).to eq(0)
    end

    it 'returns Slice objects with lazy line/column support' do
      result = described_class.parse(str('hello').as(:greeting), 'hello')
      expect(result[:greeting].line_and_column).to eq([1, 1])
    end

    context 'with multi-line input' do
      it 'computes correct line/column' do
        result = described_class.parse(str("hello\nworld").as(:greeting), "hello\nworld")
        expect(result[:greeting].line_and_column).to eq([1, 1])
      end
    end

    context 'with repetition' do
      it 'returns joined string for single-character repetition' do
        result = described_class.parse(str('x').repeat(2, 4).as(:letters), 'xxx')
        expect(result[:letters]).to be_a(Parsanol::Slice)
        expect(result[:letters].content).to eq('xxx')
      end
    end

    context 'with wrapper vs repetition pattern' do
      # This tests the flatten_sequence logic that distinguishes between:
      # - Repetition: same outer key, same inner keys (e.g., [{entity: e1}, {entity: e2}])
      #   → Should keep as array
      # - Wrapper: same outer key, different inner keys (e.g., [{syntax: {spaces: s}}, {syntax: {decl: d}}])
      #   → Should merge into single hash

      it 'keeps repetition pattern as array' do
        # Grammar that produces: [{:value => 1}, {:value => 2}]
        # Both hashes have same key "value"
        g = Class.new(Parsanol::Parser) do
          rule(:item) { str('x').as(:value) }
          rule(:list) { item.repeat(2) }
          root(:list)
        end.new

        result = described_class.parse(g, 'xx')
        expect(result).to be_an(Array)
        expect(result.length).to eq(2)
        expect(result[0]).to be_a(Hash)
        expect(result[1]).to be_a(Hash)
      end

      it 'merges wrapper pattern into hash' do
        # Grammar that produces: [{:x => {:a => A}}, {:x => {:b => B}}, {:x => {:c => C}}}]
        # Outer key is "x", inner keys are :a, :b, :c (all different)
        # This is a WRAPPER pattern - should merge into single hash
        g = Class.new(Parsanol::Parser) do
          rule(:part_a) { str('A').as(:a) }
          rule(:part_b) { str('B').as(:b) }
          rule(:part_c) { str('C').as(:c) }
          rule(:item_a) { part_a.as(:x) }
          rule(:item_b) { part_b.as(:x) }
          rule(:item_c) { part_c.as(:x) }
          rule(:list) { (item_a | item_b | item_c).repeat(3) }
          root(:list)
        end.new

        result = described_class.parse(g, 'ABC')
        # Should be a hash with merged outer keys
        expect(result).to be_a(Hash)
        expect(result[:x]).to be_a(Hash)
        expect(result[:x]).to have_key(:a)
        expect(result[:x]).to have_key(:b)
        expect(result[:x]).to have_key(:c)
      end
    end
  end

  describe '.serialize_grammar' do
    it 'returns a JSON string' do
      result = described_class.serialize_grammar(str('test').as(:value))
      expect(result).to be_a(String)
      expect { JSON.parse(result) }.not_to raise_error
    end

    it 'caches serialized grammars' do
      described_class.clear_cache
      g = str('test').as(:value)
      result1 = described_class.serialize_grammar(g)
      result2 = described_class.serialize_grammar(g)
      expect(result1).to eq(result2)
      expect(described_class.cache_stats[:grammar_cache_size]).to eq(1)
    end
  end

  describe '.clear_cache' do
    it 'clears grammar caches' do
      described_class.clear_cache
      expect(described_class.cache_stats[:grammar_cache_size]).to eq(0)
    end
  end
end
