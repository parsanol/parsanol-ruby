# frozen_string_literal: true

require 'spec_helper'

describe Parsanol::StringView do
  let(:input) { 'Hello World' }

  describe '#initialize' do
    it 'creates view with offset and length' do
      view = described_class.new(input, offset: 6, length: 5)
      expect(view.offset).to eq(6)
      expect(view.length).to eq(5)
      expect(view.string).to eq(input)
    end

    it 'defaults to full string when no offset given' do
      view = described_class.new(input)
      expect(view.offset).to eq(0)
      expect(view.length).to eq(input.bytesize)
    end

    it 'calculates length from offset when not provided' do
      view = described_class.new(input, offset: 6)
      expect(view.length).to eq(5) # "Hello World" - 6 = 5
    end

    it 'accepts explicit length' do
      view = described_class.new(input, offset: 0, length: 5)
      expect(view.length).to eq(5)
    end

    it 'does not materialize string on initialization' do
      view = described_class.new(input, offset: 0, length: 5)
      expect(view.inspect).not_to include('cached')
    end
  end

  describe '#to_s' do
    it 'materializes substring' do
      view = described_class.new(input, offset: 0, length: 5)
      expect(view.to_s).to eq('Hello')
    end

    it 'materializes full string' do
      view = described_class.new(input)
      expect(view.to_s).to eq('Hello World')
    end

    it 'materializes substring from middle' do
      view = described_class.new(input, offset: 6, length: 5)
      expect(view.to_s).to eq('World')
    end

    it 'caches materialized string' do
      view = described_class.new(input, offset: 6, length: 5)
      str1 = view.to_s
      str2 = view.to_s
      expect(str1.object_id).to eq(str2.object_id)
    end

    it 'handles empty view' do
      view = described_class.new(input, offset: 0, length: 0)
      expect(view.to_s).to eq('')
    end

    it 'handles single character' do
      view = described_class.new(input, offset: 0, length: 1)
      expect(view.to_s).to eq('H')
    end
  end

  describe '#[]' do
    it 'accesses character without materialization' do
      view = described_class.new(input, offset: 6, length: 5)
      expect(view[0]).to eq('W')
      expect(view[4]).to eq('d')
      expect(view.inspect).not_to include('cached')
    end

    it 'returns first character' do
      view = described_class.new(input, offset: 0, length: 5)
      expect(view[0]).to eq('H')
    end

    it 'returns last character' do
      view = described_class.new(input, offset: 0, length: 5)
      expect(view[4]).to eq('o')
    end

    it 'returns nil for out of bounds positive index' do
      view = described_class.new(input, offset: 0, length: 5)
      expect(view[10]).to be_nil
    end

    it 'returns nil for negative index' do
      view = described_class.new(input, offset: 0, length: 5)
      expect(view[-1]).to be_nil
    end

    it 'returns nil for index at length boundary' do
      view = described_class.new(input, offset: 0, length: 5)
      expect(view[5]).to be_nil
    end

    it 'works with offset view' do
      view = described_class.new(input, offset: 6, length: 5)
      expect(view[0]).to eq('W')
      expect(view[1]).to eq('o')
      expect(view[2]).to eq('r')
    end
  end

  describe '#slice' do
    it 'creates substring view without copying' do
      view = described_class.new(input, offset: 0, length: 11)
      sub = view.slice(6, 5)
      expect(sub.to_s).to eq('World')
      expect(sub.offset).to eq(6)
      expect(sub.length).to eq(5)
    end

    it 'shares same string reference' do
      view = described_class.new(input, offset: 0, length: 11)
      sub = view.slice(6, 5)
      expect(sub.string.object_id).to eq(view.string.object_id)
    end

    it 'creates view from middle of view' do
      view = described_class.new(input, offset: 6, length: 5)
      sub = view.slice(1, 3)
      expect(sub.to_s).to eq('orl')
    end

    it 'handles zero-length slice' do
      view = described_class.new(input, offset: 0, length: 5)
      sub = view.slice(0, 0)
      expect(sub.to_s).to eq('')
      expect(sub.empty?).to be true
    end

    it 'handles negative length' do
      view = described_class.new(input, offset: 0, length: 5)
      sub = view.slice(0, -1)
      expect(sub.to_s).to eq('')
    end

    it 'clamps to valid range when slicing beyond end' do
      view = described_class.new(input, offset: 0, length: 5)
      sub = view.slice(3, 10)
      expect(sub.to_s).to eq('lo')
    end

    it 'returns empty view when start is beyond length' do
      view = described_class.new(input, offset: 0, length: 5)
      sub = view.slice(10, 5)
      expect(sub.to_s).to eq('')
    end
  end

  describe '#bytesize, #size, #length' do
    it 'returns length in bytes' do
      view = described_class.new(input, offset: 0, length: 5)
      expect(view.bytesize).to eq(5)
      expect(view.size).to eq(5)
      expect(view.length).to eq(5)
    end

    it 'returns zero for empty view' do
      view = described_class.new(input, offset: 0, length: 0)
      expect(view.bytesize).to eq(0)
    end
  end

  describe '#empty?' do
    it 'returns true for zero-length view' do
      view = described_class.new(input, offset: 0, length: 0)
      expect(view.empty?).to be true
    end

    it 'returns false for non-empty view' do
      view = described_class.new(input, offset: 0, length: 5)
      expect(view.empty?).to be false
    end
  end

  describe '#==' do
    it 'compares with String by materializing' do
      view = described_class.new(input, offset: 0, length: 5)
      expect(view == 'Hello').to be true
      expect(view == 'World').to be false
    end

    it 'compares two StringViews without materializing' do
      view1 = described_class.new(input, offset: 0, length: 5)
      view2 = described_class.new(input, offset: 0, length: 5)
      expect(view1 == view2).to be true
      expect(view1.inspect).not_to include('cached')
      expect(view2.inspect).not_to include('cached')
    end

    it 'distinguishes different ranges on same string' do
      view1 = described_class.new(input, offset: 0, length: 5)
      view2 = described_class.new(input, offset: 6, length: 5)
      expect(view1 == view2).to be false
    end

    it 'distinguishes different strings' do
      other_input = 'Hello World'.dup # Ensure different object
      view1 = described_class.new(input, offset: 0, length: 5)
      view2 = described_class.new(other_input, offset: 0, length: 5)
      # Verify they are actually different objects
      expect(input.object_id).not_to eq(other_input.object_id)
      # StringViews should not be equal (different string objects)
      expect(view1 == view2).to be false
    end

    it 'eql? works same as ==' do
      view = described_class.new(input, offset: 0, length: 5)
      expect(view.eql?('Hello')).to be true
    end
  end

  describe '#hash' do
    it 'returns hash code for hashing' do
      view = described_class.new(input, offset: 0, length: 5)
      expect(view.hash).to be_a(Integer)
    end

    it 'same views have same hash' do
      view1 = described_class.new(input, offset: 0, length: 5)
      view2 = described_class.new(input, offset: 0, length: 5)
      expect(view1.hash).to eq(view2.hash)
    end

    it 'different views have different hashes' do
      view1 = described_class.new(input, offset: 0, length: 5)
      view2 = described_class.new(input, offset: 6, length: 5)
      expect(view1.hash).not_to eq(view2.hash)
    end

    it 'can be used in Hash' do
      view = described_class.new(input, offset: 0, length: 5)
      hash = { view => 'value' }
      expect(hash[view]).to eq('value')
    end
  end

  describe '#inspect' do
    it 'shows offset and length' do
      view = described_class.new(input, offset: 6, length: 5)
      result = view.inspect
      expect(result).to include('StringView')
      expect(result).to include('@offset=6')
      expect(result).to include('@length=5')
    end

    it 'shows cached status when materialized' do
      view = described_class.new(input, offset: 0, length: 5)
      view.to_s
      result = view.inspect
      expect(result).to include('cached="Hello"')
    end

    it 'does not show cached when not materialized' do
      view = described_class.new(input, offset: 0, length: 5)
      result = view.inspect
      expect(result).not_to include('cached')
    end
  end

  describe '#reset!' do
    it 'resets view with new values' do
      view = described_class.new(input, offset: 0, length: 5)
      view.to_s # Materialize

      new_input = 'Goodbye'
      view.reset!(new_input, 0, 4)

      expect(view.string).to eq(new_input)
      expect(view.offset).to eq(0)
      expect(view.length).to eq(4)
      expect(view.to_s).to eq('Good')
    end

    it 'clears cached materialization' do
      view = described_class.new(input, offset: 0, length: 5)
      view.to_s # Materialize
      expect(view.inspect).to include('cached')

      view.reset!(input, 6, 5)
      expect(view.inspect).not_to include('cached')
      expect(view.to_s).to eq('World')
    end

    it 'returns self for chaining' do
      view = described_class.new(input, offset: 0, length: 5)
      result = view.reset!(input, 6, 5)
      expect(result).to be(view)
    end
  end

  describe 'UTF-8 support' do
    let(:utf8_input) { 'Hello 世界' }

    it 'handles UTF-8 strings' do
      view = described_class.new(utf8_input, offset: 0, length: utf8_input.bytesize)
      expect(view.to_s).to eq(utf8_input)
    end

    it 'uses byte offsets not character offsets' do
      # "Hello " is 6 bytes, "世" is 3 bytes, "界" is 3 bytes
      view = described_class.new(utf8_input, offset: 6, length: 6)
      expect(view.to_s).to eq('世界')
    end
  end

  describe 'zero-copy performance characteristics' do
    it 'does not create strings during slicing operations' do
      view = described_class.new(input, offset: 0, length: 11)

      # Chain multiple slice operations
      sub1 = view.slice(0, 5)
      sub2 = sub1.slice(0, 3)
      sub3 = sub2.slice(1, 1)

      # No strings created yet
      expect(view.inspect).not_to include('cached')
      expect(sub1.inspect).not_to include('cached')
      expect(sub2.inspect).not_to include('cached')

      # Only when we call to_s
      expect(sub3.to_s).to eq('e')
    end

    it 'shares string reference across all views' do
      view = described_class.new(input, offset: 0, length: 11)
      sub1 = view.slice(0, 5)
      sub2 = sub1.slice(0, 3)

      expect(view.string.object_id).to eq(input.object_id)
      expect(sub1.string.object_id).to eq(input.object_id)
      expect(sub2.string.object_id).to eq(input.object_id)
    end
  end
end
