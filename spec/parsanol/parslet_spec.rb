# frozen_string_literal: true

require 'spec_helper'

describe Parsanol do
  include Parsanol

  describe Parsanol::ParseFailed do
    it 'should be caught by an empty rescue' do
      raise Parsanol::ParseFailed
    rescue StandardError
      # Success! Ignore this.
    end
  end
  describe '<- .rule' do
    # Rules define methods. This can be easily tested by defining them right
    # here.
    context 'empty rule' do
      rule(:empty) {}

      it 'should raise a NotImplementedError' do
        lambda {
          empty.parslet
        }.should raise_error(NotImplementedError)
      end
    end

    context "containing 'any'" do
      rule(:any_rule) { any }
      subject { any_rule }

      it { should be_a Parsanol::Atoms::Entity }
      it 'should memoize the returned instance' do
        any_rule.object_id.should == any_rule.object_id
      end
    end
  end
end
