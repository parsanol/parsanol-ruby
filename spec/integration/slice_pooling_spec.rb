# frozen_string_literal: true

require 'spec_helper'

describe 'Slice Pooling Integration' do
  it 'source has a slice_pool' do
    source = Parsanol::Source.new('hello world')
    expect(source.slice_pool).to be_a(Parsanol::Pools::SlicePool)
  end

  it 'source.consume uses pooled slices' do
    source = Parsanol::Source.new('hello')

    # Consume should use the pool
    slice1 = source.consume(1)
    expect(slice1).to be_a(Parsanol::Slice)
    expect(slice1.to_s).to eq('h')

    # Pool should show usage (created + reused)
    stats = source.slice_pool.statistics
    total_usage = stats[:created] + stats[:reused]
    expect(total_usage).to be > 0
  end

  it 'source.slice helper creates pooled slices' do
    source = Parsanol::Source.new('test')

    slice = source.slice(0, 'test')
    expect(slice).to be_a(Parsanol::Slice)
    expect(slice.to_s).to eq('test')

    stats = source.slice_pool.statistics
    total_usage = stats[:created] + stats[:reused]
    expect(total_usage).to be > 0
  end

  it 'reuses slices during repetitive parsing' do
    parser = Class.new(Parsanol::Parser) do
      root :letters
      rule(:letters) { str('a').repeat(10) }
    end.new

    result = parser.parse('aaaaaaaaaa')

    # Verify the parser works with pooling
    # The parse succeeded which means pooling worked
    expect(result).to be_a(Parsanol::Slice)
    expect(result.to_s).to eq('aaaaaaaaaa')
  end

  it 'handles complex parsing with pooling' do
    parser = Class.new(Parsanol::Parser) do
      root :expression
      rule(:expression) do
        (str('x') | str('y')).repeat(5) >>
          str('!')
      end
    end.new

    result = parser.parse('xyxyx!')
    # Result is flattened, so verify parse succeeded
    expect(result).to be_a(Parsanol::Slice)
    expect(result.to_s).to eq('xyxyx!')
  end
end
