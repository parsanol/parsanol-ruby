# frozen_string_literal: true

require "parsanol"
require "json"

# parsanol-ruby#414: the grammar's test block accepts `bind "input" { ... }`
# — an EXACT-match assertion on the bound map (the partial sibling of
# `example`). The assertion fails when the input stops parsing or the
# bindings produce a different map, so binding correctness is
# declarable in-language instead of being whatever the current engine
# happens to emit (the #408/#412 lesson).
RSpec.describe "bind assertions in the test block" do
  let(:source) do
    <<~PARG
      grammar Binds version "1.0.0" edition 2 {
        word = 1*( %x41-5A / %x61-7A )
        digit = 1*( %x30-39 )
        plus = "+"
        pub = ( word ) as publisher
        cop = ( plus ( word ) as copublisher )
        num = ( digit ) as number
        item = ( pub / cop / num )
        identifier = 1*( item )
        entry identifier: identifier
        bindings identifier {
          copublisher -> items[].copublisher (string)
        }
        test {
          accept "IEC+ISO1234"
          bind "IEC+ISO1234" { items: [{ copublisher: "ISO" }] }
          bind "IEC1234" {}
        }
      }
    PARG
  end

  let(:artifact) do
    envelope = Parsanol::PARG::Compiler.compile(Parsanol::PARG::Parser.new(source).parse).envelope
    Parsanol::PARG::Artifact.from_json(JSON.generate(envelope))
  end

  it "compiles the bind rows into the envelope tests" do
    binds = artifact.envelope["tests"].select { |t| t["kind"] == "bind" }
    expect(binds.length).to eq(2)
    expect(binds.first).to include("input" => "IEC+ISO1234", "kind" => "bind")
    expect(binds.first["expect"]).to eq("items" => [{ "copublisher" => "ISO" }])
    expect(binds.last["expect"]).to eq({})
  end

  it "passes when the bindings produce the asserted map" do
    expect(artifact.run_tests(mode: :ruby)).to be_empty
  end

  it "fails when the bound map differs" do
    altered = artifact.envelope.dup
    altered["tests"] = altered["tests"].map do |t|
      if t["kind"] == "bind" && t["input"] == "IEC+ISO1234"
        t.merge("expect" => { "items" => [{ "copublisher" => "XX" }] })
      else
        t
      end
    end
    expect(artifact.run_test_list(altered["tests"], mode: :ruby).join)
      .to include("expected bound")
  end

  it "fails when the asserted input stops parsing" do
    altered = artifact.envelope.dup
    altered["tests"] = altered["tests"].map do |t|
      if t["kind"] == "bind"
        t.merge("input" => "???")
      else
        t
      end
    end
    expect(artifact.run_test_list(altered["tests"], mode: :ruby).join)
      .to include("expected the input to parse")
  end
end
