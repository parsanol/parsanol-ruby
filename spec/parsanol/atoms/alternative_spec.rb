# frozen_string_literal: true

require "spec_helper"

describe Parsanol::Atoms::Alternative do
  include Parsanol

  describe "| shortcut" do
    let(:alternative) { str("a") | str("b") }

    context "when chained with different atoms" do
      before do
        # Chain something else to the alternative parslet. If it modifies the
        # parslet atom in place, we'll notice:

        alternative | str("d")
      end

      let!(:chained) { alternative | str("c") }

      it "is side-effect free" do
        chained.should parse("c")
        chained.should parse("a")
        chained.should_not parse("d")
      end
    end
  end

  describe "diagnostics" do
    it "does not format unused alternatives on a successful match" do
      unused = Object.new
      def unused.inspect
        raise "diagnostic formatting should be lazy"
      end

      parser = described_class.new(str("a"), unused)

      expect(parser.parse("a")).to eq("a")
    end

    it "formats the available alternatives when reporting a failure" do
      parser = described_class.new(str("a"), str("b"))

      expect { parser.parse("c") }
        .to raise_error(Parsanol::ParseFailed, /Expected one of/)
    end
  end
end
