# frozen_string_literal: true

require "parsanol"

# U3 (rs#297): general-category classes. %p{L} compiles to the regex
# category class; both engines carry the tables, the fixtures pin the
# agreement. Misspellings fail the compile naming the code.
RSpec.describe "PARG general-category classes" do
  def compile_source(source)
    Parsanol::PARG::Compiler.compile(Parsanol::PARG::Parser.new(source).parse)
  end

  it "compiles %p{L} and matches letters across scripts" do
    source = <<~PARG
      grammar Cat version "1.0.0" {
        entry main: word
        word = 1*%p{L} as word
        test main {
          accept "日本語"
          accept "café"
          accept "ДОН"
          reject "1x"
          reject "-"
        }
      }
    PARG
    compile_source(source)
  end

  it "compiles two-letter categories" do
    source = <<~PARG
      grammar Cat version "1.0.0" {
        entry main: num
        num = 1*%p{Nd} as num
        test main {
          accept "٠١٢"
          accept "012"
          reject "a1"
        }
      }
    PARG
    compile_source(source)
  end

  it "fails the compile on an unknown category, naming the code" do
    source = <<~PARG
      grammar Cat version "1.0.0" {
        entry main: word
        word = 1*%p{Qq} as word
      }
    PARG
    expect { compile_source(source) }
      .to raise_error(Parsanol::PARG::CompileError, /%p\{Qq\}/)
  end
end
