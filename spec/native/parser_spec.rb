# frozen_string_literal: true

require 'spec_helper'
require 'parsanol/native'
require 'parsanol/parslet'

RSpec.describe Parsanol::Native::Parser do
  include Parsanol::Parslet

  describe '.available?' do
    it 'returns true when native extension is loaded' do
      # This test assumes the native extension has been built
      skip 'Native extension not built' unless described_class.available?

      expect(described_class.available?).to be true
    end
  end

  describe '.parse', :native do
    let(:grammar) { str('hello').as(:greeting) }
    let(:grammar_json) { described_class.serialize_grammar(grammar) }

    before do
      skip 'Native extension not available' unless described_class.available?
    end

    it 'returns a Hash with symbol keys' do
      result = described_class.parse(grammar_json, 'hello')
      expect(result).to be_a(Hash)
      expect(result.keys).to all(be_a(Symbol))
    end

    it 'returns Slice objects with correct content' do
      result = described_class.parse(grammar_json, 'hello')
      expect(result[:greeting]).to be_a(Parsanol::Slice)
      expect(result[:greeting].content).to eq('hello')
    end

    it 'returns Slice objects with correct offset' do
      result = described_class.parse(grammar_json, 'hello')
      expect(result[:greeting].offset).to eq(0)
    end

    it 'returns Slice objects with lazy line/column support' do
      result = described_class.parse(grammar_json, 'hello')
      slice = result[:greeting]
      expect(slice.line_and_column).to eq([1, 1])
    end

    context 'with multi-line input' do
      let(:grammar) { str("hello\nworld").as(:greeting) }
      let(:input) { "hello\nworld" }

      it 'computes correct line/column for first line' do
        result = described_class.parse(grammar_json, input)
        slice = result[:greeting]
        expect(slice.line_and_column).to eq([1, 1])
      end
    end

    context 'with complex grammar' do
      let(:grammar) do
        str('abc').as(:word)
      end

      it 'parses and returns named capture' do
        result = described_class.parse(grammar_json, 'abc')
        expect(result).to have_key(:word)
        expect(result[:word].content).to eq('abc')
      end
    end

    context 'with repetition' do
      let(:grammar) { str('x').repeat(2, 4).as(:letters) }

      it 'returns joined string for single-character repetition' do
        result = described_class.parse(grammar_json, 'xxx')
        # Single characters are joined into one slice
        expect(result[:letters]).to be_a(Parsanol::Slice)
        expect(result[:letters].content).to eq('xxx')
      end
    end
  end

  describe '.serialize_grammar' do
    let(:grammar) { str('test').as(:value) }

    it 'returns a JSON string' do
      result = described_class.serialize_grammar(grammar)
      expect(result).to be_a(String)
      expect { JSON.parse(result) }.not_to raise_error
    end

    it 'caches serialized grammars' do
      described_class.clear_cache

      result1 = described_class.serialize_grammar(grammar)
      result2 = described_class.serialize_grammar(grammar)

      expect(result1).to eq(result2)
      expect(described_class.cache_stats[:grammar_cache_size]).to eq(1)
    end
  end

  describe '.parse_with_grammar' do
    let(:grammar) { str('test').as(:value) }

    before do
      skip 'Native extension not available' unless described_class.available?
    end

    it 'combines serialization and parsing' do
      result = described_class.parse_with_grammar(grammar, 'test')
      expect(result[:value].content).to eq('test')
    end
  end

  describe '.clear_cache' do
    it 'clears grammar caches' do
      described_class.clear_cache
      expect(described_class.cache_stats[:grammar_cache_size]).to eq(0)
    end
  end
end
