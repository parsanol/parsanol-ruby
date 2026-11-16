# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Artifact diagnostics policy (ruby#520)" do
  let(:grammar) do
    <<~PARG
      grammar T version "1.0.0" {
        main = ( *( item ) ) as items
        item = ( "ab" / "cd" ) as item
      }
      entry main: main
    PARG
  end

  let(:envelope) do
    Parsanol::PARG::Compiler.compile(Parsanol::PARG::Parser.new(grammar).parse).envelope
  end

  def artifact_for(env)
    Parsanol::PARG::Artifact.new(env, nil, nil)
  end

  def outcome(artifact, input, **options)
    [:ok, artifact.parse("main", input, **options).inspect]
  rescue StandardError => e
    [:error, e.class, e.message]
  end

  it "rejects an unknown policy" do
    expect { artifact_for(envelope).parse("main", "ab", diagnostics_policy: :fast) }
      .to raise_error(ArgumentError, /diagnostics policy must be :legacy or :pending/)
  end

  it "gives identical outcomes under both policies on the stored lane" do
    inputs = ["", "ab", "abcd", "cdab", "abX", "X", "abcdc"]
    inputs.each do |input|
      legacy = outcome(artifact_for(envelope), input, diagnostics_policy: :legacy)
      pending = outcome(artifact_for(envelope), input, diagnostics_policy: :pending)
      expect(pending).to eq(legacy)
    end
  end

  it "gives identical outcomes under both policies on the atom lane" do
    atom = artifact_for(envelope)
    atom.envelope["compiler_version"] = "0.0.1"
    inputs = ["", "ab", "abcd", "cdab", "abX", "X", "abcdc"]
    inputs.each do |input|
      expect(outcome(atom, input, diagnostics_policy: :pending))
        .to eq(outcome(atom, input, diagnostics_policy: :legacy))
    end
  end

  it "reports the deepest failure position with the pending policy" do
    expect { artifact_for(envelope).parse("main", "abXX", diagnostics_policy: :pending) }
      .to raise_error(Parsanol::ParseFailed, /char 3/)
  end

  it "parses in ruby mode with the policy set (no native surface there)" do
    shape = artifact_for(envelope).parse("main", "abcd", mode: :ruby, diagnostics_policy: :pending)
    expect(shape[:items].to_s).to include("ab")
  end
end
