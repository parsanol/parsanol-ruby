require 'spec_helper'

describe Parsanol::Rope do
  describe '#append' do
    it 'appends strings' do
      rope = described_class.new
      rope.append('hello')
      rope.append(' ')
      rope.append('world')
      expect(rope.to_s).to eq('hello world')
    end

    it 'appends Slices' do
      rope = described_class.new
      rope.append(Parsanol::Slice.new(0, 'hello'))
      rope.append(Parsanol::Slice.new(5, ' world'))
      expect(rope.to_s).to eq('hello world')
    end

    it 'appends mixed strings and Slices' do
      rope = described_class.new
      rope.append('hello')
      rope.append(Parsanol::Slice.new(5, ' '))
      rope.append('world')
      expect(rope.to_s).to eq('hello world')
    end

    it 'returns self for chaining' do
      rope = described_class.new
      result = rope.append('a')
      expect(result).to equal(rope)
    end

    it 'allows chaining multiple appends' do
      rope = described_class.new
      rope.append('a').append('b').append('c')
      expect(rope.to_s).to eq('abc')
    end

    it 'freezes after to_s' do
      rope = described_class.new.append('test')
      rope.to_s
      expect { rope.append('more') }.to raise_error(FrozenError)
    end

    it 'raises FrozenError with descriptive message' do
      rope = described_class.new.append('test')
      rope.to_s
      expect { rope.append('more') }.to raise_error(FrozenError, /frozen Rope/)
    end

    it 'handles empty string segments' do
      rope = described_class.new
      rope.append('hello')
      rope.append('')
      rope.append('world')
      expect(rope.to_s).to eq('helloworld')
    end
  end

  describe '#to_s' do
    it 'joins all segments' do
      rope = described_class.new
      rope.append('a').append('b').append('c')
      expect(rope.to_s).to eq('abc')
    end

    it 'handles empty rope' do
      rope = described_class.new
      expect(rope.to_s).to eq('')
    end

    it 'handles single segment' do
      rope = described_class.new.append('test')
      expect(rope.to_s).to eq('test')
    end

    it 'joins Slice objects correctly' do
      rope = described_class.new
      rope.append(Parsanol::Slice.new(0, 'first'))
      rope.append(Parsanol::Slice.new(5, 'second'))
      expect(rope.to_s).to eq('firstsecond')
    end

    it 'can be called multiple times (idempotent)' do
      rope = described_class.new.append('test')
      result1 = rope.to_s
      result2 = rope.to_s
      expect(result1).to eq('test')
      expect(result2).to eq('test')
    end

    it 'freezes the rope' do
      rope = described_class.new.append('test')
      expect(rope.to_s).to eq('test')
      expect { rope.append('more') }.to raise_error(FrozenError)
    end
  end

  describe '#empty?' do
    it 'returns true for new rope' do
      rope = described_class.new
      expect(rope.empty?).to be true
    end

    it 'returns false after append' do
      rope = described_class.new.append('x')
      expect(rope.empty?).to be false
    end

    it 'returns false after appending empty string' do
      rope = described_class.new.append('')
      expect(rope.empty?).to be false
    end

    it 'returns false after appending Slice' do
      rope = described_class.new.append(Parsanol::Slice.new(0, 'x'))
      expect(rope.empty?).to be false
    end
  end

  describe '#size' do
    it 'returns 0 for empty rope' do
      rope = described_class.new
      expect(rope.size).to eq(0)
    end

    it 'estimates total size for strings' do
      rope = described_class.new
      rope.append('hello').append('world')
      expect(rope.size).to eq(10)
    end

    it 'estimates total size for Slices' do
      rope = described_class.new
      rope.append(Parsanol::Slice.new(0, 'hello'))
      rope.append(Parsanol::Slice.new(5, 'world'))
      expect(rope.size).to eq(10)
    end

    it 'estimates total size for mixed segments' do
      rope = described_class.new
      rope.append('hello')
      rope.append(Parsanol::Slice.new(5, ' '))
      rope.append('world')
      expect(rope.size).to eq(11)
    end

    it 'handles empty string segments' do
      rope = described_class.new
      rope.append('hello')
      rope.append('')
      rope.append('world')
      expect(rope.size).to eq(10)
    end
  end

  describe '.from_string' do
    it 'creates rope from string' do
      rope = described_class.from_string('test')
      expect(rope.to_s).to eq('test')
    end

    it 'handles empty string' do
      rope = described_class.from_string('')
      expect(rope.empty?).to be true
      expect(rope.to_s).to eq('')
    end

    it 'creates a new rope instance each time' do
      rope1 = described_class.from_string('test')
      rope2 = described_class.from_string('test')
      expect(rope1).not_to equal(rope2)
    end

    it 'allows further appends' do
      rope = described_class.from_string('hello')
      rope.append(' world')
      expect(rope.to_s).to eq('hello world')
    end
  end

  describe 'integration scenarios' do
    it 'handles complex concatenation patterns' do
      rope = described_class.new
      100.times { |i| rope.append(i.to_s) }
      result = rope.to_s
      expected = (0...100).map(&:to_s).join
      expect(result).to eq(expected)
    end

    it 'handles Unicode strings' do
      rope = described_class.new
      rope.append('Hello')
      rope.append(' ')
      rope.append('世界')
      expect(rope.to_s).to eq('Hello 世界')
    end

    it 'handles multi-byte characters in size calculation' do
      rope = described_class.new
      rope.append('Hello ')
      rope.append('世界')
      expect(rope.size).to eq(8)  # 6 ASCII + 2 multi-byte chars (counted as chars, not bytes)
    end
  end
end