# frozen_string_literal: true

require "spec_helper"
require "json"
require "stringio"
require "tmpdir"
require "fileutils"

RSpec.describe Parsanol::PARG::Lsp do
  def frame(payload)
    body = JSON.generate(payload)
    "Content-Length: #{body.bytesize}\r\n\r\n#{body}"
  end

  def request(id, method, params = {})
    frame("jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params)
  end

  def notify(method, params)
    frame("jsonrpc" => "2.0", "method" => method, "params" => params)
  end

  def open_document(uri, text)
    notify("textDocument/didOpen",
           "textDocument" => { "uri" => uri, "languageId" => "parg",
                               "version" => 1, "text" => text })
  end

  # Run the server over framed stdio and return the decoded responses.
  def run_lsp(frames)
    input = StringIO.new(frames.join)
    output = StringIO.new
    described_class.new(input, output).run
    decode_messages(output.string)
  end

  def decode_messages(raw)
    messages = []
    until raw.empty?
      header, rest = raw.split("\r\n\r\n", 2)
      raise "malformed LSP output: #{raw[0, 80].inspect}" unless rest

      length = header[/Content-Length: (\d+)/i, 1].to_i
      body = rest.byteslice(0, length)
      messages << JSON.parse(body)
      raw = rest.byteslice(length..) || ""
    end
    messages
  end

  def response(messages, id)
    messages.find { |message| message["id"] == id }
  end

  def diagnostics_for(messages, uri)
    messages.select do |message|
      message["method"] == "textDocument/publishDiagnostics" &&
        message.dig("params", "uri") == uri
    end.flat_map { |message| message.dig("params", "diagnostics") }
  end

  let(:grammar) do
    <<~PARG
      grammar Demo version "1.0.0" {
        ## The publisher vocabulary.
        publisher = %i"iso" / %i"ieee"
        ## A whole identifier.
        identifier = publisher " " 1*%x30-39 as number

        entry identifier: identifier
      }
    PARG
  end

  it "advertises the full feature set on initialize" do
    messages = run_lsp([request(1, "initialize", {})])
    capabilities = response(messages, 1).dig("result", "capabilities")

    expect(capabilities["hoverProvider"]).to be(true)
    expect(capabilities["definitionProvider"]).to be(true)
    expect(capabilities["referencesProvider"]).to be(true)
    expect(capabilities["codeActionProvider"]).to be(true)
    expect(capabilities["completionProvider"]["triggerCharacters"]).to include(".")
    expect(capabilities["semanticTokensProvider"]["full"]).to be(true)
  end

  it "publishes no diagnostics for a valid grammar" do
    uri = "file:///tmp/lsp-valid.parg"
    messages = run_lsp([open_document(uri, grammar)])
    expect(diagnostics_for(messages, uri)).to be_empty
  end

  it "publishes a diagnostic for a parse error" do
    uri = "file:///tmp/lsp-broken.parg"
    messages = run_lsp([open_document(uri, "grammar Broken { main = ( }\n")])
    expect(diagnostics_for(messages, uri).length).to eq(1)
    expect(diagnostics_for(messages, uri).first["message"]).not_to be_empty
  end

  it "hovers a rule reference with its doc comment" do
    uri = "file:///tmp/lsp-hover.parg"
    # `publisher` on the identifier line (line 4, inside the reference).
    messages = run_lsp([
                         open_document(uri, grammar),
                         request(2, "textDocument/hover",
                                 "textDocument" => { "uri" => uri },
                                 "position" => { "line" => 4, "character" => 17 }),
                       ])
    value = response(messages, 2).dig("result", "contents", "value")

    expect(value).to include("`publisher`")
    expect(value).to include("The publisher vocabulary.")
  end

  it "jumps to a rule definition" do
    uri = "file:///tmp/lsp-def.parg"
    messages = run_lsp([
                         open_document(uri, grammar),
                         request(2, "textDocument/definition",
                                 "textDocument" => { "uri" => uri },
                                 "position" => { "line" => 4, "character" => 17 }),
                       ])
    location = response(messages, 2)["result"]

    expect(location["uri"]).to eq(uri)
    expect(location.dig("range", "start", "line")).to eq(2)
    expect(location.dig("range", "start", "character")).to eq(2)
  end

  it "finds all references including the declaration" do
    uri = "file:///tmp/lsp-refs.parg"
    messages = run_lsp([
                         open_document(uri, grammar),
                         request(2, "textDocument/references",
                                 "textDocument" => { "uri" => uri },
                                 "position" => { "line" => 4, "character" => 17 },
                                 "context" => { "includeDeclaration" => true }),
                       ])
    locations = response(messages, 2)["result"]

    expect(locations.length).to eq(2)
    expect(locations.map { |l| l.dig("range", "start", "line") }).to contain_exactly(2, 4)
  end

  it "completes keywords, rule names, and snippets" do
    uri = "file:///tmp/lsp-complete.parg"
    messages = run_lsp([
                         open_document(uri, grammar),
                         request(2, "textDocument/completion",
                                 "textDocument" => { "uri" => uri },
                                 "position" => { "line" => 4, "character" => 4 }),
                       ])
    items = response(messages, 2).dig("result", "items")
    labels = items.map { |item| item["label"] }

    expect(labels).to include("grammar", "entry", "publisher", "identifier")
    expect(labels).to include("%i\"...\"", "%x41-5A", "*( ... )")
    expect(items.find { |item| item["label"] == "%i\"...\"" }["insertTextFormat"]).to eq(2)
  end

  it "emits semantic tokens for rules, captures, keywords, strings, and comments" do
    uri = "file:///tmp/lsp-tokens.parg"
    messages = run_lsp([
                         open_document(uri, grammar),
                         request(2, "textDocument/semanticTokens/full",
                                 "textDocument" => { "uri" => uri }),
                       ])
    data = response(messages, 2).dig("result", "data")
    decoded = decode_tokens(data, grammar)

    types = Parsanol::PARG::Lsp::SEMANTIC_TYPES
    keyword = decoded.find { |token| token[:type] == "keyword" }
    declaration = decoded.find do |token|
      token[:type] == "rule" && token[:modifiers] == Parsanol::PARG::Lsp::DECLARATION_BIT
    end
    capture = decoded.find { |token| token[:type] == "capture" }
    string = decoded.find { |token| token[:type] == "string" }
    comment = decoded.find { |token| token[:type] == "comment" }

    expect(types).to include(keyword[:type], declaration[:type], capture[:type])
    expect(string).not_to be_nil
    expect(comment).not_to be_nil
    expect(capture[:text]).to eq("number")
  end

  def decode_tokens(data, source)
    lines = source.lines
    tokens = []
    line = 0
    character = 0
    data.each_slice(5) do |delta_line, delta_char, length, type, modifiers|
      line += delta_line
      character = delta_line.zero? ? character + delta_char : delta_char
      tokens << { line: line, character: character, length: length,
                  text: lines[line].to_s[character, length],
                  type: Parsanol::PARG::Lsp::SEMANTIC_TYPES[type],
                  modifiers: modifiers }
    end
    tokens
  end

  describe "imports" do
    let(:workspace) { Dir.mktmpdir("parg-lsp") }
    let(:helper_path) { File.join(workspace, "helper.parg") }
    let(:main_path) { File.join(workspace, "main.parg") }
    let(:helper_source) do
      <<~PARG
        grammar Helper version "1.0.0" {
          ## A two-letter code.
          code = 2*2(%x61-7A) as code

          entry code: code
        }
      PARG
    end
    let(:main_source) do
      <<~PARG
        use helper

        grammar Main version "1.0.0" {
          main = helper.code "!"

          entry main: main
        }
      PARG
    end

    def helper_uri
      "file://#{helper_path}"
    end

    def main_uri
      "file://#{main_path}"
    end

    before do
      File.write(helper_path, helper_source)
      File.write(main_path, main_source)
    end

    after do
      FileUtils.remove_entry(workspace) if File.directory?(workspace)
    end

    it "resolves hover and definition through the import" do
      messages = run_lsp([
                           open_document(main_uri, main_source),
                           request(2, "textDocument/hover",
                                   "textDocument" => { "uri" => main_uri },
                                   "position" => { "line" => 3, "character" => 12 }),
                           request(3, "textDocument/definition",
                                   "textDocument" => { "uri" => main_uri },
                                   "position" => { "line" => 3, "character" => 12 }),
                         ])

      hover = response(messages, 2).dig("result", "contents", "value")
      expect(hover).to include("`code`")
      expect(hover).to include("A two-letter code.")

      location = response(messages, 3)["result"]
      expect(URI::DEFAULT_PARSER.unescape(location["uri"].sub("file://", ""))).to eq(helper_path)
      expect(location.dig("range", "start", "line")).to eq(2)
    end

    it "accepts the qualified reference without lint diagnostics" do
      messages = run_lsp([open_document(main_uri, main_source)])
      expect(diagnostics_for(messages, main_uri)).to be_empty
    end

    it "completes imported rule names as qualified labels" do
      messages = run_lsp([
                           open_document(main_uri, main_source),
                           request(2, "textDocument/completion",
                                   "textDocument" => { "uri" => main_uri },
                                   "position" => { "line" => 3, "character" => 4 }),
                         ])
      labels = response(messages, 2).dig("result", "items").map { |item| item["label"] }
      expect(labels).to include("helper.code")
    end
  end
end
