# frozen_string_literal: true

require 'spec_helper'

class TestCustomAtom < Parsanol::Atoms::Custom
  def initialize(match_string)
    @match_string = match_string
    super()
  end

  def try_match(source, context, consume_all)
    pos = source.bytepos

    # Try to match the string using consume (returns a Slice)
    result = source.consume(@match_string.length)
    if result == @match_string
      # Success - source.consume already returned a Slice
      [true, result]
    else
      # Restore position on failure
      source.bytepos = pos
      [false, nil]
    end
  end

  def to_s_inner(prec = nil)
    "test_custom(#{@match_string.inspect})"
  end
end

RSpec.describe Parsanol::Atoms::Custom do
  let(:atom) { TestCustomAtom.new('hello') }

  it 'can be created and used for parsing' do
    result = atom.parse('hello')
    expect(result.to_s).to eq('hello')
  end

  it 'fails on non-matching input' do
    expect { atom.parse('world') }.to raise_error(Parsanol::ParseFailed)
  end

  it 'raises NotImplementedError when try_match is not implemented' do
    custom = Class.new(Parsanol::Atoms::Custom).new
    expect { custom.parse('test') }.to raise_error(NotImplementedError)
  end

  it 'can be combined with other atoms using sequence' do
    # Use as() to label results for structured output
    combined = atom.as(:first) >> Parsanol.str(' world').as(:second)
    result = combined.parse('hello world')
    expect(result).to eq({ first: 'hello', second: ' world' })
  end

  it 'supports repetition' do
    # Basic repetition - returns concatenated result by default
    repeated = atom.repeat(2, 2)
    result = repeated.parse('hellohello')
    expect(result.to_s).to eq('hellohello')
  end

  it 'can be used in alternative' do
    alt = atom | Parsanol.str('world')
    expect(alt.parse('hello').to_s).to eq('hello')
    expect(alt.parse('world').to_s).to eq('world')
  end

  it 'supports maybe' do
    maybe = atom.maybe
    expect(maybe.parse('hello').to_s).to eq('hello')
    # Maybe returns empty string when it doesn't match (standard Parslet behavior)
    expect(maybe.parse('')).to eq('')
  end

  it 'provides custom to_s_inner for debugging' do
    expect(atom.to_s).to include('test_custom')
    expect(atom.to_s).to include('hello')
  end
end
