# frozen_string_literal: true

require 'spec_helper'
require 'parsanol/edit_tracker'

describe Parsanol::EditTracker do
  let(:tracker) { Parsanol::EditTracker.new }

  describe '#initialize' do
    it 'creates an empty tracker' do
      expect(tracker.empty?).to be true
      expect(tracker.size).to eq 0
    end
  end

  describe '#insert and #delete' do
    it 'records insertions' do
      tracker.insert(10, 5)
      expect(tracker.size).to eq 1
      expect(tracker.edits.first.position).to eq 10
      expect(tracker.edits.first.delta).to eq 5
    end

    it 'records deletions' do
      tracker.delete(20, 3)
      expect(tracker.size).to eq 1
      expect(tracker.edits.first.position).to eq 20
      expect(tracker.edits.first.delta).to eq(-3)
    end

    it 'records multiple edits in order' do
      tracker.insert(10, 5)
      tracker.delete(30, 2)
      tracker.insert(50, 10)

      expect(tracker.size).to eq 3
      expect(tracker.edits[0].delta).to eq 5
      expect(tracker.edits[1].delta).to eq(-2)
      expect(tracker.edits[2].delta).to eq 10
    end
  end

  describe '#shift_interval' do
    context 'with no edits' do
      it 'returns the original interval' do
        result = tracker.shift_interval(10, 20)
        expect(result).to eq [10, 20]
      end
    end

    context 'with edit before interval' do
      it 'shifts both boundaries forward for insertion' do
        tracker.insert(5, 10) # Insert 10 chars at position 5
        result = tracker.shift_interval(10, 20)
        expect(result).to eq [20, 30] # Both shifted by +10
      end

      it 'shifts both boundaries backward for deletion' do
        tracker.delete(5, 3) # Delete 3 chars at position 5
        result = tracker.shift_interval(10, 20)
        expect(result).to eq [7, 17] # Both shifted by -3
      end
    end

    context 'with edit after interval' do
      it 'does not shift interval for insertion' do
        tracker.insert(50, 10)
        result = tracker.shift_interval(10, 20)
        expect(result).to eq [10, 20]  # No change
      end

      it 'does not shift interval for deletion' do
        tracker.delete(50, 5)
        result = tracker.shift_interval(10, 20)
        expect(result).to eq [10, 20]  # No change
      end
    end

    context 'with edit inside interval' do
      it 'invalidates interval for insertion' do
        tracker.insert(15, 5) # Insert inside [10, 20)
        result = tracker.shift_interval(10, 20)
        expect(result).to be_nil # Invalidated
      end

      it 'invalidates interval for deletion' do
        tracker.delete(15, 3) # Delete inside [10, 20)
        result = tracker.shift_interval(10, 20)
        expect(result).to be_nil # Invalidated
      end

      it 'invalidates interval for edit at start boundary' do
        tracker.insert(10, 5) # Edit at start of [10, 20)
        result = tracker.shift_interval(10, 20)
        expect(result).to be_nil # Invalidated
      end
    end

    context 'with edit at end boundary' do
      it 'does not invalidate interval' do
        tracker.insert(20, 5) # Edit at end of [10, 20) - not inside
        result = tracker.shift_interval(10, 20)
        expect(result).to eq [10, 20] # Not invalidated
      end
    end

    context 'with multiple edits' do
      it 'applies all edits in order' do
        tracker.insert(5, 10)   # Shift [10,20) to [20,30)
        tracker.insert(3, 5)    # Shift [20,30) to [25,35)
        tracker.delete(2, 1)    # Shift [25,35) to [24,34)

        result = tracker.shift_interval(10, 20)
        expect(result).to eq [24, 34]
      end

      it 'invalidates if any edit is inside interval' do
        tracker.insert(5, 10)   # Shift [10,20) to [20,30)
        tracker.insert(25, 5)   # Inside shifted interval [20,30)

        result = tracker.shift_interval(10, 20)
        expect(result).to be_nil # Invalidated by second edit
      end

      it 'handles complex sequence of edits' do
        # Start with interval [100, 200)
        tracker.insert(50, 20)    # Shift to [120, 220)
        tracker.delete(80, 10)    # Shift to [110, 210)
        tracker.insert(250, 30)   # After interval, no shift
        tracker.insert(90, 5)     # Shift to [115, 215)

        result = tracker.shift_interval(100, 200)
        expect(result).to eq [115, 215]
      end
    end

    context 'with invalidation conditions' do
      it 'invalidates if shifted interval becomes negative' do
        tracker.delete(5, 20) # Large deletion before interval
        result = tracker.shift_interval(10, 20)
        expect(result).to be_nil # Would become [<0, <0)
      end

      it 'invalidates if high becomes less than low' do
        tracker.delete(5, 100) # Very large deletion
        result = tracker.shift_interval(10, 20)
        expect(result).to be_nil # Would become invalid
      end
    end
  end

  describe '#invalidates?' do
    it 'returns false when interval is valid after edits' do
      tracker.insert(5, 10)
      expect(tracker.invalidates?(20, 30)).to be false
    end

    it 'returns true when interval is invalidated' do
      tracker.insert(15, 5)
      expect(tracker.invalidates?(10, 20)).to be true
    end
  end

  describe '#clear' do
    it 'removes all edits' do
      tracker.insert(10, 5)
      tracker.delete(20, 3)
      tracker.clear

      expect(tracker.empty?).to be true
      expect(tracker.size).to eq 0
    end

    it 'resets interval shifting' do
      tracker.insert(5, 10)
      tracker.clear

      result = tracker.shift_interval(10, 20)
      expect(result).to eq [10, 20]  # No shift after clear
    end
  end

  describe 'edge cases' do
    it 'handles zero-length intervals' do
      tracker.insert(10, 5)
      result = tracker.shift_interval(15, 15)
      expect(result).to eq [20, 20]  # Shifted but still zero-length
    end

    it 'handles zero-length insertions' do
      tracker.insert(10, 0)
      result = tracker.shift_interval(5, 15)
      expect(result).to eq [5, 15]  # No change
    end

    it 'handles zero-length deletions' do
      tracker.delete(10, 0)
      result = tracker.shift_interval(5, 15)
      expect(result).to eq [5, 15]  # No change
    end

    it 'handles negative positions in edits' do
      tracker.insert(-5, 10)
      result = tracker.shift_interval(10, 20)
      expect(result).to eq [20, 30] # Shifted
    end
  end

  describe 'Edit#to_s' do
    it 'describes insertions' do
      edit = Parsanol::EditTracker::Edit.new(10, 5)
      expect(edit.to_s).to eq 'Insert(5 chars at 10)'
    end

    it 'describes deletions' do
      edit = Parsanol::EditTracker::Edit.new(20, -3)
      expect(edit.to_s).to eq 'Delete(3 chars at 20)'
    end
  end
end
