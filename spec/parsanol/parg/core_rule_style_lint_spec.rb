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

  it "warns when the grammar ships without a test section" do
    source = <<~PARG
      grammar Bare version "1.0.0" {
        code = "ok"
        entry main: code
      }
    PARG
    expect(warnings_for(source)).to include(/ships without a test section/)
  end

  it "stays silent about pins when tests exist" do
    source = <<~PARG
      grammar Pinned version "1.0.0" {
        code = "ok"
        entry main: code
        test main {
          accept "ok"
        }
      }
    PARG
    expect(warnings_for(source)).not_to include(/ships without a test section/)
  end

  it "warns when an entry-reachable rule has no doc comment" do
    source = <<~PARG
      grammar Undoc version "1.0.0" {
        ## The documented root.
        root_rule = inner "!"
        inner = "x"
        entry main: root_rule
      }
    PARG
    expect(warnings_for(source)).to include(/rule inner: entry-reachable without a ## doc comment/)
    expect(warnings_for(source)).not_to include(/rule root_rule:/)
  end

  it "does not flag injected core rules or tier rules as undocumented" do
    source = <<~PARG
      grammar Prelude version "1.0.0" {
        hex = 2HEXDIG
        entry main: hex
      }
    PARG
    # HEXDIG is served by the builtin classes (no rule node); a grammar
    # whose reachable set includes an INJECTED rule (CRLF/LWSP) must
    # not gain an undocumented warning for it.
    source_lwsp = <<~PARG
      grammar Lwsp version "1.0.0" {
        ## The documented rule.
        gap = "a" LWSP "b"
        entry main: gap
      }
    PARG
    expect(warnings_for(source)).not_to include(/undocumented/)
    expect(warnings_for(source_lwsp)).not_to include(/rule CRLF:/)
    expect(warnings_for(source_lwsp)).not_to include(/rule WSP:/)
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
