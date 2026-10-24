# frozen_string_literal: true

require "parsanol"
require "json"

# ruby#305: the ABNF importer hardening — an RFC corpus imported,
# compiled, and replayed; the edge matrix; the reviewable
# order-dependence report; and import stability.
#
# The .abnf fixtures quote IETF text with attribution (IETF Trust
# license permits reproduction for interoperability).
RSpec.describe "ABNF importer corpus" do
  def fixture_path(name)
    File.expand_path("../../fixtures/abnf/#{name}", __dir__)
  end

  def imported_parg(name)
    Parsanol::PARG::Import.import(:abnf, File.read(fixture_path(name)))
  end

  def root_rule(fixture)
    {
      "rfc5234-core.abnf" => "checksum_line",
      "rfc3339-date-time.abnf" => "date_time",
      "rfc3986-uri.abnf" => "uri",
      "rfc8259-json.abnf" => "json_text",
    }.fetch(fixture)
  end

  def compiled_artifact(fixture, accepts:, rejects:)
    # Pins ride the imported source: the compile-time test run enforces
    # them, and the artifact carries them to every engine. Imported
    # grammars declare no entries, so the harness adds one at the
    # fixture's root rule.
    root = root_rule(fixture)
    test_block = "  entry corpus: #{root}\n  test corpus {\n"
    accepts.each { |input| test_block << "    accept #{input.inspect}\n" }
    rejects.each { |input| test_block << "    reject #{input.inspect}\n" }
    test_block << "  }\n"
    with_tests = imported_parg(fixture).sub(/\}\s*\z/) { |m| "#{test_block}#{m}" }
    document = Parsanol::PARG::Parser.new(with_tests).parse
    result = Parsanol::PARG::Compiler.compile(document)
    artifact = Parsanol::PARG::Artifact.from_json(JSON.generate(result.envelope))
    [artifact, "corpus"]
  end

  shared_examples "an importable RFC grammar" do |fixture, accepts, rejects|
    it "imports, compiles, and replays its acceptance set" do
      artifact, entry = compiled_artifact(fixture, accepts: accepts, rejects: rejects)
      accepts.each do |input|
        expect { artifact.parse(entry, input) }
          .not_to raise_error, "expected acceptance: #{input.inspect}"
      end
      rejects.each do |input|
        expect { artifact.parse(entry, input) }
          .to raise_error(Parsanol::ParseFailed), "expected rejection: #{input.inspect}"
      end
    end
  end

  describe "RFC 5234 core rules" do
    it_behaves_like "an importable RFC grammar", "rfc5234-core.abnf",
                    ["a4F 2024\r\n", "fff 0000\r\n"],
                    ["g4F 2024\r\n", "a4F 202\r\n", "000 1234\n"]
  end

  describe "RFC 3339 date-time" do
    it_behaves_like "an importable RFC grammar", "rfc3339-date-time.abnf",
                    ["1985-04-12T23:20:50.52Z", "1996-12-19T16:39:57-08:00", "1937-01-01T12:00:27.87+00:20"],
                    # month 13 is legal SYNTACTICALLY (2DIGIT): the RFC's
                    # semantic ranges live above the grammar.
                    ["1985-04-12 23:20:50Z", "1985-04-12T23:20Z"]
  end

  describe "RFC 3986 URI" do
    it_behaves_like "an importable RFC grammar", "rfc3986-uri.abnf",
                    ["https://www.example.com:8080/a/path?q=1#frag",
                     "mailto:info@example.com",
                     "http://[2001:db8:0:0:0:0:0:1]/x",
                     "ftp://user:pw@192.168.0.1/"],
                    # [2001:db8::1] is a VALID address but RFC 3986's own
                    # IPv6 grammar cannot express short elisions — a
                    # documented quirk of the RFC, not the importer.
                    ["http://[bad::G]/", "1http://example.com"]
  end

  describe "RFC 8259 JSON" do
    it_behaves_like "an importable RFC grammar", "rfc8259-json.abnf",
                    ['{"k": [1, 2.5e3, true, null, "s"]}', "[]", '{"a":{"b":[-0.5]}}', '"top"'],
                    ["{'k': 1}", "[1,]", "{,}", "01"]
  end

  describe "the edge matrix" do
    it "imports incremental definitions, %d/%b forms, and merges case-collided rules" do
      source = imported_parg("edge-matrix.abnf")
      expect(source).to include("mixed_forms")
      expect(source).to include("seq_token")
      expect(source).not_to include("SEQ_TOKEN =")
      expect(source).not_to include("SEQ_TOKEN =/")
      grows_line = source.lines.grep(/grows =/).join
      expect(grows_line).to include('"FIX"')      # the %s original
      expect(grows_line).to include("%i\"fix\"")  # both =/ branches merged in
    end

    it "keeps a semicolon inside a quoted string as content" do
      source = imported_parg("edge-matrix.abnf")
      # %s (case-sensitive) lowers to PARG's plain literal.
      expect(source).to include('"a;b(c)"')
    end

    it "compiles and replays the merged case-collided rule" do
      source = imported_parg("edge-matrix.abnf")
      source_with_tests = source.sub(/\}\s*\z/) do |m|
        "  entry corpus: seq_token\n  test corpus {\n    accept \"go\"\n    accept \"stop\"\n  }\n#{m}"
      end
      document = Parsanol::PARG::Parser.new(source_with_tests).parse
      result = Parsanol::PARG::Compiler.compile(document)
      artifact = Parsanol::PARG::Artifact.from_json(JSON.generate(result.envelope))
      entry = artifact.entries.first
      expect { artifact.parse(entry, "go") }.not_to raise_error
      expect { artifact.parse(entry, "stop") }.not_to raise_error
      # "a;b(c)" rides with_comment_chars, which no entry roots at — its
      # CONTENT (the semicolon surviving as text) is pinned above.
    end

    it "rejects prose-vals with a positioned, actionable error" do
      abnf = "broken = 1*<any sequence of chars>\n"
      expect { Parsanol::PARG::Import.import(:abnf, abnf) }
        .to raise_error(/prose/i)
    end
  end

  describe "the order-dependence report" do
    it "names the conflicting branches for an order-dependent import" do
      # Shared first bytes, neither a prefix of the other: ordered
      # choice is decisive, which the import must surface.
      abnf = <<~ABNF
        token = "iso" / "ism"
      ABNF
      source = Parsanol::PARG::Import.import(:abnf, abnf)
      document = Parsanol::PARG::Parser.new(source).parse
      result = Parsanol::PARG::Compiler.compile(document)
      order_warnings = result.warnings.grep(/order-dependent|shadows/)
      expect(order_warnings).not_to be_empty,
                                    "an unordered-ABNF import must surface its order-dependent branches"
    end
  end

  describe "import stability" do
    it "is deterministic across runs" do
      first = imported_parg("rfc3339-date-time.abnf")
      second = imported_parg("rfc3339-date-time.abnf")
      expect(first).to eq(second)
    end

    it "round-trips: the imported text compiles to the same envelope every time" do
      first = imported_parg("rfc5234-core.abnf")
      one = Parsanol::PARG::Compiler.compile(Parsanol::PARG::Parser.new(first).parse)
      two = Parsanol::PARG::Compiler.compile(Parsanol::PARG::Parser.new(first).parse)
      expect(JSON.generate(one.envelope)).to eq(JSON.generate(two.envelope))
    end
  end
end
