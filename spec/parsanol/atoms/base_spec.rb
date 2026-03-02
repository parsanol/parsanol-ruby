# frozen_string_literal: true

require 'spec_helper'

describe Parsanol::Atoms::Base do
  let(:parslet) { Parsanol::Atoms::Base.new }
  let(:context) { Parsanol::Atoms::Context.new }

  describe '<- #try(io)' do
    it 'raises NotImplementedError' do
      lambda {
        parslet.try(double(:io), context, false)
      }.should raise_error(NotImplementedError)
    end
  end

  describe '<- #flatten_sequence' do
    [
      # 9 possibilities for making a word of 2 letters from the alphabeth of
      # A(rray), H(ash) and S(tring). Make sure that all results are valid.
      #
      %w[a b], 'ab',                             # S S
      [['a'], ['b']], %w[a b],                   # A A
      [{ a: 'a' }, { b: 'b' }], { a: 'a', b: 'b' }, # H H

      [{ a: 'a' }, ['a']], [{ a: 'a' }, 'a'],         # H A
      [{ a: 'a' }, 's'],   { a: 'a' },                # H S

      [['a'], { a: 'a' }], ['a', { a: 'a' }],         # A H (symmetric to H A)
      [['a'], 'b'], ['a'], # A S

      ['a', { b: 'b' }], { b: 'b' }, # S H (symmetric to H S)
      ['a', ['b']], ['b'],                          # S A (symmetric to A S)

      [nil, ['a']], ['a'],                          # handling of lhs nil
      [nil, { a: 'a' }], { a: 'a' },
      [['a'], nil], ['a'],                          # handling of rhs nil
      [{ a: 'a' }, nil], { a: 'a' }
    ].each_slice(2) do |sequence, result|
      context "for #{sequence.inspect}" do
        it "equals #{result.inspect}" do
          parslet.flatten_sequence(sequence).should == result
        end
      end
    end
  end

  describe '<- #flatten_repetition' do
    def unnamed(obj)
      parslet.flatten_repetition(obj, false)
    end

    it 'gives subtrees precedence' do
      unnamed([[{ a: 'a' }, { m: 'm' }], { a: 'a' }]).should == [{ a: 'a' }]
    end
  end

  describe '#parse(source)' do
    context 'when given something that looks like a source' do
      let(:source) do
        double('source lookalike',
               line_and_column: [1, 2],
               bytepos: 1,
               chars_left: 0)
      end

      it 'does not rewrap in a source' do
        expect(Parsanol::Source).not_to receive(:new)

        begin
          parslet.parse(source)
        rescue NotImplementedError
        end
      end
    end
  end

  context 'when the parse fails, the exception' do
    it 'contains a string' do
      Parsanol.str('foo').parse('bar')
    rescue Parsanol::ParseFailed => e
      e.message.should be_kind_of(String)
    end
  end

  context 'when not all input is consumed' do
    let(:parslet) { Parsanol.str('foo') }

    it 'raises with a proper error message' do
      error = catch_failed_parse do
        parslet.parse('foobar')
      end

      error.to_s.should == "Don't know what to do with \"bar\" at line 1 char 4."
    end
  end

  context 'when only parsing string prefix' do
    let(:parslet) { Parsanol.str('foo') >> Parsanol.str('bar') }

    it 'returns the first half on a prefix parse' do
      parslet.parse('foobarbaz', prefix: true).should == 'foobar'
    end
  end

  describe ':reporter option' do
    let(:parslet) { Parsanol.str('test') >> Parsanol.str('ing') }
    let(:reporter) { double(:reporter) }

    it 'replaces the default reporter' do
      cause = double(:cause)

      # Two levels of the parse, calling two different error reporting
      # methods.
      expect(reporter).to receive(:err_at).once
      expect(reporter).to receive(:err).and_return(cause).once
      expect(reporter).to receive(:succ).once

      # The final cause will be sent the #raise method.
      expect(cause).to receive(:raise).once.and_throw(:raise)

      catch(:raise) do
        parslet.parse('testung', reporter: reporter)

        raise 'NEVER REACHED'
      end
    end
  end
end
