# frozen_string_literal: true

require 'spec_helper'

describe Parsanol::Atoms::Repetition do
  include Parsanol

  describe 'repeat' do
    let(:parslet) { str('a') }

    describe '(min, max)' do
      subject { parslet.repeat(1, 2) }

      it { should_not parse('') }
      it { should parse('a') }
      it { should parse('aa') }
    end
    describe '0 times' do
      it 'raises an ArgumentError' do
        expect do
          parslet.repeat(0, 0)
        end.to raise_error(ArgumentError)
      end
    end
  end
end
