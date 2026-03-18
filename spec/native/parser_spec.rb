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
