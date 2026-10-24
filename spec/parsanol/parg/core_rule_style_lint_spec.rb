# frozen_string_literal: true

require "parsanol"
require "json"

# ruby#307 (partial): the lints that ride the core rules (T1) and the
# brace form (T2). Both are migration guidance — warnings, never
# errors, because the constructs they flag are legal by design.
RSpec.describe "PARG core-rule style lints" do
  def warnings_for(source)
    document = Parsanol::PARG::Parser.new(source).parse
    Parsanol::PARG::Compiler.compile(document).warnings
  end

  it "warns when a rule shadows an RFC 5234 core rule" do
    source = <<~PARG
      grammar Shadow version "1.0.0" {
        DIGIT = "7"
        code = 2DIGIT
        entry main: code
      }
    PARG
    expect(warnings_for(source)).to include(/shadows the RFC 5234 core rule/)
  end

  it "stays silent when the prelude is used without shadowing" do
    source = <<~PARG
      grammar Core version "1.0.0" {
        code = 2DIGIT SP
        entry main: code
      }
    PARG
    expect(warnings_for(source)).not_to include(/shadows the RFC 5234 core rule/)
  end

  it "warns when a grammar mixes brace and line bodies" do
    source = <<~PARG
      grammar Mix version "1.0.0" {
        braced = { "a" }
        line = "b"
        other = "c"
        more = "d"
        entry document: braced
      }
    PARG
    expect(warnings_for(source)).to include(/mixes brace .* and line .* rule bodies/)
  end

  it "stays silent on a single-style grammar" do
    source = <<~PARG
      grammar Pure version "1.0.0" {
        line = "b"
        other = "c"
        more = "d"
        entry document: line
      }
    PARG
    expect(warnings_for(source)).not_to include(/mixes brace/)
  end

  it "does not warn on small grammars that happen to mix" do
    source = <<~PARG
      grammar Tiny version "1.0.0" {
        braced = { "a" }
        line = "b"
        entry document: braced
      }
    PARG
    expect(warnings_for(source)).not_to include(/mixes brace/)
  end
end
