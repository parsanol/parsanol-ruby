# frozen_string_literal: true

require "spec_helper"

describe Parsanol::Scope do
  let(:scope) { described_class.new }

  describe "simple store/retrieve" do
    before { scope[:foo] = :bar }

    it "allows storing objects" do
      scope[:obj] = 42
    end

    it "raises on access of empty slots" do
      expect do
        scope[:empty]
      end.to raise_error(Parsanol::Scope::NotFound)
    end

    it "allows retrieval of stored values" do
      scope[:foo].should == :bar
    end
  end

  describe "scoping" do
    subject { depth }

    before do
      scope[:depth] = 1
      scope.push
    end

    let(:depth) { scope[:depth] }

    it { is_expected.to eq(1) }

    describe "after a push" do
      before { scope.push }

      it { is_expected.to eq(1) }

      describe "and reassign" do
        before { scope[:depth] = 2 }

        it { is_expected.to eq(2) }

        describe "and a pop" do
          before { scope.pop }

          it { is_expected.to eq(1) }
        end
      end
    end
  end
end
