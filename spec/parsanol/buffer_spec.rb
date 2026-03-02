# frozen_string_literal: true

require 'spec_helper'

describe Parsanol::Buffer do
  let(:buffer) { described_class.new(capacity: 10) }

  describe '#initialize' do
    it 'creates buffer with specified capacity' do
      expect(buffer.capacity).to eq(10)
      expect(buffer.size).to eq(0)
      expect(buffer.storage).to be_a(Array)
    end

    it 'uses default capacity if not specified' do
      default_buffer = described_class.new
      expect(default_buffer.capacity).to eq(10)
    end
  end

  describe '#push' do
    it 'adds elements to buffer' do
      buffer.push('a')
      buffer.push('b')

      expect(buffer.size).to eq(2)
      expect(buffer[0]).to eq('a')
      expect(buffer[1]).to eq('b')
    end

    it 'returns self for method chaining' do
      result = buffer.push('a')
      expect(result).to eq(buffer)
    end

    it 'grows buffer when capacity is exceeded' do
      original_capacity = buffer.capacity

      # Fill to capacity
      (original_capacity + 1).times { |i| buffer.push(i) }

      expect(buffer.size).to eq(original_capacity + 1)
      expect(buffer.capacity).to be > original_capacity
    end

    it 'preserves all elements when growing' do
      11.times { |i| buffer.push(i) }

      arr = buffer.to_a
      expect(arr.size).to eq(11)
      expect(arr).to eq((0..10).to_a)
    end
  end

  describe '#<<' do
    it 'is an alias for push' do
      buffer << 'a' << 'b'

      expect(buffer.size).to eq(2)
      expect(buffer.to_a).to eq(%w[a b])
    end
  end

  describe '#[]' do
    before do
      buffer.push('a')
      buffer.push('b')
      buffer.push('c')
    end

    it 'returns element at index' do
      expect(buffer[0]).to eq('a')
      expect(buffer[1]).to eq('b')
      expect(buffer[2]).to eq('c')
    end

    it 'returns nil for out of bounds index' do
      expect(buffer[3]).to be_nil
      expect(buffer[100]).to be_nil
    end
  end

  describe '#[]=' do
    before do
      buffer.push('a')
      buffer.push('b')
      buffer.push('c')
    end

    it 'sets element at index' do
      buffer[1] = 'x'
      expect(buffer[1]).to eq('x')
      expect(buffer.to_a).to eq(%w[a x c])
    end

    it 'does not set element beyond size' do
      buffer[10] = 'x'
      expect(buffer.size).to eq(3)
    end
  end

  describe '#to_a' do
    it 'returns array of logical size' do
      buffer.push('a')
      buffer.push('b')
      buffer.push('c')

      arr = buffer.to_a
      expect(arr).to be_a(Array)
      expect(arr.size).to eq(3)
      expect(arr).to eq(%w[a b c])
    end

    it 'returns empty array for empty buffer' do
      expect(buffer.to_a).to eq([])
    end

    it 'returns new array instance' do
      buffer.push('a')
      arr1 = buffer.to_a
      arr2 = buffer.to_a

      expect(arr1.object_id).not_to eq(arr2.object_id)
    end
  end

  describe '#clear!' do
    before do
      buffer.push('a')
      buffer.push('b')
      buffer.push('c')
    end

    it 'resets size to zero' do
      buffer.clear!
      expect(buffer.size).to eq(0)
    end

    it 'keeps capacity unchanged' do
      original_capacity = buffer.capacity
      buffer.clear!
      expect(buffer.capacity).to eq(original_capacity)
    end

    it 'clears references for GC' do
      buffer.clear!
      expect(buffer.to_a).to eq([])
    end

    it 'returns self for method chaining' do
      result = buffer.clear!
      expect(result).to eq(buffer)
    end

    it 'allows reuse after clear' do
      buffer.clear!
      buffer.push('x')
      buffer.push('y')

      expect(buffer.size).to eq(2)
      expect(buffer.to_a).to eq(%w[x y])
    end
  end

  describe '#empty?' do
    it 'returns true for new buffer' do
      expect(buffer.empty?).to be true
    end

    it 'returns false after adding elements' do
      buffer.push('a')
      expect(buffer.empty?).to be false
    end

    it 'returns true after clear' do
      buffer.push('a')
      buffer.clear!
      expect(buffer.empty?).to be true
    end
  end

  describe '#reset!' do
    it 'is an alias for clear!' do
      buffer.push('a')
      buffer.push('b')

      buffer.reset!

      expect(buffer.size).to eq(0)
      expect(buffer.empty?).to be true
    end
  end

  describe 'buffer reuse' do
    it 'efficiently reuses buffer without reallocation' do
      # First use
      5.times { |i| buffer.push(i) }
      expect(buffer.size).to eq(5)
      original_capacity = buffer.capacity

      # Clear and reuse
      buffer.clear!
      5.times { |i| buffer.push(i + 10) }

      expect(buffer.size).to eq(5)
      expect(buffer.capacity).to eq(original_capacity)
      expect(buffer.to_a).to eq([10, 11, 12, 13, 14])
    end
  end

  describe 'growth strategy' do
    it 'doubles capacity when growing' do
      small_buffer = described_class.new(capacity: 4)

      # Fill to capacity
      5.times { |i| small_buffer.push(i) }

      expect(small_buffer.capacity).to eq(8) # 4 * 2
    end
  end
end
