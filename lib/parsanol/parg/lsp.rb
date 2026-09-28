# frozen_string_literal: true

require "json"
require "rbconfig"

module Parsanol
  module PARG
    # F11: minimal PARG LSP over stdio (JSON-RPC 2.0, no framework).
    #
    #   initialize / shutdown / exit
    #   textDocument/didOpen|didChange -> publishDiagnostics
    #     (parse errors, lint errors, failing inline tests)
    #   textDocument/hover -> the rule's ## doc comment
    #
    # Diagnostics and hover run entirely on the compiler API — one
    # language implementation, every editor.
    class Lsp
      ContentLength = "Content-Length: ".freeze

      def initialize(input = $stdin, output = $stdout)
        @input = input
        @output = output
        @documents = {}
      end

      def run
        until @input.eof?
          header = @input.gets("\r\n\r\n")
          break if header.nil?

          length = header[/Content-Length: (\d+)/i, 1].to_i
          break if length.zero?

          message = JSON.parse(@input.read(length))
          handle(message)
        end
      end

      private

      def handle(message)
        case message["method"]
        when "initialize"
          respond(message, {
            "capabilities" => {
              "textDocumentSync" => 1,
              "hoverProvider" => true,
            },
            "serverInfo" => { "name" => "parsanol-parg-lsp" },
          })
        when "shutdown"
          respond(message, nil)
        when "exit"
          exit 0
        when "textDocument/didOpen", "textDocument/didChange"
          doc = message["params"]["textDocument"]
          @documents[doc["uri"]] =
            doc["text"] || message.dig("params", "contentChanges", -1, "text")
          publish_diagnostics(doc["uri"])
        when "textDocument/codeAction"
          respond(message, code_action(message["params"]))
        when "textDocument/hover"
          respond(message, hover(message.dig("params", "textDocument", "uri"),
                                 message.dig("params", "position")))
        end
      end

      def respond(message, result)
        send_message("id" => message["id"], "result" => result)
      end

      def notify(method, params)
        send_message("jsonrpc" => "2.0", "method" => method, "params" => params)
      end

      def send_message(payload)
        body = JSON.generate(payload)
        @output.write("Content-Length: #{body.bytesize}\r\n\r\n#{body}")
        @output.flush
      end

      def publish_diagnostics(uri)
        source = @documents[uri]
        diagnostics = []
        document = nil
        begin
          document = Parser.new(source).parse
        rescue ParseError => e
          line = 0
          # The self-hosting artifact yields a precise offset (F7 wire);
          # prefer it when the artifact is available.
          if SelfHost.available?
            begin
              SelfHost.validate(source)
            rescue Parsanol::ParseFailed
              # fall through to line 0
            end
          end
          diagnostics << diagnostic(line, e.message)
        end
        if document
          begin
            tables_dir = ENV["PG_TABLES_DIR"]
            compiler = Compiler.new(document, tables_dir)
            document.rules.each_key { |rule| compiler.atom_for(rule) }
            Lints.errors(document, compiler).each do |error|
              diagnostics << diagnostic(rule_line(source, error[/\Arule (\w+):/, 1]), error)
            end
            compiler.run_tests.each do |failure|
              diagnostics << diagnostic(0, failure)
            end
          rescue ParseError, PARG::Error => e
            diagnostics << diagnostic(0, e.message)
          end
        end
        notify("textDocument/publishDiagnostics",
               "uri" => uri, "diagnostics" => diagnostics)
      end

      # Rule-granular position: the line the named rule is defined on.
      def rule_line(source, rule_name)
        return 0 unless rule_name

        source.lines.index { |l| l.match?(/^\s*#{rule_name}\s*=/) } || 0
      end

      def diagnostic(line, message)
        {
          "range" => { "start" => { "line" => line, "character" => 0 },
                       "end" => { "line" => line, "character" => 0 } },
          "severity" => 1,
          "source" => "parsanol-parg",
          "message" => message,
        }
      end

      # Reorder code action: only when EVERY top-level alternative of the
      # rule is a quoted literal is the reorder mechanically safe.
      def code_action(params)
        uri = params.dig("textDocument", "uri")
        source = @documents[uri]
        return [] unless source

        line_no = params.dig("range", "start", "line").to_i
        text = source.lines[line_no].to_s
        return [] unless text.match?(/^\s*[a-z_]+\s*=\s*"/)

        alternatives = top_level_literals(text)
        return [] if alternatives.nil? || alternatives.size < 2

        sorted = alternatives.sort_by { |a| -a.length }
        return [] if sorted == alternatives

        [{
          "title" => "Reorder alternatives longest-first",
          "kind" => "refactor",
          "edit" => {
            "changes" => {
              uri => [{ "range" => whole_line_range(line_no),
                        "newText" => "#{text[/^\s*[a-z_]+\s*=\s*/]}#{sorted.join(' / ').inspect}" }],
            },
          },
        }]
      end

      def top_level_literals(line)
        rhs = line.sub(/^\s*[a-z_]+\s*=\s*/, "")
        parts = rhs.split(/ (?=")/).flat_map { |p| p.split(%r{ / (?=")} ) }
        literals = parts.map { |p| p.match(/^"((?:[^"\\]|\\.)*)"$/) }
        return nil if literals.any?(&:nil?)

        literals.map { |m| m[1] }
      end

      def whole_line_range(line_no)
        { "start" => { "line" => line_no, "character" => 0 },
          "end" => { "line" => line_no, "character" => 1000 } }
      end

      def hover(uri, position)
        source = @documents[uri]
        return nil unless source && position

        line_no = position.dig("position", "line") || position["line"]
        text = source.lines[line_no.to_i].to_s
        rule = text[/^\s*([a-z_]+)\s*=/, 1]
        return nil unless rule

        lines = source.lines
        rule_line = lines.index { |l| l.match?(/^\s*#{rule}\s*=/) }
        return nil unless rule_line

        doc_lines = []
        cursor = rule_line - 1
        while cursor >= 0 && lines[cursor].strip.start_with?("##")
          doc_lines.unshift(lines[cursor])
          cursor -= 1
        end
        return nil if doc_lines.empty?

        doc = doc_lines.map(&:strip).join("\n")

        { "contents" => { "kind" => "markdown",
                          "value" => doc.gsub(/^##\s?/, "").strip } }
      end
    end
  end
end
