# frozen_string_literal: true

require "spec_helper"
require "json"

# PR #350 made "v2" the default capture dialect, but Artifact#compiler
# re-parses the embedded source, so an envelope baked before 1.3.110
# (no "mode" key) was recompiled as v2: uncaptured rule references inside
# a capture became named subtrees and `-2` lost its single-slice shape
# (asciiunits' `m*s^-2`). An envelope without "mode" predates the key and
# must keep compiling as v1.
RSpec.describe "PARG Artifact capture mode of baked envelopes" do
  let(:source) do
    <<~PARG
      grammar Legacy version "1.0" {
        digit = %x30-39
        sign = "-"
        num = [sign] 1*digit
        integer = num as integer
        entry integer: integer
      }
    PARG
  end

  def envelope_with_mode(mode)
    document = Parsanol::PARG::Parser.new(source).parse
    envelope = JSON.parse(JSON.generate(Parsanol::PARG::Compiler.compile(document).envelope))
    mode.nil? ? envelope.delete("mode") : envelope["mode"] = mode
    envelope["checksum"] = Parsanol::PARG::Compiler.checksum(envelope)
    Parsanol::PARG::Artifact.from_json(JSON.generate(envelope))
  end

  # The engines differ in key type (Symbol vs String) for named rule
  # references; compare on strings so one expectation covers both.
  def normalize(tree)
    case tree
    when Hash then tree.to_h { |key, value| [key.to_s, normalize(value)] }
    when Array then tree.map { |value| normalize(value) }
    else tree.to_s
    end
  end

  engines = [:ruby]
  engines.unshift(:native) if Parsanol::Native.available?

  engines.each do |engine|
    context "with the #{engine} engine" do
      it "compiles an envelope without a mode key as v1" do
        tree = envelope_with_mode(nil).parse("integer", "-2", mode: engine)
        expect(normalize(tree)).to eq("integer" => "-2")
      end

      it "keeps v2 output for an envelope that records mode v2" do
        tree = envelope_with_mode("v2").parse("integer", "-2", mode: engine)
        expect(normalize(tree))
          .to eq("integer" => [{ "sign" => "-" }, { "digit" => "2" }])
      end

      it "keeps v1 output for an envelope that records mode v1" do
        tree = envelope_with_mode("v1").parse("integer", "-2", mode: engine)
        expect(normalize(tree)).to eq("integer" => "-2")
      end
    end
  end
end
