# frozen_string_literal: true

require 'spec_helper'

describe 'parslet/convenience' do
  require 'parsanol/convenience'
  include Parsanol

  class FooParser < Parsanol::Parser
    rule(:foo) { str('foo') }
    root(:foo)
  end

  describe 'parse_with_debug' do
    let(:parser) { FooParser.new }

    context 'internal' do
      before do
        # Suppress output.
        #
        allow(parser).to receive(:puts)
      end

      it 'exists' do
        -> { parser.parse_with_debug('anything') }.should_not raise_error
      end

      it 'catches ParseFailed exceptions' do
        -> { parser.parse_with_debug('bar') }.should_not raise_error
      end

      it 'parses correct input like #parse' do
        -> { parser.parse_with_debug('foo') }.should_not raise_error
      end
    end

    context 'output' do
      it 'putses once for tree output' do
        expect(parser).to receive(:puts).once

        parser.parse_with_debug('incorrect')
      end

      it 'putses once for the error on unconsumed input' do
        expect(parser).to receive(:puts).once

        parser.parse_with_debug('foobar')
      end
    end

    it 'works for all parslets' do
      str('foo').parse_with_debug('foo')
      match['bar'].parse_with_debug('a')
    end
  end
end
