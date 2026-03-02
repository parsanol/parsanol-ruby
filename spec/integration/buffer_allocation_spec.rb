# frozen_string_literal: true

require 'spec_helper'
require 'parsanol/parslet'

# Integration tests for Phase 2.1: Fixed-Size Buffer Pre-allocation
# Verifies that BufferPool is properly integrated into Context and accessible
describe 'Buffer Allocation Integration' do
  describe 'Context integration' do
    it 'has a buffer_pool' do
      context = Parsanol::Atoms::Context.new
      expect(context.buffer_pool).to be_a(Parsanol::Pools::BufferPool)
    end

    it 'provides acquire_buffer helper' do
      context = Parsanol::Atoms::Context.new
      buffer = context.acquire_buffer(size: 8)

      expect(buffer).to be_a(Parsanol::Buffer)
      expect(buffer.capacity).to be >= 8
      expect(buffer).to be_empty
    end

    it 'provides release_buffer helper' do
      context = Parsanol::Atoms::Context.new
      buffer = context.acquire_buffer(size: 8)
      buffer.push('a')
      buffer.push('b')

      result = context.release_buffer(buffer)
      expect(result).to be true
    end

    it 'clears buffers on release' do
      context = Parsanol::Atoms::Context.new

      # Acquire and use buffer
      buffer = context.acquire_buffer(size: 4)
      buffer.push('a')
      buffer.push('b')
      buffer.push('c')
      context.release_buffer(buffer)

      # Next acquisition should get a cleared buffer
      buffer2 = context.acquire_buffer(size: 4)
      expect(buffer2).to be_empty
      expect(buffer2.size).to eq(0)
    end

    it 'reuses buffers across acquire/release cycles' do
      context = Parsanol::Atoms::Context.new

      # First cycle
      buffer1 = context.acquire_buffer(size: 8)
      buffer1_id = buffer1.object_id
      context.release_buffer(buffer1)

      # Second cycle - should reuse same buffer
      buffer2 = context.acquire_buffer(size: 8)
      expect(buffer2.object_id).to eq(buffer1_id)
    end
  end

  describe 'Buffer size class selection' do
    let(:context) { Parsanol::Atoms::Context.new }

    it 'selects appropriate size classes' do
      test_cases = [
        [2, 2],
        [3, 4],
        [5, 8],
        [10, 16],
        [20, 32],
        [50, 64]
      ]

      test_cases.each do |requested, expected|
        buffer = context.acquire_buffer(size: requested)
        expect(buffer.capacity).to eq(expected),
                                   "size #{requested} should get capacity #{expected}, got #{buffer.capacity}"
        context.release_buffer(buffer)
      end
    end

    it 'handles standard size classes' do
      Parsanol::Pools::BufferPool::SIZE_CLASSES.each do |size|
        buffer = context.acquire_buffer(size: size)
        expect(buffer.capacity).to eq(size)
        context.release_buffer(buffer)
      end
    end
  end

  describe 'Buffer pool statistics' do
    it 'tracks buffer creation and reuse' do
      context = Parsanol::Atoms::Context.new
      pool = context.buffer_pool

      # First acquire - creates new buffer
      buffer1 = context.acquire_buffer(size: 8)
      context.release_buffer(buffer1)

      # Second acquire - reuses buffer
      buffer2 = context.acquire_buffer(size: 8)
      context.release_buffer(buffer2)

      # Check statistics
      stats = pool.statistics
      expect(stats).to be_a(Hash)
      expect(stats[8]).to include(
        :created,
        :reused,
        :released,
        :utilization
      )

      expect(stats[8][:created]).to eq(1)
      expect(stats[8][:reused]).to eq(1)
      expect(stats[8][:utilization]).to be > 0
    end

    it 'tracks statistics per size class' do
      context = Parsanol::Atoms::Context.new
      pool = context.buffer_pool

      # Use different size classes
      buffer2 = context.acquire_buffer(size: 2)
      buffer4 = context.acquire_buffer(size: 4)
      buffer8 = context.acquire_buffer(size: 8)

      context.release_buffer(buffer2)
      context.release_buffer(buffer4)
      context.release_buffer(buffer8)

      stats = pool.statistics
      expect(stats[2][:created]).to eq(1)
      expect(stats[4][:created]).to eq(1)
      expect(stats[8][:created]).to eq(1)
    end
  end

  describe 'Buffer lifecycle' do
    it 'maintains buffer capacity across reuse' do
      context = Parsanol::Atoms::Context.new

      # Create buffer with capacity 8
      buffer = context.acquire_buffer(size: 8)
      expect(buffer.capacity).to eq(8)

      # Fill it
      8.times { |i| buffer.push(i) }
      expect(buffer.size).to eq(8)

      # Release and reacquire
      context.release_buffer(buffer)
      buffer2 = context.acquire_buffer(size: 8)

      # Capacity should be preserved, size reset
      expect(buffer2.capacity).to eq(8)
      expect(buffer2.size).to eq(0)
    end

    it 'handles buffer growth gracefully' do
      context = Parsanol::Atoms::Context.new

      # Acquire small buffer
      buffer = context.acquire_buffer(size: 4)
      expect(buffer.capacity).to eq(4)

      # Grow beyond capacity
      10.times { |i| buffer.push(i) }
      expect(buffer.size).to eq(10)
      expect(buffer.capacity).to be > 4

      # Verify contents
      expect(buffer.to_a).to eq((0..9).to_a)
    end
  end

  describe 'Multiple contexts' do
    it 'each context has independent buffer pool' do
      context1 = Parsanol::Atoms::Context.new
      context2 = Parsanol::Atoms::Context.new

      pool1 = context1.buffer_pool
      pool2 = context2.buffer_pool

      expect(pool1.object_id).not_to eq(pool2.object_id)

      # Activity in one doesn't affect the other
      buffer1 = context1.acquire_buffer(size: 8)
      context1.release_buffer(buffer1)

      stats1 = pool1.statistics[8]
      stats2 = pool2.statistics[8]

      expect(stats1[:created]).to eq(1)
      expect(stats2[:created]).to eq(0)
    end
  end

  describe 'Buffer operations' do
    let(:context) { Parsanol::Atoms::Context.new }

    it 'supports push operations' do
      buffer = context.acquire_buffer(size: 4)

      buffer.push('a')
      buffer.push('b')

      expect(buffer.size).to eq(2)
      expect(buffer.to_a).to eq(%w[a b])

      context.release_buffer(buffer)
    end

    it 'supports array conversion' do
      buffer = context.acquire_buffer(size: 8)

      elements = %w[x y z]
      elements.each { |e| buffer.push(e) }

      result = buffer.to_a
      expect(result).to eq(elements)
      expect(result).to be_a(Array)

      context.release_buffer(buffer)
    end

    it 'supports indexing' do
      buffer = context.acquire_buffer(size: 8)

      buffer.push('a')
      buffer.push('b')
      buffer.push('c')

      expect(buffer[0]).to eq('a')
      expect(buffer[1]).to eq('b')
      expect(buffer[2]).to eq('c')

      buffer[1] = 'x'
      expect(buffer[1]).to eq('x')

      context.release_buffer(buffer)
    end

    it 'supports empty? check' do
      buffer = context.acquire_buffer(size: 4)

      expect(buffer.empty?).to be true

      buffer.push('a')
      expect(buffer.empty?).to be false

      buffer.clear!
      expect(buffer.empty?).to be true

      context.release_buffer(buffer)
    end
  end

  describe 'Pool capacity management' do
    it 'handles pool overflow gracefully' do
      context = Parsanol::Atoms::Context.new
      pool = context.buffer_pool

      # NOTE: BufferPool has pool_size of 100 by default
      # We'll just verify the pool can handle multiple buffer cycles

      10.times do
        buffer = context.acquire_buffer(size: 8)
        buffer.push('data')
        context.release_buffer(buffer)
      end

      stats = pool.statistics[8]
      expect(stats[:released]).to be >= 10
    end
  end

  describe 'Performance characteristics' do
    it 'buffer reuse reduces allocations' do
      context = Parsanol::Atoms::Context.new
      pool = context.buffer_pool

      # Clear statistics
      pool.clear!

      # Perform multiple acquire/release cycles
      cycles = 20
      cycles.times do
        buffer = context.acquire_buffer(size: 8)
        buffer.push('x')
        context.release_buffer(buffer)
      end

      stats = pool.statistics[8]

      # Should have high reuse rate
      # First acquire creates, rest reuse
      expect(stats[:created]).to be <= 2
      expect(stats[:reused]).to be >= (cycles - 2)
      expect(stats[:utilization]).to be > 80.0
    end
  end

  describe 'Context pool coexistence' do
    it 'buffer_pool works alongside array_pool' do
      context = Parsanol::Atoms::Context.new

      # Both pools should exist
      expect(context.array_pool).to be_a(Parsanol::Pools::ArrayPool)
      expect(context.buffer_pool).to be_a(Parsanol::Pools::BufferPool)

      # Both should be functional
      array = context.acquire_array
      buffer = context.acquire_buffer(size: 4)

      expect(array).to be_a(Array)
      expect(buffer).to be_a(Parsanol::Buffer)

      context.release_array(array)
      context.release_buffer(buffer)
    end
  end
end
