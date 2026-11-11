# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Artifact stored-grammar lane" do
  before do
    # The lane needs the compiled extension; the FFI tier keeps the atom lane.
    unless Parsanol::Native.available? && Parsanol::Native::Parser.extension_loaded?
      skip "native extension unavailable"
    end
  end

  let(:grammar) do
    <<~PARG
      # Comments may use the word use without importing anything.
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

  def atom_lane(env)
    artifact_for(env).tap { |a| a.instance_variable_set(:@stored_grammar_usable, false) }
  end

  def outcome(artifact, input)
    [:ok, artifact.parse("main", input).inspect]
  rescue StandardError => e
    [:error, e.class, e.message]
  end

  it "parses from the stored grammar without rebuilding the atom tree" do
    artifact = artifact_for(envelope)
    expect(artifact.parse("main", "abcd")[:items].to_s).to include("ab")
    expect(artifact.instance_variable_get(:@compiler)).to be_nil
  end

  it "gives the same trees and failures as the atom lane" do
    ["", "ab", "abcd", "cdab", "abX", "X", "abcdc"].each do |input|
      expect(outcome(artifact_for(envelope), input)).to eq(outcome(atom_lane(envelope), input))
    end
  end

  it "answers a refusal through the atom lane" do
    artifact = artifact_for(envelope)
    expect { artifact.parse("main", "abXX") }.to raise_error(Parsanol::ParseFailed, /char 3/)
    expect(artifact.instance_variable_get(:@compiler)).not_to be_nil
  end

  it "re-registers the stored grammar after the native cache is cleared" do
    artifact = artifact_for(envelope)
    artifact.parse("main", "ab")
    Parsanol::Native.clear_cache
    expect(artifact.parse("main", "cd")[:items].to_s).to include("cd")
  end

  # The checksum covers these fields, so each case edits a loaded
  # artifact's envelope instead of constructing a tampered one.
  {
    "another compiler release baked it" => ->(env) { env["compiler_version"] = "0.0.1" },
    "it reads lookup tables" => ->(env) { env["tables"] = { "units" => "sha256:0" } },
    "it declares custom atoms" => ->(env) { env["customs"] = { "c" => "Object" } },
    "it carries runtime state atoms" => ->(env) { env["dynamic"] = true },
    "its source imports another grammar" => ->(env) { env["source"] = "use other\n#{env['source']}" },
  }.each do |reason, change|
    it "keeps the atom lane when #{reason}" do
      artifact = artifact_for(envelope)
      change.call(artifact.envelope)
      expect(artifact.stored_grammar_usable?).to be(false)
    end
  end

  it "ignores the word use inside comments and strings" do
    artifact = artifact_for(envelope)
    artifact.envelope["source"] = "#{artifact.envelope['source']}\n# use other\nx = \"use\"\n"
    expect(artifact.stored_grammar_usable?).to be(true)
  end
end
