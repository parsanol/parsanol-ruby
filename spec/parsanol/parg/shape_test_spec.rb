# frozen_string_literal: true

require "spec_helper"

# `shape` is the whole-tree test phase: it compares the canonical flattened
# parse tree, which is the only phase that can observe repetition flattening
# (V3) and sequence merge laws (V1).
RSpec.describe "PARG shape tests" do
  def compile(source)
    document = Parsanol::PARG::Parser.new(source).parse
    Parsanol::PARG::Compiler.compile(document)
  end

  let(:source) do
    <<~PARG
      grammar ShapeDemo version "1.0.0" {
        main = ( 1*( "a" as x ) ) ( "b" as y )

        entry main: main

        test main {
          shape "aab" [ { x: "a" }, { x: "a" }, { y: "b" } ]
          shape "ab" [ { x: "a" }, { y: "b" } ]
        }
      }
    PARG
  end

  it "accepts the canonical whole tree" do
    expect { compile(source) }.not_to raise_error
  end

  it "reports a shape mismatch with the canonical trees" do
    bad = source.sub(
      %(shape "aab" [ { x: "a" }, { x: "a" }, { y: "b" } ]),
      %(shape "aab" [ { x: "a" }, { y: "b" } ]),
    )
    expect { compile(bad) }.to raise_error(
      Parsanol::PARG::CompileError, /expected shape .*got/
    )
  end

  it "keeps the expectation as a bare value in the envelope" do
    envelope = compile(source).envelope
    shape_tests = envelope["tests"].select { |test| test["kind"] == "shape" }
    expect(shape_tests.first["expect"]).to eq(
      [{ "x" => "a" }, { "x" => "a" }, { "y" => "b" }],
    )
  end
end
