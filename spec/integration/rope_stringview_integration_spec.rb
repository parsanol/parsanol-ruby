# frozen_string_literal: true

require 'spec_helper'

describe 'Rope + StringView Integration' do
  let(:source_str) { 'hello world this is a test' }

  describe 'Rope with StringView segments' do
    it 'builds rope from StringView segments' do
      rope = Parsanol::Rope.new

      # Create StringView segments (zero-copy)
      view1 = Parsanol::StringView.new(source_str, offset: 0, length: 5)
      view2 = Parsanol::StringView.new(source_str, offset: 6, length: 5)

      rope.append(view1)
      rope.append(' ')
      rope.append(view2)

      expect(rope.to_s).to eq('hello world')
    end

    it 'builds rope from mixed StringView and String segments' do
      rope = Parsanol::Rope.new

      view1 = Parsanol::StringView.new(source_str, offset: 0, length: 5)

      rope.append(view1)
      rope.append(' from ')
      rope.append('rope')

      expect(rope.to_s).to eq('hello from rope')
    end

    it 'builds rope from Slices containing StringViews' do
      rope = Parsanol::Rope.new

      # Create Slices with StringView (as Source.consume does)
      view1 = Parsanol::StringView.new(source_str, offset: 0, length: 5)
      slice1 = Parsanol::Slice.new(0, view1)

      view2 = Parsanol::StringView.new(source_str, offset: 6, length: 5)
      slice2 = Parsanol::Slice.new(6, view2)

      rope.append(slice1)
      rope.append(' ')
      rope.append(slice2)

      expect(rope.to_s).to eq('hello world')
    end
  end

  describe 'Slice.from_rope with StringView' do
    it 'converts rope to slice' do
      rope = Parsanol::Rope.new
      rope.append('hello')
      rope.append(' ')
      rope.append('world')

      slice = Parsanol::Slice.from_rope(rope, 0)

      expect(slice.to_s).to eq('hello world')
      expect(slice.offset).to eq(0)
    end

    it 'converts rope with StringView segments to slice' do
      rope = Parsanol::Rope.new

      view1 = Parsanol::StringView.new(source_str, offset: 0, length: 5)
      view2 = Parsanol::StringView.new(source_str, offset: 6, length: 5)

      rope.append(view1)
      rope.append(' ')
      rope.append(view2)

      slice = Parsanol::Slice.from_rope(rope, 0)

      expect(slice.to_s).to eq('hello world')
      expect(slice.str).to eq('hello world')
    end

    it 'preserves line cache when converting rope to slice' do
      line_cache = double('line_cache')
      allow(line_cache).to receive(:line_and_column).with(0).and_return([1, 1])

      rope = Parsanol::Rope.new.append('test')
      slice = Parsanol::Slice.from_rope(rope, 0, line_cache)

      expect(slice.line_and_column).to eq([1, 1])
    end
  end

  describe 'Rope with UTF-8 StringView segments' do
    let(:utf8_str) { 'Hello 世界 test' }

    it 'handles UTF-8 StringView segments correctly' do
      rope = Parsanol::Rope.new

      # UTF-8 segment
      view1 = Parsanol::StringView.new(utf8_str, offset: 0, length: 6)
      view2 = Parsanol::StringView.new(utf8_str, offset: 6, length: 6)

      rope.append(view1)
      rope.append(view2)

      result = rope.to_s
      expect(result).to eq('Hello 世界')
      expect(result.encoding).to eq(Encoding::UTF_8)
    end

    it 'calculates size correctly for UTF-8 content' do
      rope = Parsanol::Rope.new

      view1 = Parsanol::StringView.new(utf8_str, offset: 0, length: 6)
      rope.append(view1)

      # Size based on string length, not byte length
      expect(rope.size).to eq(6)
    end
  end

  describe 'Performance characteristics' do
    it 'defers materialization until to_s called' do
      rope = Parsanol::Rope.new

      # Create views (no string materialization yet)
      view1 = Parsanol::StringView.new(source_str, offset: 0, length: 5)
      view2 = Parsanol::StringView.new(source_str, offset: 6, length: 5)

      rope.append(view1)
      rope.append(view2)

      # Verify views haven't materialized yet
      expect(view1.instance_variable_get(:@materialized)).to be_nil
      expect(view2.instance_variable_get(:@materialized)).to be_nil

      # Materialize only on to_s
      result = rope.to_s

      # Now views are materialized as part of joining
      expect(result).to eq('helloworld')
    end

    it 'handles large number of StringView segments efficiently' do
      rope = Parsanol::Rope.new

      # Append 100 small segments
      100.times do |i|
        offset = i * 2
        view = Parsanol::StringView.new('ab' * 100, offset: offset, length: 2)
        rope.append(view)
      end

      result = rope.to_s
      expect(result.length).to eq(200)
    end
  end

  describe 'Edge cases' do
    it 'handles empty StringView segments' do
      rope = Parsanol::Rope.new

      view1 = Parsanol::StringView.new(source_str, offset: 0, length: 0)
      rope.append(view1)
      rope.append('test')

      expect(rope.to_s).to eq('test')
    end

    it 'handles rope with only StringView segments' do
      rope = Parsanol::Rope.new

      view1 = Parsanol::StringView.new(source_str, offset: 0, length: 5)
      view2 = Parsanol::StringView.new(source_str, offset: 6, length: 5)
      view3 = Parsanol::StringView.new(source_str, offset: 12, length: 4)

      rope.append(view1).append(view2).append(view3)

      expect(rope.to_s).to eq('helloworldthis')
    end

    it 'handles empty rope' do
      rope = Parsanol::Rope.new
      slice = Parsanol::Slice.from_rope(rope, 0)

      expect(slice.to_s).to eq('')
      expect(slice.size).to eq(0)
    end
  end
end
