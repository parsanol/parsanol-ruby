# frozen_string_literal: true

require "json"
require "strscan"
require "uri"

module Parsanol
  module PARG
    # PARG language server over stdio (JSON-RPC 2.0, no framework).
    #
    #   initialize / shutdown / exit
    #   textDocument/didOpen|didChange|didClose -> publishDiagnostics
    #     (parse errors, lint errors, failing inline tests; imports merged)
    #   textDocument/hover              -> rule docs (Imports-aware)
    #   textDocument/definition         -> rule definition / imported file
    #   textDocument/references         -> rule occurrences
    #   textDocument/completion         -> keywords, rule names, snippets
    #   textDocument/semanticTokens/full
    #   textDocument/codeAction         -> longest-first reorder
    #
    # Everything runs on the compiler API and the parsed Document model — one
    # language implementation, every editor. Imported grammars are resolved
    # from the document's directory and PG_IMPORT_DIR (path-separator list).
    class Lsp
      CONTENT_LENGTH = "Content-Length: "

      SEMANTIC_TYPES = %w[keyword rule capture string number comment].freeze
      SEMANTIC_MODIFIERS = %w[declaration].freeze
      DECLARATION_BIT = 1

      KEYWORDS = (%w[version test accept reject example use] + Parser::KEYWORDS).uniq.freeze

      COMPLETION_KEYWORDS = KEYWORDS.map do |keyword|
        { "label" => keyword, "kind" => 14 }
      end.freeze

      SNIPPETS = [
        ["%i\"...\"", "%i\"${1:text}\"", "case-insensitive literal"],
        ["%x41", "%x41", "one code point"],
        ["%x41-5A", "%x41-5A", "code point range"],
        ["%x0D.0A", "%x0D.0A", "code point sequence"],
        ["[ ... ]", "[ ${1:content} ]", "optional"],
        ["*( ... )", "*( ${1:content} )", "zero or more"],
        ["1*( ... )", "1*( ${1:content} )", "one or more"],
        ["!x", "!${1:x}", "negative lookahead"],
        ["&x", "&${1:x}", "positive lookahead"],
        ["!<x", "!< ${1:x}", "negative behind-guard"],
        ["&<x", "&< ${1:x}", "positive behind-guard"],
        ["as name", "as ${1:name}", "capture"],
      ].map do |label, insert, detail|
        { "label" => label, "kind" => 15, "detail" => detail,
          "insertText" => insert, "insertTextFormat" => 2 }
      end.freeze

      def initialize(input = $stdin, output = $stdout)
        @input = input
        @output = output
        @documents = {}
        @parsed = {}
        @import_paths = {}
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
                      "definitionProvider" => true,
                      "referencesProvider" => true,
                      "codeActionProvider" => true,
                      "completionProvider" => {
                        "triggerCharacters" => [".", "%", "\""],
                      },
                      "semanticTokensProvider" => {
                        "legend" => {
                          "tokenTypes" => SEMANTIC_TYPES,
                          "tokenModifiers" => SEMANTIC_MODIFIERS,
                        },
                        "full" => true,
                      },
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
          @parsed.delete(doc["uri"])
          publish_diagnostics(doc["uri"])
        when "textDocument/didClose"
          uri = message.dig("params", "textDocument", "uri")
          @documents.delete(uri)
          @parsed.delete(uri)
        when "textDocument/codeAction"
          respond(message, code_action(message["params"]))
        when "textDocument/hover"
          respond(message, hover(*position_params(message["params"])))
        when "textDocument/definition"
          respond(message, definition(*position_params(message["params"])))
        when "textDocument/references"
          params = message["params"]
          respond(message, references(params.dig("textDocument", "uri"),
                                      params["position"],
                                      params.dig("context", "includeDeclaration")))
        when "textDocument/completion"
          respond(message, completion(message.dig("params", "textDocument", "uri")))
        when "textDocument/semanticTokens/full"
          respond(message, semantic_tokens(message.dig("params", "textDocument", "uri")))
        end
      end

      def respond(message, result)
        send_message("jsonrpc" => "2.0", "id" => message["id"], "result" => result)
      end

      def notify(method, params)
        send_message("jsonrpc" => "2.0", "method" => method, "params" => params)
      end

      def send_message(payload)
        body = JSON.generate(payload)
        @output.write("Content-Length: #{body.bytesize}\r\n\r\n#{body}")
        @output.flush
      end

      # ---- documents and imports -------------------------------------------

      def position_params(params)
        [params.dig("textDocument", "uri"), params["position"]]
      end

      def document_source(uri)
        return @documents[uri] if @documents.key?(uri)

        path = @import_paths[uri] || file_path(uri)
        return nil unless path && File.file?(path)

        File.read(path)
      end

      def parsed(uri)
        source = @documents[uri]
        return nil unless source

        cached = @parsed[uri]
        return cached[1] if cached && cached[0] == source

        document = begin
          Parser.new(source).parse
        rescue ParseError
          nil
        end
        @parsed[uri] = [source, document]
        document
      end

      def file_path(uri)
        text = uri.to_s
        return nil unless text.start_with?("file://")

        URI::DEFAULT_PARSER.unescape(text.delete_prefix("file://"))
      end

      def import_dirs(uri)
        dirs = []
        path = file_path(uri)
        dirs << File.dirname(path) if path
        ENV.fetch("PG_IMPORT_DIR", "").split(File::PATH_SEPARATOR).each do |dir|
          dirs << dir unless dir.to_s.empty?
        end
        dirs.uniq
      end

      def import_uri(uri, name)
        import_dirs(uri).each do |dir|
          path = File.join(dir, "#{name}.parg")
          next unless File.file?(path)

          expanded = File.expand_path(path)
          target = "file://#{URI::DEFAULT_PARSER.escape(expanded)}"
          @import_paths[target] = expanded
          return target
        end
        nil
      end

      # ---- rule model ------------------------------------------------------

      Definition = Struct.new(:line, :character, :name_length, :docs)

      # Rule definitions with their preceding ## doc comments. Works on a
      # source that does not parse: hover/definition stay useful mid-edit.
      def rule_definitions(source)
        defs = {}
        lines = source.to_s.lines
        lines.each_with_index do |line, index|
          match = line.match(/\A(\s*)(?:atomic\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=/)
          next unless match

          name = match[2]
          docs = []
          cursor = index - 1
          while cursor.negative? == false && lines[cursor].to_s.strip.start_with?("##")
            docs.unshift(lines[cursor].strip.sub(/\A##\s?/, ""))
            cursor -= 1
          end
          defs[name] = Definition.new(index, match.begin(2), name.length, docs.join("\n"))
        end
        defs
      end

      def rule_names(uri)
        document = parsed(uri)
        return document.rules.keys if document

        rule_definitions(document_source(uri)).keys
      end

      # Resolve a (possibly dotted) rule reference to its defining file.
      def resolve(uri, word)
        segments = word.to_s.split(".").reject(&:empty?)
        return nil if segments.empty?

        resolve_segments(uri, segments)
      end

      def resolve_segments(uri, segments)
        source = document_source(uri)
        return nil unless source

        if segments.size == 1
          name = segments.first
          defs = rule_definitions(source)
          definition = defs[name]
          return nil unless definition

          return { uri: uri, name: name, definition: definition }
        end

        document = if @documents.key?(uri)
                     parsed(uri)
                   else
                     begin
                       Parser.new(source).parse
                     rescue ParseError
                       nil
                     end
                   end
        return nil unless document&.uses&.include?(segments.first)

        target = import_uri(uri, segments.first)
        return nil unless target

        resolve_segments(target, segments[1..])
      end

      def word_at(source, position)
        return nil unless source && position

        line = source.lines[position["line"].to_i].to_s
        character = position["character"].to_i
        left = line[0...character].to_s
        right = line[character..].to_s
        prefix = left[/[A-Za-z0-9_.]*\z/] || ""
        suffix = right[/\A[A-Za-z0-9_.]*/] || ""
        word = (prefix + suffix).sub(/\A\.+/, "").sub(/\.+\z/, "")
        return nil if word.empty?

        word
      end

      def import_use_line?(source, position)
        line = source.lines[position["line"].to_i].to_s
        line.match?(/\A\s*use\s+/)
      end

      def location(uri, line, character, length)
        {
          "uri" => uri,
          "range" => {
            "start" => { "line" => line, "character" => character },
            "end" => { "line" => line, "character" => character + length },
          },
        }
      end

      # ---- hover / definition / references ---------------------------------

      def hover(uri, position)
        source = document_source(uri)
        return nil unless source && position

        word = word_at(source, position)
        return nil unless word

        if import_use_line?(source, position)
          target = import_uri(uri, word)
          return nil unless target

          return { "contents" => { "kind" => "markdown",
                                   "value" => "Import `#{word}`\n\n`#{File.basename(target)}`" } }
        end

        resolved = resolve(uri, word)
        return nil unless resolved

        definition = resolved[:definition]
        return nil unless definition

        value = if definition.docs.empty?
                  "`#{resolved[:name]}` — rule"
                else
                  "`#{resolved[:name]}`\n\n#{definition.docs}"
                end
        { "contents" => { "kind" => "markdown", "value" => value } }
      end

      def definition(uri, position)
        source = document_source(uri)
        return nil unless source && position

        word = word_at(source, position)
        return nil unless word

        if import_use_line?(source, position)
          target = import_uri(uri, word)
          return target ? location(target, 0, 0, 0) : nil
        end

        resolved = resolve(uri, word)
        return nil unless resolved

        definition = resolved[:definition]
        location(resolved[:uri], definition.line, definition.character,
                 definition.name_length)
      end

      def references(uri, position, include_declaration)
        source = document_source(uri)
        return nil unless source && position

        word = word_at(source, position)
        resolved = word && resolve(uri, word)
        return nil unless resolved

        name = resolved[:name]
        uris = [resolved[:uri], uri].uniq
        results = []
        uris.each do |target_uri|
          target_source = document_source(target_uri)
          next unless target_source

          qualified = target_uri == uri && resolved[:uri] != uri && word.include?(".")
          needle = qualified ? word : name
          declaration = rule_definitions(target_source)[name]
          target_source.lines.each_with_index do |line, index|
            identifier_occurrences(line, needle).each do |character, length|
              declaration_here = declaration && declaration.line == index &&
                character == declaration.character && needle == name
              results << location(target_uri, index, character, length) if
                include_declaration || !declaration_here
            end
          end
        end
        results
      end

      # Identifier tokens outside strings and comments: a rule name inside a
      # literal or a doc comment is not a reference.
      def identifier_occurrences(line, name)
        found = []
        scanner = StringScanner.new(line)
        until scanner.eos?
          start = scanner.pos
          start_char = line.byteslice(0, start).length
          if scanner.scan(/#.*/)
            break
          elsif scanner.scan(/%(?:i|s)?"(?:\\.|[^"\\])*"/) ||
              scanner.scan(/"(?:\\.|[^"\\])*"/) ||
              scanner.scan(/%x[0-9A-Fa-f]{2}(?:[.-][0-9A-Fa-f]{2})*|[0-9]+/) ||
              scanner.scan(/\s+/)
            next
          elsif (text = scanner.scan(/[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*/))
            found << [start_char, text.length] if text == name
          else
            scanner.getch
          end
        end
        found
      end

      # ---- completion ------------------------------------------------------

      def completion(uri)
        source = document_source(uri)
        return nil unless source

        items = COMPLETION_KEYWORDS.dup + SNIPPETS.dup
        rule_names(uri).each do |name|
          items << { "label" => name, "kind" => 18, "detail" => "rule" }
        end
        document = parsed(uri)
        (document&.uses || []).each do |import|
          target = import_uri(uri, import)
          next unless target

          rule_definitions(document_source(target)).each_key do |name|
            items << { "label" => "#{import}.#{name}", "kind" => 18,
                       "detail" => "imported rule" }
          end
        end
        { "isIncomplete" => false, "items" => items }
      end

      # ---- semantic tokens -------------------------------------------------

      def semantic_tokens(uri)
        source = document_source(uri)
        return nil unless source

        names = rule_names(uri)
        tokens = []
        source.lines.each_with_index do |line, line_no|
          scan_line(line, line_no, names, tokens)
        end
        { "data" => encode_tokens(tokens) }
      end

      def scan_line(line, line_no, names, tokens)
        scanner = StringScanner.new(line)
        previous_word = nil
        until scanner.eos?
          start = scanner.pos
          start_char = line.byteslice(0, start).length

          if (text = scanner.scan(/#.*/))
            tokens << [line_no, start_char, text.length, "comment", 0]
            break
          elsif (text = scanner.scan(/%(?:i|s)?"(?:\\.|[^"\\])*"|"(?:\\.|[^"\\])*"/))
            tokens << [line_no, start_char, text.length, "string", 0]
            previous_word = nil
          elsif (text = scanner.scan(/%x[0-9A-Fa-f]{2}(?:[.-][0-9A-Fa-f]{2})*|[0-9]+/))
            tokens << [line_no, start_char, text.length, "number", 0]
            previous_word = nil
          elsif (text = scanner.scan(/[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*/))
            type, modifiers = classify_word(line, start_char, text, names, previous_word)
            tokens << [line_no, start_char, text.length, type, modifiers] if type
            previous_word = text
          elsif (text = scanner.scan(/\s+/))
            _ = text
          else
            scanner.getch
            previous_word = nil
          end
        end
      end

      def classify_word(line, start_char, text, names, previous_word)
        base = text.split(".").last
        if KEYWORDS.include?(text)
          ["keyword", 0]
        elsif previous_word == "as"
          ["capture", 0]
        elsif names.include?(base) || text.include?(".")
          modifier = declaration_here?(line, start_char, text) ? DECLARATION_BIT : 0
          ["rule", modifier]
        elsif %w[entry bindings test].include?(previous_word)
          ["rule", DECLARATION_BIT]
        end
      end

      def declaration_here?(line, start_char, text)
        before = line[0...start_char].to_s
        after = line[(start_char + text.length)..].to_s
        before.match?(/\A\s*(?:atomic\s+)?\z/) && after.match?(/\A\s*=/)
      end

      def encode_tokens(tokens)
        data = []
        last_line = 0
        last_char = 0
        tokens.sort_by { |token| [token[0], token[1]] }.each do |line, char, length, type, modifiers|
          delta_line = line - last_line
          delta_char = delta_line.zero? ? char - last_char : char
          data.push(delta_line, delta_char, length, SEMANTIC_TYPES.index(type), modifiers)
          last_line = line
          last_char = char
        end
        data
      end

      # ---- diagnostics -----------------------------------------------------

      def publish_diagnostics(uri)
        source = @documents[uri]
        diagnostics = []
        document = begin
          Parser.new(source).parse
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
          nil
        end
        if document
          dirs = import_dirs(uri)
          begin
            Imports.merge!(document, dirs) if document.uses.any?
          rescue PARG::Error, ParseError => e
            diagnostics << diagnostic(use_line(source, document), e.message)
          end
          begin
            tables_dir = ENV.fetch("PG_TABLES_DIR", nil) || dirs.first
            compiler = Compiler.new(document, tables_dir)
            document.rules.each_key { |rule| compiler.atom_for(rule) }
            Lints.errors(document, compiler).each do |error|
              diagnostics << diagnostic(rule_line(source, error[/\Arule (\w+):/, 1]), error)
            end
            compiler.test_failures.each do |failure|
              diagnostics << diagnostic(0, failure)
            end
          rescue ParseError, PARG::Error => e
            diagnostics << diagnostic(0, e.message)
          end
        end
        notify("textDocument/publishDiagnostics",
               "uri" => uri, "diagnostics" => diagnostics)
      end

      def use_line(source, document)
        name = document.uses.first
        return 0 unless name

        source.lines.index { |line| line.match?(/^\s*use\s+#{Regexp.escape(name)}\b/) } || 0
      end

      # Rule-granular position: the line the named rule is defined on.
      def rule_line(source, rule_name)
        return 0 unless rule_name

        source.lines.index { |line| line.match?(/^\s*#{rule_name}\s*=/) } || 0
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

      # ---- code action -----------------------------------------------------

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
        parts = rhs.split(/ (?=")/).flat_map { |p| p.split(%r{ / (?=")}) }
        literals = parts.map { |p| p.match(/^"((?:[^"\\]|\\.)*)"$/) }
        return nil if literals.any?(&:nil?)

        literals.map { |m| m[1] }
      end

      def whole_line_range(line_no)
        { "start" => { "line" => line_no, "character" => 0 },
          "end" => { "line" => line_no, "character" => 1000 } }
      end
    end
  end
end
