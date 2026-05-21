# frozen_string_literal: true

require "spec_helper"

describe Parsanol::Atoms::Sequence do
  include Parsanol

  let(:sequence) { described_class.new }

  describe ">> shortcut" do
    let(:sequence) { str("a") >> str("b") }

    context "when chained with different atoms" do
      before do
        # Chain something else to the sequence parslet. If it modifies the
        # parslet atom in place, we'll notice:

        sequence >> str("d")
      end

      let!(:chained) { sequence >> str("c") }

      it "is side-effect free" do
        chained.should parse("abc")
        chained.should_not parse("abdc")
      end
    end
  end

  describe "diagnostics" do
    it "does not format the sequence on a successful match" do
      atom = str("a")
      def atom.to_s(*)
        raise "diagnostic formatting should be lazy"
      end

      parser = described_class.new(atom)

      expect(parser.parse("a")).to eq("a")
    end
  end
end
