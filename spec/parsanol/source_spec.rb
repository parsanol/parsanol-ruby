# frozen_string_literal: true

require 'spec_helper'

describe Parsanol::Source do
  describe 'using simple input' do
    let(:str)     { "#{'a' * 100}\n#{'a' * 100}\n" }
    let(:source)  { described_class.new(str) }

    describe '<- #read(n)' do
      it 'does not raise error when the return value is nil' do
        described_class.new('').consume(1)
      end

      it "returns 100 'a's when reading 100 chars" do
        source.consume(100).should == 'a' * 100
      end
    end

    describe '<- #chars_left' do
      subject { source.chars_left }

      it { is_expected.to eq(202) }

      context 'after depleting the source' do
        before { source.consume(10_000) }

        it { is_expected.to eq(0) }
      end
    end

    describe '<- #pos' do
      subject { source.pos }

      it { is_expected.to eq(0) }

      context 'after reading a few bytes' do
        it 'stills be correct' do
          pos = 0
          10.times do
            pos += (n = rand(1..10))
            source.consume(n)

            source.pos.should == pos
          end
        end
      end
    end

    describe '<- #pos=(n)' do
      subject { source.pos }

      10.times do
        pos = rand(200)
        context "setting position #{pos}" do
          before { source.bytepos = pos }

          it { is_expected.to eq(pos) }
        end
      end
    end

    describe '#chars_until' do
      it 'returns 100 chars before line end' do
        source.chars_until("\n").should == 100
      end
    end

    describe '<- #column & #line' do
      subject { source.line_and_column }

      it { is_expected.to eq([1, 1]) }

      context 'on the first line' do
        it 'increases column with every read' do
          10.times do |_i|
            source.line_and_column.last.should
            source.consume(1)
          end
        end
      end

      context 'on the second line' do
        before { source.consume(101) }

        it { is_expected.to eq([2, 1]) }
      end

      context 'after reading everything' do
        before { source.consume(10_000) }

        context 'when seeking to 9' do
          before { source.bytepos = 9 }

          it { is_expected.to eq([1, 10]) }
        end

        context 'when seeking to 100' do
          before { source.bytepos = 100 }

          it { is_expected.to eq([1, 101]) }
        end

        context 'when seeking to 101' do
          before { source.bytepos = 101 }

          it { is_expected.to eq([2, 1]) }
        end

        context 'when seeking to 102' do
          before { source.bytepos = 102 }

          it { is_expected.to eq([2, 2]) }
        end

        context 'when seeking beyond eof' do
          it 'does not throw an error' do
            source.bytepos = 1000
          end
        end
      end

      context 'reading char by char, storing the results' do
        attr_reader :results

        before do
          @results = {}
          while source.chars_left > 0
            pos = source.pos
            @results[pos] = source.line_and_column
            source.consume(1)
          end

          @results.entries.size.should
          @results
        end

        context 'when using pos argument' do
          it 'returns the same results' do
            results.each do |pos, result|
              source.line_and_column(pos).should == result
            end
          end
        end

        it 'gives the same results when seeking' do
          results.each do |pos, result|
            source.bytepos = pos
            source.line_and_column.should == result
          end
        end

        it 'gives the same results when reading' do
          cur = source.bytepos = 0
          while source.chars_left > 0
            source.line_and_column.should
            results[cur]
            cur += 1
            source.consume(1)
          end
        end
      end
    end
  end

  describe 'reading encoded input' do
    let(:source) { described_class.new('éö変わる') }

    def r(str)
      Regexp.new(Regexp.escape(str))
    end

    it 'reads characters, not bytes' do
      source.should match(r('é'))
      source.consume(1)

      # NOTE: pos now returns bytepos directly (not charpos)
      # For UTF-8: é is 2 bytes, ö is 2 bytes
      source.pos.should
      if RUBY_ENGINE == 'opal'
        # In Opal/JavaScript, string indexing is character-based
        1
      else
        # In Ruby, multi-byte characters use multiple bytes
        2
      end

      # TODO: This needs to be fixed in code with Opal
      if RUBY_ENGINE == 'opal'
        skip 'Opal does not support byte positions and char positions correctly for multi-byte characters'
      end

      source.bytepos.should # Ruby: 2 bytes for 'é'

      source.should match(r('ö'))
      source.consume(1)

      # After consuming 'é' (2 bytes) and 'ö' (2 bytes) = 4 bytes total
      source.pos.should

      source.bytepos.should

      source.should match(r('変'))
      source.consume(1)

      source.consume(2)
      source.chars_left.should
      source.chars_left.should == 0
    end
  end
end
