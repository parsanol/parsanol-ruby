# frozen_string_literal: true

require "parsanol"

RSpec.describe Parsanol::PARG::SelfHost do
  let(:artifact_dir) { ENV.fetch("PARG_ARTIFACT_DIR", "../../../pubid/pubid-grammar/artifacts") }

  before do
    skip "parg artifact not available" unless described_class.available?
  end

  it "validates a real grammar under the self-hosting artifact" do
    source = File.read(File.expand_path(
                         "../../../../../pubid/pubid-grammar/grammars/parg.parg", __dir__
                       ))
    expect(described_class.valid?(source)).to be(true)
  end

  it "rejects source the PARG language cannot parse" do
    expect(described_class.valid?("%%% not parg %%%")).to be(false)
  end

  it "exposes the structured shape for valid source" do
    shape = described_class.validate("grammar T version \"1\" {\nx = %x30-39\n}\n")
    expect(shape).to be_truthy
  end
end
