require 'spec_helper'
require 'parsanol/interval_tree'

describe Parsanol::IntervalTree do
  let(:tree) { Parsanol::IntervalTree.new }

  describe '#initialize' do
    it 'creates an empty tree' do
      expect(tree.empty?).to be true
      expect(tree.size).to eq 0
    end
  end

  describe '#insert and #query_exact' do
    it 'inserts and retrieves a single interval' do
      tree.insert(0, 10, 'data1')
      expect(tree.size).to eq 1
      expect(tree.query_exact(0, 10)).to eq 'data1'
    end

    it 'returns nil for non-existent intervals' do
      tree.insert(0, 10, 'data1')
      expect(tree.query_exact(0, 5)).to be_nil
      expect(tree.query_exact(5, 10)).to be_nil
    end

    it 'handles multiple insertions' do
      tree.insert(0, 10, 'data1')
      tree.insert(20, 30, 'data2')
      tree.insert(10, 20, 'data3')

      expect(tree.size).to eq 3
      expect(tree.query_exact(0, 10)).to eq 'data1'
      expect(tree.query_exact(20, 30)).to eq 'data2'
      expect(tree.query_exact(10, 20)).to eq 'data3'
    end
  end

  describe '#query_overlapping' do
    before do
      # Create intervals: [0,10), [5,15), [20,30), [25,35)
      tree.insert(0, 10, 'interval1')
      tree.insert(5, 15, 'interval2')
      tree.insert(20, 30, 'interval3')
      tree.insert(25, 35, 'interval4')
    end

    it 'finds intervals that overlap with query range' do
      # Query [0,5) should overlap with [0,10)
      results = tree.query_overlapping(0, 5)
      expect(results).to include('interval1')
      expect(results.size).to eq 1
    end

    it 'finds multiple overlapping intervals' do
      # Query [7,12) should overlap with [0,10) and [5,15)
      results = tree.query_overlapping(7, 12)
      expect(results).to include('interval1', 'interval2')
      expect(results.size).to eq 2
    end

    it 'returns empty array when no overlaps' do
      # Query [15,20) should have no overlaps
      results = tree.query_overlapping(15, 20)
      expect(results).to be_empty
    end

    it 'finds overlaps at boundaries' do
      # Query [22,28) should overlap with [20,30) and [25,35)
      results = tree.query_overlapping(22, 28)
      expect(results).to include('interval3', 'interval4')
      expect(results.size).to eq 2
    end

    it 'handles query that encompasses multiple intervals' do
      # Query [0,40) should overlap with all intervals
      results = tree.query_overlapping(0, 40)
      expect(results.size).to eq 4
    end

    it 'handles point queries (zero-length intervals)' do
      # Query [8,8) is empty, should have no overlaps
      results = tree.query_overlapping(8, 8)
      expect(results).to be_empty
    end
  end

  describe '#delete_overlapping' do
    before do
      tree.insert(0, 10, 'interval1')
      tree.insert(5, 15, 'interval2')
      tree.insert(20, 30, 'interval3')
      tree.insert(25, 35, 'interval4')
    end

    it 'deletes overlapping intervals' do
      # Delete intervals overlapping with [7,12)
      deleted = tree.delete_overlapping(7, 12)

      expect(deleted).to include('interval1', 'interval2')
      expect(deleted.size).to eq 2
      expect(tree.size).to eq 2

      # Verify they're actually deleted
      expect(tree.query_exact(0, 10)).to be_nil
      expect(tree.query_exact(5, 15)).to be_nil

      # Verify others remain
      expect(tree.query_exact(20, 30)).to eq 'interval3'
      expect(tree.query_exact(25, 35)).to eq 'interval4'
    end

    it 'returns empty array when no overlaps to delete' do
      deleted = tree.delete_overlapping(15, 20)
      expect(deleted).to be_empty
      expect(tree.size).to eq 4
    end

    it 'can delete all intervals' do
      deleted = tree.delete_overlapping(0, 40)
      expect(deleted.size).to eq 4
      expect(tree.empty?).to be true
    end
  end

  describe '#clear' do
    it 'removes all intervals' do
      tree.insert(0, 10, 'data1')
      tree.insert(20, 30, 'data2')

      tree.clear

      expect(tree.empty?).to be true
      expect(tree.size).to eq 0
      expect(tree.query_exact(0, 10)).to be_nil
    end
  end

  describe 'complex scenarios' do
    it 'handles many intervals efficiently' do
      # Insert 100 intervals
      100.times do |i|
        tree.insert(i * 10, i * 10 + 15, "data#{i}")
      end

      expect(tree.size).to eq 100

      # Query should find overlapping intervals efficiently
      results = tree.query_overlapping(50, 65)
      expect(results.size).to be > 0
    end

    it 'handles overlapping insertions correctly' do
      tree.insert(0, 100, 'big')
      tree.insert(10, 20, 'small1')
      tree.insert(30, 40, 'small2')
      tree.insert(50, 60, 'small3')

      # Query in middle should find big + one small
      results = tree.query_overlapping(15, 25)
      expect(results).to include('big', 'small1')
      expect(results.size).to eq 2
    end

    it 'maintains correctness after deletions' do
      # Insert intervals
      tree.insert(0, 10, 'a')
      tree.insert(20, 30, 'b')
      tree.insert(40, 50, 'c')
      tree.insert(60, 70, 'd')

      # Delete middle range - should delete b and c
      deleted = tree.delete_overlapping(15, 55)

      # Should have deleted b and c
      expect(deleted).to include('b', 'c')
      expect(deleted.size).to eq 2
      expect(tree.query_exact(20, 30)).to be_nil
      expect(tree.query_exact(40, 50)).to be_nil

      # Should still have a and d
      expect(tree.query_exact(0, 10)).to eq 'a'
      expect(tree.query_exact(60, 70)).to eq 'd'
    end
  end

  describe 'edge cases' do
    it 'handles zero-length intervals' do
      tree.insert(10, 10, 'zero-length')
      expect(tree.size).to eq 1
      expect(tree.query_exact(10, 10)).to eq 'zero-length'
    end

    it 'handles large position values' do
      large_pos = 1_000_000
      tree.insert(large_pos, large_pos + 100, 'large')
      expect(tree.query_exact(large_pos, large_pos + 100)).to eq 'large'
    end

    it 'handles negative positions' do
      tree.insert(-10, 0, 'negative')
      expect(tree.query_exact(-10, 0)).to eq 'negative'
    end
  end
end
