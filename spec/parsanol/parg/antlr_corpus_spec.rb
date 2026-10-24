# frozen_string_literal: true

require "parsanol"
require "json"

# ruby#309: the ANTLR importer, scoped v1. Parser rules, lexer rules,
# fragments, literals, char sets, postfixes, groups, alternatives.
# Actions/predicates/labels/options/lexer commands are rejected with
# position and guidance — never silently dropped. Like the ABNF import:
# ANTLR's adaptive LL(*) tolerates ambiguity, PARG's ordered choice is
# decisive, and the compiler's order-dependence lint makes the
# transliteration reviewable.
RSpec.describe "ANTLR importer corpus" do
  def fixture_path(name)
    File.expand_path("../../fixtures/antlr/#{name}", __dir__)
  end

  def imported_parg(name)
    Parsanol::PARG::Import.import(:antlr, File.read(fixture_path(name)))
  end

  def compiled_artifact(fixture, root:, accepts:, rejects:)
    test_block = "  entry corpus: #{root}\n  test corpus {\n"
    accepts.each { |input| test_block << "    accept #{input.inspect}\n" }
    rejects.each { |input| test_block << "    reject #{input.inspect}\n" }
    test_block << "  }\n"
    with_tests = imported_parg(fixture).sub(/\}\s*\z/) { |closing| "#{test_block}#{closing}" }
    document = Parsanol::PARG::Parser.new(with_tests).parse
    result = Parsanol::PARG::Compiler.compile(document)
    artifact = Parsanol::PARG::Artifact.from_json(JSON.generate(result.envelope))
    [artifact, "corpus"]
  end

  describe "the expression grammar" do
    it "imports, compiles, and replays its acceptance set" do
      artifact, entry = compiled_artifact(
        "expr.g4",
        root: "prog",
        accepts: ["1+2*3", "(1+2)*3", "10.5/2"],
        rejects: ["+1", "1+", "1..2"],
      )
      accepts = ["1+2*3", "(1+2)*3", "10.5/2"]
      accepts.each do |input|
        expect { artifact.parse(entry, input) }.not_to raise_error, input.inspect
      end
    end
  end

  describe "the json grammar" do
    it "imports, compiles, and replays its acceptance set" do
      artifact, entry = compiled_artifact(
        "json.g4",
        root: "json",
        accepts: ['{"a":1}', "[true,false,null]", '{"nested":{"x":[1,2]}}', '"bare"', "0", "-1.5e10"],
        rejects: ['{"a":}', "{,}", "[1,]", "tru", '{"a" 1}'],
      )
      accepts = ["{\"a\":1}", "[true,false,null]", "{\"nested\":{\"x\":[1,2]}}", "\"bare\"", "0", "-1.5e10"]
      rejects = ["{\"a\":}", "{,}", "[1,]", "tru", "{\"a\" 1}"]
      accepts.each { |input| expect { artifact.parse(entry, input) }.not_to raise_error, input.inspect }
      rejects.each { |input| expect { artifact.parse(entry, input) }.to raise_error(Parsanol::ParseFailed), input.inspect }
    end
  end

  describe "the select grammar" do
    it "imports, compiles, and replays its acceptance set" do
      artifact, entry = compiled_artifact(
        "select.g4",
        root: "query",
        accepts: ["select * from t;", "SELECT a,b FROM t2 WHERE c"],
        rejects: ["select *", "update t set x=1", "select ;"],
      )
      accepts = ["select * from t;", "SELECT a,b FROM t2 WHERE c"]
      accepts.each { |input| expect { artifact.parse(entry, input) }.not_to raise_error, input.inspect }
    end
  end

  describe "the props grammar" do
    it "imports, compiles, and replays its acceptance set" do
      artifact, entry = compiled_artifact(
        "props.g4",
        root: "file",
        accepts: ["a=1", "key:value", "# comment", "a=1#trailing"],
        rejects: ["= novalue", "=:"],
      )
      accepts = ["a=1", "key:value", "# comment", "a=1#trailing"]
      accepts.each { |input| expect { artifact.parse(entry, input) }.not_to raise_error, input.inspect }
    end
  end

  describe "the ini grammar" do
    it "imports, compiles, and replays its acceptance set" do
      artifact, entry = compiled_artifact(
        "ini.g4",
        root: "file",
        # Without the stripped WS lexer rule, whitespace is significant —
        # the import is faithful to what the grammar text says.
        # No newline rule in the fixture: separators stay explicit.
        accepts: ["[core]name=value", "k=v", "; just a comment"],
        rejects: ["= novalue", "[unterminated", "k = v"],
      )
      accepts = ["[core]name=value", "k=v", "; just a comment"]
      accepts.each do |input|
        expect { artifact.parse(entry, input) }.not_to raise_error, input.inspect
      end
    end
  end

  describe "rejections with position and guidance" do
    it "rejects actions and predicates, naming the line" do
      source = "grammar A;\nr: x { someCode } ;\nx: 'a' ;\n"
      expect { Parsanol::PARG::Import.import(:antlr, source) }
        .to raise_error(/action\/predicate.*out of scope.*v1/)
    end

    it "rejects alternative labels" do
      source = "grammar A;\nr: 'a' # altName ;\n"
      expect { Parsanol::PARG::Import.import(:antlr, source) }
        .to raise_error(/alternative labels/)
    end

    it "rejects lexer commands and points at PARG's skip declaration" do
      source = "grammar A;\nWS: [ ] -> skip ;\nr: 'a' ;\n"
      expect { Parsanol::PARG::Import.import(:antlr, source) }
        .to raise_error(/-> "skip".*skip = <rule>/m)
    end

    it "rejects non-greedy quantifiers instead of reading them as greedy" do
      source = "grammar A;\nr: SEMI? ;\nx: (\"a\"*? \"b\")? ;\nSEMI: \";\" ;\n"
      expect { Parsanol::PARG::Import.import(:antlr, source) }
        .to raise_error(/non-greedy quantifier \*\?/)
    end

    it "rejects options sections" do
      source = "grammar A;\noptions { language = Go; }\nr: 'a' ;\n"
      expect { Parsanol::PARG::Import.import(:antlr, source) }
        .to raise_error(/expected ':'|options/)
    end
  end

  describe "import stability" do
    it "compiles the imported text to the same envelope every time" do
      first = imported_parg("expr.g4")
      one = Parsanol::PARG::Compiler.compile(Parsanol::PARG::Parser.new(first).parse)
      two = Parsanol::PARG::Compiler.compile(Parsanol::PARG::Parser.new(first).parse)
      expect(JSON.generate(one.envelope)).to eq(JSON.generate(two.envelope))
    end
  end
end
