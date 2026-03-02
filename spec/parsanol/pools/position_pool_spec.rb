# frozen_string_literal: true

require 'spec_helper'

describe Parsanol::Pools::PositionPool do
  let(:pool) { described_class.new(size: 10) }

  describe '#initialize' do
    it 'creates a PositionPool' do
      expect(pool).to be_a(Parsanol::Pools::PositionPool)
    end

    it 'inherits from ObjectPool' do
      expect(pool).to be_a(Parsanol::ObjectPool)
    end
  end

  describe '#acquire_with' do
    it 'returns a Position with specified values' do
      pos = pool.acquire_with(string: 'test', bytepos: 42, charpos: 42)
      expect(pos).to be_a(Parsanol::Position)
      expect(pos.bytepos).to eq(42)
      expect(pos.charpos).to eq(42)
    end

    it 'works without charpos' do
      pos = pool.acquire_with(string: 'test', bytepos: 10)
      expect(pos).to be_a(Parsanol::Position)
      expect(pos.bytepos).to eq(10)
    end
  end

  describe '#release' do
    it 'resets position before returning to pool' do
      pos = pool.acquire_with(string: 'test', bytepos: 42, charpos: 42)
      pool.release(pos)

      # Next acquire should get a fresh position that can be reinitialized
      pos2 = pool.acquire_with(string: 'new', bytepos: 1, charpos: 1)
      expect(pos2.bytepos).to eq(1)
      expect(pos2.charpos).to eq(1)
    end

    it 'returns true if returned to pool' do
      pos = pool.acquire_with(string: 'test', bytepos: 0, charpos: 0)
      expect(pool.release(pos)).to eq(true)
    end

    it 'returns false if pool is full' do
      # Fill the pool to capacity
      positions = 10.times.map { pool.acquire_with(string: 'test', bytepos: 0) }
      positions.each { |p| pool.release(p) }

      # Create a new position outside the pool
      external_pos = Parsanol::Position.new('external', 99, 99)

      # Try to release it - should be rejected since pool is full
      expect(pool.release(external_pos)).to eq(false)
    end
  end

  describe 'reuse' do
    it 'reuses positions from the pool' do
      pos1 = pool.acquire_with(string: 'test1', bytepos: 1, charpos: 1)
      pool.release(pos1)

      pos2 = pool.acquire_with(string: 'test2', bytepos: 2, charpos: 2)

      # Should reuse the same object
      expect(pos2.object_id).to eq(pos1.object_id)
      # But with new values
      expect(pos2.bytepos).to eq(2)
      expect(pos2.charpos).to eq(2)
    end

    it 'tracks reuse statistics' do
      # Acquire and release to populate pool
      pos1 = pool.acquire_with(string: 'test', bytepos: 0)
      pool.release(pos1)

      # Acquire again - should be reused
      pool.acquire_with(string: 'test', bytepos: 0)

      stats = pool.statistics
      expect(stats[:reused]).to eq(1)
      expect(stats[:created]).to eq(1)
    end
  end

  describe '#statistics' do
    it 'provides utilization percentage' do
      # Create one position
      pos = pool.acquire_with(string: 'test', bytepos: 0)
      pool.release(pos)

      # Reuse it
      pool.acquire_with(string: 'test', bytepos: 0)

      stats = pool.statistics
      expect(stats[:utilization]).to eq(50.0) # 1 reused out of 2 total acquires
    end

    it 'tracks created, reused, released, and discarded counts' do
      pos1 = pool.acquire_with(string: 'test', bytepos: 0)
      pos2 = pool.acquire_with(string: 'test', bytepos: 0)

      pool.release(pos1)
      pool.release(pos2)

      pool.acquire_with(string: 'test', bytepos: 0)

      stats = pool.statistics
      expect(stats[:created]).to eq(2)
      expect(stats[:reused]).to eq(1)
      expect(stats[:released]).to eq(2)
    end
  end
end
