# frozen_string_literal: true

require "parsanol"

RSpec.describe Parsanol::PARG::SelfHost do
  let(:artifact_dir) { ENV.fetch("PARG_ARTIFACT_DIR", "../../../pubid/pubid-grammar/artifacts") }

  before do
    skip "parg artifact not available" unless described_class.available?
  end

  it "validates a real grammar under the self-hosting artifact" do
    # The self-description grammar lives next to the artifact the lib
    # already located (the same pubid-grammar checkout), so the source
    # resolves from artifact_path rather than a checkout-layout guess.
    artifact_path = described_class.artifact_path
    source = File.read(File.join(File.dirname(artifact_path), "..", "grammars", "parg.parg"))
    expect(described_class.valid?(source)).to be(true)
  end

  it "rejects source the PARG language cannot parse" do
    expect(described_class.valid?("%%% not parg %%%")).to be(false)
  end

  it "validates brace-form rule bodies (the A3 gate)" do
    brace_source = <<~PARG
      grammar T version "1" edition "v1" {
        ## Publisher code: case-insensitive tag; raw input is captured.
        publisher = {
          %i"iso" / %i"ieee"
        }
      }
    PARG
    expect(described_class.valid?(brace_source)).to be(true)
  end

  it "exposes the structured shape for valid source" do
    shape = described_class.validate("grammar T version \"1\" {\nx = %x30-39\n}\n")
    expect(shape).to be_truthy
  end
end
