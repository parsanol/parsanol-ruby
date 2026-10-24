# frozen_string_literal: true

require "parsanol"

# ruby#307 B5: case-ambiguity. A case-insensitive literal shadows a
# later case-equal literal outright, and a later case-insensitive
# case-equal literal is its duplicate — both dead branches, both
# build failures like the prefix shadow they are.
RSpec.describe "PARG case ambiguity lint" do
  def compile_source(source)
    Parsanol::PARG::Compiler.compile(Parsanol::PARG::Parser.new(source).parse)
  end

  it "fails when a case-insensitive branch shadows a case-equal literal" do
    source = <<~PARG
      grammar Demo version "1.0.0" {
        tag = %i"iso" / "ISO"
        entry document: tag
      }
    PARG
    expect { compile_source(source) }
      .to raise_error(Parsanol::PARG::CompileError, /"ISO".*case-insensitive.*every casing/m)
  end

  it "fails when two case-insensitive branches are case-equal" do
    source = <<~PARG
      grammar Demo version "1.0.0" {
        tag = %i"iso" / %i"ISO"
        entry document: tag
      }
    PARG
    expect { compile_source(source) }
      .to raise_error(Parsanol::PARG::CompileError, /can never match/)
  end

  it "stays silent when only the later branch is case-insensitive" do
    source = <<~PARG
      grammar Demo version "1.0.0" {
        tag = "ISO" / %i"iso" / %i"ieee"
        entry document: tag
      }
    PARG
    compile_source(source)
  end

  it "stays silent for case-differing case-sensitive literals" do
    source = <<~PARG
      grammar Demo version "1.0.0" {
        tag = "iso" / "ISO"
        entry document: tag
      }
    PARG
    compile_source(source)
  end
end
