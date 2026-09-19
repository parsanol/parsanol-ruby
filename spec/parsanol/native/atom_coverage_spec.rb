# frozen_string_literal: true

require "spec_helper"

class NativeCutParser < Parsanol::Parser
  root(:w)
  rule(:w) { str("a").cut >> str("b") }
end

# TODO.perf/8 item 4: atoms the Rust backend cannot express are rejected
# at registration with a clear error, never planted as never-matching
# placeholders that explode mid-parse.
RSpec.describe "atom coverage audit", :native do
  describe "Ignored atoms" do
    it "serialize and parse natively (value discarded)" do
      atom = Parsanol.str("x").ignore >> Parsanol.str("y").as(:v)
      expect(Parsanol::Native.parse(atom, "xy"))
        .to eq(v: Parsanol::Slice.new(1, "y", "xy"))
    end
  end

  describe "unsupported atoms" do
    it "fails Cut at registration with a clear error" do
      expect { Parsanol::Native.parse(Parsanol.str("a").cut, "a") }
        .to raise_error(Parsanol::Native::UnsupportedGrammar, /Cut/)
    end

    it "fails Infix at registration with a clear error" do
      infix = Parsanol.infix_expression(
        Parsanol.match("[a-z]").repeat(1),
        Parsanol.str("+") >> Parsanol.match("[a-z]").repeat(1),
      )
      expect { Parsanol::Native.parse(infix, "ab") }
        .to raise_error(Parsanol::Native::UnsupportedGrammar, /Infix/)
    end

    it "explicit mode: :native raises the same error" do
      expect { NativeCutParser.new.parse("ab", mode: :native) }
        .to raise_error(Parsanol::Native::UnsupportedGrammar, /Cut/)
    end
  end

  describe "default-mode engine selection" do
    it "runs unserializable grammars on the Ruby engine, warning once" do
      begin
        Parsanol::Parser.class_variable_set(:@@unsupported_warned, {})
      rescue NameError
        nil
      end

      expect do
        expect(NativeCutParser.new.parse("ab")).to eq("ab")
      end.to output(/Ruby engine.*Cut/).to_stderr

      expect do
        2.times { NativeCutParser.new.parse("ab") }
      end.not_to output.to_stderr
    end
  end
end
