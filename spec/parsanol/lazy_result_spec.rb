# frozen_string_literal: true

require 'spec_helper'

describe Parsanol::LazyResult do
  let(:context) { Parsanol::Atoms::Context.new }
  let(:buffer) do
    buf = context.acquire_buffer(size: 4)
    buf.push('a')
    buf.push('b')
    buf.push('c')
    buf
  end
  let(:lazy) { described_class.new(buffer, context) }

  describe '#initialize' do
    it 'stores buffer and context' do
      expect(lazy.buffer).to eq(buffer)
      expect(lazy.context).to eq(context)
      expect(lazy.materialized).to be_nil
    end
  end

  describe '#to_a' do
    it 'materializes buffer to array' do
      result = lazy.to_a
      expect(result).to be_a(Array)
      expect(result).to eq(%w[a b c])
    end

    it 'caches materialized array' do
      arr1 = lazy.to_a
      arr2 = lazy.to_a
      expect(arr2.object_id).to eq(arr1.object_id)
    end

    it 'only materializes once' do
      expect(buffer).to receive(:to_a).once.and_call_original
      lazy.to_a
      lazy.to_a
      lazy.to_a
    end
  end

  describe '#[]' do
    it 'accesses elements by index' do
      expect(lazy[0]).to eq('a')
      expect(lazy[1]).to eq('b')
      expect(lazy[2]).to eq('c')
    end

    it 'materializes on first access' do
      expect(lazy.materialized).to be_nil
      lazy[0]
      expect(lazy.materialized).not_to be_nil
    end

    it 'returns nil for out of bounds index' do
      expect(lazy[10]).to be_nil
    end
  end

  describe '#size' do
    it 'returns buffer size without materializing' do
      expect(lazy.size).to eq(3)
      expect(lazy.materialized).to be_nil
    end
  end

  describe '#length' do
    it 'returns buffer size without materializing' do
      expect(lazy.length).to eq(3)
      expect(lazy.materialized).to be_nil
    end
  end

  describe '#empty?' do
    it 'returns false for non-empty buffer' do
      expect(lazy.empty?).to be false
      expect(lazy.materialized).to be_nil
    end

    it 'returns true for empty buffer' do
      empty_buffer = context.acquire_buffer(size: 2)
      empty_lazy = described_class.new(empty_buffer, context)
      expect(empty_lazy.empty?).to be true
    end
  end

  describe '#each' do
    it 'iterates over elements' do
      result = lazy.map { |e| e }
      expect(result).to eq(%w[a b c])
    end

    it 'returns enumerator without block' do
      enum = lazy.each
      expect(enum).to be_a(Enumerator)
      expect(enum.to_a).to eq(%w[a b c])
    end

    it 'returns self when block given' do
      result = lazy.each { |e| }
      expect(result).to eq(lazy)
    end
  end

  describe '#is_a?' do
    it 'reports as Array' do
      expect(lazy.is_a?(Array)).to be true
    end

    it 'reports as LazyResult' do
      expect(lazy.is_a?(Parsanol::LazyResult)).to be true
    end

    it 'reports as Object' do
      expect(lazy.is_a?(Object)).to be true
    end
  end

  describe '#kind_of?' do
    it 'is an alias for is_a?' do
      expect(lazy.is_a?(Array)).to be true
      expect(lazy.is_a?(Parsanol::LazyResult)).to be true
    end
  end

  describe '#respond_to?' do
    it 'responds to array methods' do
      expect(lazy.respond_to?(:map)).to be true
      expect(lazy.respond_to?(:select)).to be true
      expect(lazy.respond_to?(:first)).to be true
      expect(lazy.respond_to?(:last)).to be true
    end

    it 'responds to LazyResult methods' do
      expect(lazy.respond_to?(:to_a)).to be true
      expect(lazy.respond_to?(:size)).to be true
      expect(lazy.respond_to?(:empty?)).to be true
    end
  end

  describe '#method_missing' do
    it 'delegates map to materialized array' do
      expect(lazy.map(&:upcase)).to eq(%w[A B C])
    end

    it 'delegates select to materialized array' do
      expect(lazy.select { |e| e > 'a' }).to eq(%w[b c])
    end

    it 'delegates first to materialized array' do
      expect(lazy.first).to eq('a')
    end

    it 'delegates last to materialized array' do
      expect(lazy.last).to eq('c')
    end

    it 'delegates join to materialized array' do
      expect(lazy.join(', ')).to eq('a, b, c')
    end

    it 'raises NoMethodError for unknown methods' do
      expect { lazy.unknown_method }.to raise_error(NoMethodError)
    end
  end

  describe '#respond_to_missing?' do
    it 'returns true for array methods' do
      expect(lazy.respond_to?(:map)).to be true
      expect(lazy.respond_to?(:flatten)).to be true
    end

    it 'returns false for non-existent methods' do
      expect(lazy.respond_to?(:nonexistent_method)).to be false
    end
  end

  describe '#==' do
    it 'compares equal to array with same content' do
      expect(lazy == %w[a b c]).to be true
      expect(lazy).to eq(%w[a b c])
    end

    it 'compares not equal to array with different content' do
      expect(lazy == %w[x y z]).to be false
      expect(lazy).not_to eq(%w[x y z])
    end

    it 'compares equal to another LazyResult with same content' do
      buffer2 = context.acquire_buffer(size: 4)
      buffer2.push('a')
      buffer2.push('b')
      buffer2.push('c')
      lazy2 = described_class.new(buffer2, context)

      expect(lazy == lazy2).to be true
      expect(lazy).to eq(lazy2)
    end

    it 'works with rspec eq matcher' do
      expect(lazy).to eq(%w[a b c])
    end
  end

  describe '#eql?' do
    it 'is an alias for ==' do
      expect(lazy.eql?(%w[a b c])).to be true
    end
  end

  describe '#hash' do
    it 'returns same hash as equivalent array' do
      array = %w[a b c]
      expect(lazy.hash).to eq(array.hash)
    end
  end

  describe 'materialization behavior' do
    it 'defers materialization until needed' do
      new_lazy = described_class.new(buffer, context)
      expect(new_lazy.materialized).to be_nil

      # These don't materialize
      new_lazy.size
      new_lazy.empty?
      new_lazy.length
      expect(new_lazy.materialized).to be_nil

      # This does materialize
      new_lazy.to_a
      expect(new_lazy.materialized).not_to be_nil
    end

    it 'materializes on array method calls' do
      new_lazy = described_class.new(buffer, context)
      expect(new_lazy.materialized).to be_nil

      # Array access materializes
      new_lazy[0]
      expect(new_lazy.materialized).not_to be_nil
    end

    it 'materializes on enumerable methods' do
      new_lazy = described_class.new(buffer, context)
      expect(new_lazy.materialized).to be_nil

      # map materializes
      new_lazy.map { |x| x }
      expect(new_lazy.materialized).not_to be_nil
    end
  end

  describe '#inspect' do
    it 'shows buffer size when not materialized' do
      new_lazy = described_class.new(buffer, context)
      expect(new_lazy.inspect).to include('buffer.size=3')
      expect(new_lazy.inspect).not_to include('materialized=')
    end

    it 'shows materialized array after materialization' do
      lazy.to_a
      expect(lazy.inspect).to include('materialized=')
      expect(lazy.inspect).to include('["a", "b", "c"]')
    end
  end

  describe 'integration with parsing' do
    it 'can be used in place of arrays' do
      # LazyResult should act like an array in all contexts
      result_array = lazy.to_a
      expect(lazy.size).to eq(result_array.size)
      expect(lazy.first).to eq(result_array.first)
      expect(lazy.last).to eq(result_array.last)
      expect(lazy.empty?).to eq(result_array.empty?)
    end

    it 'supports array destructuring' do
      a, b, c = lazy
      expect(a).to eq('a')
      expect(b).to eq('b')
      expect(c).to eq('c')
    end
  end
end
