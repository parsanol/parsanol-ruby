# frozen_string_literal: true

require "spec_helper"

describe Parsanol::Atoms::Repetition do
  include Parsanol

  describe "repeat" do
    let(:parslet) { str("a") }

    describe "(min, max)" do
      subject { parslet.repeat(1, 2) }

      it { is_expected.not_to parse("") }
      it { is_expected.to parse("a") }
      it { is_expected.to parse("aa") }
    end

    describe "0 times" do
      it "raises an ArgumentError" do
        expect do
          parslet.repeat(0, 0)
        end.to raise_error(ArgumentError)
      end
    end
  end

  describe "diagnostics" do
    it "does not format the repeated parser on a successful match" do
      atom = str("a")
      def atom.inspect
        raise "diagnostic formatting should be lazy"
      end

      parser = described_class.new(atom, 1, nil)

      expect(parser.parse("a")).to eq("a")
    end
  end
end
