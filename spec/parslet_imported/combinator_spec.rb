# frozen_string_literal: true

# Imported from Parslet test suite
# Original: https://github.com/kschiess/parslet/blob/main/spec/combinator_spec.rb
#
# These tests verify that Parsanol::Parslet behaves identically to Parslet
# for the core combinator operations.

require_relative 'spec_helper'

RSpec.describe 'Parslet Combinators' do
  let(:parslet) do
    ENV['PARSANOL_BACKEND'] == 'parslet' ? Parslet : Parsanol::Parslet
  end

  describe 'sequence (>>) combinator' do
    it 'matches sequences in order' do
      parser = parslet.str('a') >> parslet.str('b')
      expect(parser.parse('ab')).to eq('ab')
    end

    it 'fails on first part failure' do
      parser = parslet.str('a') >> parslet.str('b')
      expect { parser.parse('xb') }.to raise_error(parslet::ParseFailed)
    end

    it 'fails on second part failure' do
      parser = parslet.str('a') >> parslet.str('b')
      expect { parser.parse('ax') }.to raise_error(parslet::ParseFailed)
    end

    it 'returns merged hash for named captures' do
      parser = parslet.str('a').as(:first) >> parslet.str('b').as(:second)
      result = parser.parse('ab')
      expect(result).to eq({ first: 'a', second: 'b' })
    end

    it 'discards unnamed matches when named captures present' do
      # This is the KEY Parslet semantic!
      parser = parslet.str('SCHEMA ') >> parslet.match('[a-z]').repeat(1).as(:name) >> parslet.str(';')
      result = parser.parse('SCHEMA test;')
      expect(result).to eq({ name: 'test' })
    end

    it 'joins consecutive unnamed strings' do
      parser = parslet.str('a') >> parslet.str('b') >> parslet.str('c')
      expect(parser.parse('abc')).to eq('abc')
    end

    it 'handles three-part sequences' do
      parser = parslet.str('a') >> parslet.str('b') >> parslet.str('c')
      expect(parser.parse('abc')).to eq('abc')
    end
  end

  describe 'alternative (|) combinator' do
    it 'tries alternatives in order' do
      parser = parslet.str('a') | parslet.str('b')
      expect(parser.parse('a')).to eq('a')
      expect(parser.parse('b')).to eq('b')
    end

    it 'succeeds on first match' do
      parser = parslet.str('a') | parslet.str('ab')
      expect(parser.parse('a')).to eq('a')
    end

    it 'tries second if first fails' do
      parser = parslet.str('x') | parslet.str('a')
      expect(parser.parse('a')).to eq('a')
    end

    it 'fails if no alternative matches' do
      parser = parslet.str('a') | parslet.str('b')
      expect { parser.parse('c') }.to raise_error(parslet::ParseFailed)
    end

    it 'handles multiple alternatives' do
      parser = parslet.str('a') | parslet.str('b') | parslet.str('c')
      expect(parser.parse('b')).to eq('b')
    end
  end

  describe 'repetition (.repeat)' do
    it 'matches zero or more times' do
      parser = parslet.match('[a-z]').repeat(0)
      expect(parser.parse('')).to eq('')
      expect(parser.parse('abc')).to eq('abc')
    end

    it 'matches one or more times' do
      parser = parslet.match('[a-z]').repeat(1)
      expect(parser.parse('abc')).to eq('abc')
      expect { parser.parse('') }.to raise_error(parslet::ParseFailed)
    end

    it 'respects min boundary' do
      parser = parslet.match('[a-z]').repeat(2)
      expect(parser.parse('ab')).to eq('ab')
      expect { parser.parse('a') }.to raise_error(parslet::ParseFailed)
    end

    it 'respects max boundary' do
      parser = parslet.match('[a-z]').repeat(0, 2)
      expect(parser.parse('ab')).to eq('ab')
      # Note: This should only parse 2 characters, not fail
    end

    it 'produces array of named captures when name comes before repeat' do
      # .as(:x).repeat(1) produces [{x: 'a'}, {x: 'b'}, {x: 'c'}]
      parser = parslet.match('[a-z]').as(:letter).repeat(1)
      result = parser.parse('abc')
      expect(result).to be_an(Array)
      expect(result.length).to eq(3)
      expect(result.first).to eq({ letter: 'a' })
    end

    it 'produces single hash when repeat comes before name' do
      # .repeat(1).as(:x) produces {x: 'abc'}
      parser = parslet.match('[a-z]').repeat(1).as(:letters)
      result = parser.parse('abc')
      expect(result).to eq({ letters: 'abc' })
    end
  end

  describe '.maybe (optional)' do
    it 'matches zero or one time' do
      parser = parslet.str('a').maybe
      expect(parser.parse('')).to eq('')
      expect(parser.parse('a')).to eq('a')
    end

    it 'does not consume more than one' do
      parser = parslet.str('a').maybe >> parslet.str('b')
      expect(parser.parse('ab')).to eq('ab')
      expect(parser.parse('b')).to eq('b')
    end

    it 'returns empty string for no match' do
      parser = parslet.str('x').maybe
      expect(parser.parse('')).to eq('')
    end
  end

  describe '.as (named capture)' do
    it 'captures match with name' do
      parser = parslet.match('[a-z]').repeat(1).as(:word)
      expect(parser.parse('hello')).to eq({ word: 'hello' })
    end

    it 'captures sequences' do
      parser = (parslet.str('a') >> parslet.str('b')).as(:pair)
      expect(parser.parse('ab')).to eq({ pair: 'ab' })
    end

    it 'captures single character' do
      parser = parslet.match('[a-z]').as(:char)
      expect(parser.parse('x')).to eq({ char: 'x' })
    end
  end
end
