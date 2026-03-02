# frozen_string_literal: true

require 'spec_helper'

describe Parsanol::Atoms::Alternative do
  include Parsanol

  describe '| shortcut' do
    let(:alternative) { str('a') | str('b') }

    context 'when chained with different atoms' do
      before(:each) do
        # Chain something else to the alternative parslet. If it modifies the
        # parslet atom in place, we'll notice:

        alternative | str('d')
      end
      let!(:chained) { alternative | str('c') }

      it 'is side-effect free' do
        chained.should parse('c')
        chained.should parse('a')
        chained.should_not parse('d')
      end
    end
  end
end
