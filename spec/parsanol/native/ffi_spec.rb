# frozen_string_literal: true

require "spec_helper"

RSpec.describe Parsanol::Native::Ffi, :native do
  describe "availability" do
    it "reports a boolean" do
      expect(described_class.available?).to be(true).or be(false)
    end
  end

  describe "parse" do
    let(:grammar) { Parsanol.str("ab").as(:greeting) }

    it "parses through the cdylib with position info", if: described_class.available? do
      expect(described_class.parse(grammar, "ab"))
        .to eq(greeting: Parsanol::Slice.new(0, "ab", "ab"))
    end

    it "raises a parslet-compatible error for unparseable input", if: described_class.available? do
      expect { described_class.parse(grammar, "zz") }
        .to raise_error(Parsanol::ParseFailed)
    end

    it "reuses the registered handle across parses", if: described_class.available? do
      3.times { described_class.parse(grammar, "ab") }
      expect(described_class.parse(grammar, "ab")[:greeting].to_s).to eq("ab")
    end

    it "matches the extension tier tree",
       if: described_class.available? && Parsanol::Native::Parser.extension_loaded? do
      atom = Parsanol.match("[a-z]").repeat(1).as(:w)
      expect(described_class.parse(atom, "hey"))
        .to eq(Parsanol::Native.parse(atom, "hey"))
    end
  end
end
