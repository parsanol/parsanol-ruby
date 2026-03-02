# frozen_string_literal: true

require 'spec_helper'

# Test class that supports reset protocol
class TestPoolable
  attr_accessor :value

  def initialize
    @value = nil
  end

  def reset!
    @value = nil
  end
end

# Test class that does NOT support reset protocol
class TestNonResettable
  attr_accessor :value

  def initialize
    @value = nil
  end
end

# Test class that requires arguments (cannot be pre-allocated)
class TestWithArgs
  attr_accessor :value

  def initialize(value)
    @value = value
  end

  def reset!
    @value = nil
  end
end

describe Parsanol::ObjectPool do
  describe '#initialize' do
    it 'creates a pool with specified size' do
      pool = described_class.new(Array, size: 500)
      expect(pool.size).to eq(500)
    end

    it 'creates a pool with default size of 1000' do
      pool = described_class.new(Array)
      expect(pool.size).to eq(1000)
    end

    it 'pre-allocates objects when preallocate is true (default)' do
      pool = described_class.new(Array, size: 10, preallocate: true)
      stats = pool.statistics
      expect(stats[:available]).to eq(10)
      expect(stats[:released]).to eq(10)
    end

    it 'does not pre-allocate when preallocate is false' do
      pool = described_class.new(Array, size: 10, preallocate: false)
      stats = pool.statistics
      expect(stats[:available]).to eq(0)
      expect(stats[:released]).to eq(0)
    end

    it 'handles classes that require arguments gracefully' do
      # Should not raise error, just skip pre-allocation
      pool = described_class.new(TestWithArgs, size: 10, preallocate: true)
      stats = pool.statistics
      expect(stats[:available]).to eq(0)
    end
  end

  describe '#acquire' do
    context 'with empty pool' do
      it 'creates a new object' do
        pool = described_class.new(Array, size: 10, preallocate: false)
        obj = pool.acquire
        expect(obj).to be_a(Array)
      end

      it 'increments created counter' do
        pool = described_class.new(Array, size: 10, preallocate: false)
        pool.acquire
        stats = pool.statistics
        expect(stats[:created]).to eq(1)
      end

      it 'does not increment reused counter' do
        pool = described_class.new(Array, size: 10, preallocate: false)
        pool.acquire
        stats = pool.statistics
        expect(stats[:reused]).to eq(0)
      end
    end

    context 'with available objects' do
      it 'returns an object from the pool' do
        pool = described_class.new(Array, size: 10, preallocate: true)
        obj = pool.acquire
        expect(obj).to be_a(Array)
      end

      it 'increments reused counter' do
        pool = described_class.new(Array, size: 10, preallocate: true)
        pool.acquire
        stats = pool.statistics
        expect(stats[:reused]).to eq(1)
      end

      it 'does not increment created counter' do
        pool = described_class.new(Array, size: 10, preallocate: true)
        initial_created = pool.statistics[:created]
        pool.acquire
        stats = pool.statistics
        expect(stats[:created]).to eq(initial_created)
      end

      it 'decreases available count' do
        pool = described_class.new(Array, size: 10, preallocate: true)
        initial_available = pool.statistics[:available]
        pool.acquire
        stats = pool.statistics
        expect(stats[:available]).to eq(initial_available - 1)
      end
    end

    context 'multiple acquisitions' do
      it 'can acquire multiple objects' do
        pool = described_class.new(Array, size: 5, preallocate: true)
        objects = 3.times.map { pool.acquire }
        expect(objects.size).to eq(3)
        # With pre-allocation, objects come from the pool and are reused
        # So they will be different instances (different object_ids)
        expect(objects.map(&:object_id).uniq.size).to eq(3)
      end

      it 'creates new objects when pool is exhausted' do
        pool = described_class.new(Array, size: 2, preallocate: true)
        # Acquire all pre-allocated objects
        pool.acquire
        pool.acquire
        # This should create a new one
        obj = pool.acquire
        expect(obj).to be_a(Array)
        stats = pool.statistics
        expect(stats[:created]).to eq(1)
        expect(stats[:reused]).to eq(2)
      end
    end
  end

  describe '#release' do
    context 'with objects that support reset!' do
      it 'calls reset! on the object' do
        pool = described_class.new(TestPoolable, size: 10, preallocate: false)
        obj = pool.acquire
        obj.value = 'test'
        pool.release(obj)
        # Acquire the same object again
        reused = pool.acquire
        expect(reused.value).to be_nil
      end
    end

    context 'with objects that do not support reset!' do
      it 'pools the object without calling reset!' do
        pool = described_class.new(TestNonResettable, size: 10, preallocate: false)
        obj = pool.acquire
        obj.value = 'test'
        pool.release(obj)
        # Value should still be set (no reset called)
        reused = pool.acquire
        expect(reused.value).to eq('test')
      end
    end

    context 'pool capacity management' do
      it 'returns object to pool when under capacity' do
        pool = described_class.new(Array, size: 10, preallocate: false)
        obj = pool.acquire
        result = pool.release(obj)
        expect(result).to be true
        stats = pool.statistics
        expect(stats[:available]).to eq(1)
        expect(stats[:released]).to eq(1)
      end

      it 'discards object when pool is at capacity' do
        pool = described_class.new(Array, size: 2, preallocate: true)
        # Try to release one more than capacity
        obj = Array.new
        result = pool.release(obj)
        expect(result).to be false
        stats = pool.statistics
        expect(stats[:available]).to eq(2) # Still at capacity
        expect(stats[:discarded]).to eq(1)
      end

      it 'increments discarded counter when capacity exceeded' do
        pool = described_class.new(Array, size: 1, preallocate: true)
        obj1 = Array.new
        obj2 = Array.new
        pool.release(obj1)
        pool.release(obj2)
        stats = pool.statistics
        expect(stats[:discarded]).to eq(2)
      end
    end

    context 'statistics tracking' do
      it 'increments released counter' do
        pool = described_class.new(Array, size: 10, preallocate: false)
        obj = pool.acquire
        pool.release(obj)
        stats = pool.statistics
        expect(stats[:released]).to eq(1)
      end

      it 'tracks multiple releases' do
        pool = described_class.new(Array, size: 10, preallocate: false)
        3.times do
          obj = pool.acquire
          pool.release(obj)
        end
        stats = pool.statistics
        expect(stats[:released]).to eq(3)
      end
    end
  end

  describe '#statistics' do
    it 'returns hash with all statistics' do
      pool = described_class.new(Array, size: 10, preallocate: false)
      stats = pool.statistics
      expect(stats).to include(
        :size, :available, :created, :reused, :released, :discarded, :utilization
      )
    end

    it 'calculates utilization percentage correctly' do
      pool = described_class.new(Array, size: 10, preallocate: false)
      # Create 3 objects first (created=3)
      objs = 3.times.map { pool.acquire }
      # Release them back to pool
      objs.each { |obj| pool.release(obj) }
      # Acquire 5 more: 3 from pool (reused=3), 2 new (created=5 total)
      # Total acquires = 3 + 5 = 8, reused = 3, utilization = 3/8 = 37.5%
      5.times { pool.acquire }
      stats = pool.statistics
      expect(stats[:utilization]).to eq(37.5)
    end

    it 'handles zero acquires without division by zero' do
      pool = described_class.new(Array, size: 10, preallocate: false)
      stats = pool.statistics
      expect(stats[:utilization]).to eq(0.0)
    end

    it 'tracks available count correctly' do
      pool = described_class.new(Array, size: 10, preallocate: true)
      pool.acquire
      pool.acquire
      stats = pool.statistics
      expect(stats[:available]).to eq(8)
    end
  end

  describe '#clear!' do
    it 'removes all objects from pool' do
      pool = described_class.new(Array, size: 10, preallocate: true)
      pool.clear!
      stats = pool.statistics
      expect(stats[:available]).to eq(0)
    end

    it 'resets all statistics' do
      pool = described_class.new(Array, size: 10, preallocate: true)
      3.times { pool.acquire }
      pool.clear!
      stats = pool.statistics
      expect(stats[:created]).to eq(0)
      expect(stats[:reused]).to eq(0)
      expect(stats[:released]).to eq(0)
      expect(stats[:discarded]).to eq(0)
    end
  end

  describe 'object reuse cycle' do
    it 'successfully reuses objects through multiple cycles' do
      pool = described_class.new(TestPoolable, size: 5, preallocate: false)

      # Cycle 1: Acquire and release
      obj1 = pool.acquire
      obj1.value = 'cycle1'
      pool.release(obj1)

      # Cycle 2: Reuse same object
      obj2 = pool.acquire
      expect(obj2.value).to be_nil # Should be reset
      obj2.value = 'cycle2'
      pool.release(obj2)

      # Cycle 3: Reuse again
      obj3 = pool.acquire
      expect(obj3.value).to be_nil # Should be reset again

      # All cycles should use the same object
      expect(obj1.object_id).to eq(obj2.object_id)
      expect(obj2.object_id).to eq(obj3.object_id)
    end

    it 'maintains object count correctly through cycles' do
      pool = described_class.new(Array, size: 3, preallocate: false)

      # Create 3 objects
      obj1 = pool.acquire
      obj2 = pool.acquire
      obj3 = pool.acquire

      # Release all
      pool.release(obj1)
      pool.release(obj2)
      pool.release(obj3)

      stats = pool.statistics
      expect(stats[:available]).to eq(3)
      expect(stats[:created]).to eq(3)

      # Reuse all 3
      pool.acquire
      pool.acquire
      pool.acquire

      stats = pool.statistics
      expect(stats[:available]).to eq(0)
      expect(stats[:reused]).to eq(3)
      expect(stats[:created]).to eq(3) # No new creations
    end
  end

  describe 'edge cases' do
    it 'handles pool size of 0 gracefully' do
      pool = described_class.new(Array, size: 0, preallocate: false)
      obj = pool.acquire
      result = pool.release(obj)
      expect(result).to be false # Always discarded
      expect(pool.statistics[:discarded]).to eq(1)
    end

    it 'handles pool size of 1' do
      pool = described_class.new(Array, size: 1, preallocate: true)
      obj = pool.acquire
      expect(pool.statistics[:available]).to eq(0)
      pool.release(obj)
      expect(pool.statistics[:available]).to eq(1)
    end

    it 'handles large pool sizes' do
      pool = described_class.new(Array, size: 10000, preallocate: true)
      expect(pool.statistics[:available]).to eq(10000)
    end
  end

  describe 'pool overhead' do
    it 'has minimal overhead for acquire operations' do
      pool = described_class.new(Array, size: 1000, preallocate: true)

      # Measure 1000 acquires from pre-allocated pool
      start_time = Time.now
      1000.times { pool.acquire }
      elapsed = Time.now - start_time

      # Pool acquires should be very fast (< 10ms for 1000 operations)
      # This validates that pool overhead is minimal
      expect(elapsed).to be < 0.01
    end

    it 'has minimal overhead for release operations' do
      pool = described_class.new(TestPoolable, size: 1000, preallocate: false)
      objects = 100.times.map { pool.acquire }

      # Measure 100 releases with reset
      start_time = Time.now
      objects.each { |obj| pool.release(obj) }
      elapsed = Time.now - start_time

      # Releases with reset should be fast (< 10ms for 100 operations)
      expect(elapsed).to be < 0.01
    end
  end
end