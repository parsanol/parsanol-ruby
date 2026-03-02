# frozen_string_literal: true

require 'spec_helper'

describe Parsanol::Slice do
  def cslice(string, bytepos, cache = nil)
    described_class.new(
      bytepos,
      string,
      cache
    )
  end

  describe 'construction' do
    it 'constructs from a byte position and a string' do
      cslice('foobar', 40)
    end
  end

  context "('foobar', 40, 'foobar')" do
    let(:slice) { cslice('foobar', 40) }

    describe 'comparison' do
      it 'is equal to other slices with the same attributes' do
        other = cslice('foobar', 40)
        slice.should
        other.should == slice
      end

      it 'is equal to other slices (offset is irrelevant for comparison)' do
        other = cslice('foobar', 41)
        slice.should
        other.should == slice
      end

      it 'is equal to a string with the same content' do
        slice.should == 'foobar'
      end

      it 'is equal to a string (inversed operands)' do
        'foobar'.should == slice
      end

      it 'is not equal to a string' do
        slice.should_not equal('foobar')
      end

      it 'is not eql to a string' do
        # In Opal, eql? must handle String comparison for Hash/Array equality
        skip if RUBY_ENGINE == 'opal'

        slice.should_not eql('foobar')
      end

      it 'does not hash to the same number' do
        slice.hash.should_not == 'foobar'.hash
      end
    end

    describe 'offset' do
      it 'returns the associated offset' do
        slice.offset.should == 40
      end

      it 'fails to return a line and column' do
        lambda {
          slice.line_and_column
        }.should raise_error(ArgumentError)
      end

      context 'when constructed with a source' do
        let(:cache) { double(:cache, line_and_column: [13, 14]) }
        let(:slice) { cslice('foobar', 40, cache) }

        it 'returns proper line and column' do
          slice.line_and_column.should == [13, 14]
        end
      end
    end

    describe '#bytepos' do
      it 'returns byte position' do
        slice.bytepos.should == 40
      end
    end

    describe '#charpos' do
      it 'returns same as offset (bytepos)' do
        slice.charpos.should == 40
      end
    end

    describe 'string methods' do
      describe 'matching' do
        it 'matches as a string would' do
          slice.should match(/bar/)
          slice.should match(/foo/)

          md = slice.match(/f(o)o/)
          md.captures.first.should == 'o'
        end
      end

      describe '<- #size' do
        subject { slice.size }

        it { is_expected.to eq(6) }
      end

      describe '<- #length' do
        subject { slice.length }

        it { is_expected.to eq(6) }
      end

      describe '<- #+' do
        subject { slice + other }

        let(:other) { cslice('baz', 10) }

        it 'concats like string does' do
          subject.size.should
          subject.should
          subject.offset.should == 40
        end
      end
    end

    describe 'conversion' do
      describe '<- #to_slice' do
        it 'returns self' do
          slice.to_slice.should eq(slice)
        end
      end

      describe '<- #to_sym' do
        it 'returns :foobar' do
          slice.to_sym.should == :foobar
        end
      end

      describe 'cast to Float' do
        it 'returns a float' do
          Float(cslice('1.345', 11)).should == 1.345
        end
      end

      describe 'cast to Integer' do
        it 'casts to integer as a string would' do
          s = cslice('1234', 40)
          Integer(s).should
          s.to_i.should == 1234
        end

        it 'fails when Integer would fail on a string' do
          -> { Integer(slice.to_s) }.should raise_error(ArgumentError, /invalid value/)
        end

        it 'turns into zero when a string would' do
          slice.to_i.should == 0
        end
      end
    end

    describe 'inspection and string conversion' do
      describe '#inspect' do
        subject { slice.inspect }

        it {
          # For Opal we have redefined inspect to return the string itself
          skip if RUBY_ENGINE == 'opal'

          is_expected.to eq('"foobar"@40')
        }
      end

      describe '#to_s' do
        subject { slice.to_s }

        it { is_expected.to eq('foobar') }
      end
    end

    describe 'serializability' do
      it 'serializes' do
        Marshal.dump(slice)
      end

      context 'when storing a line cache' do
        let(:slice) { cslice('foobar', 40, Parsanol::Source::LineCache.new) }

        it 'serializes' do
          Marshal.dump(slice)
        end
      end
    end
  end

  describe '.from_rope' do
    let(:bytepos) { 0 }

    it 'creates slice from rope' do
      rope = Parsanol::Rope.new.append('hello').append(' world')
      slice = described_class.from_rope(rope, bytepos)
      expect(slice.str).to eq('hello world')
      expect(slice.offset).to eq(0)
    end

    it 'handles empty rope' do
      rope = Parsanol::Rope.new
      slice = described_class.from_rope(rope, bytepos)
      expect(slice.str).to eq('')
      expect(slice.offset).to eq(0)
    end

    it 'handles rope with single segment' do
      rope = Parsanol::Rope.new.append('single')
      slice = described_class.from_rope(rope, bytepos)
      expect(slice.str).to eq('single')
    end

    it 'preserves position information' do
      rope = Parsanol::Rope.new.append('test')
      slice = described_class.from_rope(rope, 5)
      expect(slice.offset).to eq(5)
    end

    it 'preserves line cache' do
      cache = double(:cache, line_and_column: [10, 15])
      rope = Parsanol::Rope.new.append('test')
      slice = described_class.from_rope(rope, 0, cache)
      expect(slice.line_and_column).to eq([10, 15])
    end

    it 'handles rope with Slice segments' do
      rope = Parsanol::Rope.new
      rope.append(cslice('hello', 0))
      rope.append(cslice(' world', 5))
      slice = described_class.from_rope(rope, bytepos)
      expect(slice.str).to eq('hello world')
    end

    it 'creates a proper Slice instance' do
      rope = Parsanol::Rope.new.append('test')
      slice = described_class.from_rope(rope, bytepos)
      expect(slice).to be_a(Parsanol::Slice)
    end
  end
end
