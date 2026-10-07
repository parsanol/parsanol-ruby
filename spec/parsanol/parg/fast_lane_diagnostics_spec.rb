# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Artifact native fast-lane diagnostics (rs#162/#171)" do
  let(:grammar) do
    <<~PARG
      grammar T version "1.0.0" {
        main = ( *( item ) ) as items
        item = "ab" / "cd"
      }
      entry main: main
    PARG
  end

  let(:artifact) do
    document = Parsanol::PARG::Parser.new(grammar).parse
    Parsanol::PARG::Artifact.new(
      Parsanol::PARG::Compiler.compile(document).envelope, nil, nil
    )
  end

  it "keeps the fast lane on success" do
    items = artifact.parse("main", "abcd")[:items]
    expect(items.to_s).to include("ab")
  end

  it "reports the deepest failure position, not the entry root" do
    expect { artifact.parse("main", "abXX") }
      .to raise_error(Parsanol::ParseFailed, /char 3/)
  end
end
