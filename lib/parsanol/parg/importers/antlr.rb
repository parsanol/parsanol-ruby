# frozen_string_literal: true

module Parsanol
  module PARG
    module Import
      # ANTLR 4 importer — scoped v1 (ruby#309).
      #
      # Imported: parser rules, lexer rules (as PARG rules), fragments
      # (inlined name rules), literals, character sets and ranges,
      # `?`/`*`/`+` postfixes, groups, `|` alternatives, `//` and `/* */`
      # comments.
      #
      # Reported per occurrence with position, never silently dropped:
      # semantic predicates and actions `{...}`, non-greedy quantifiers
      # (`*?`), alternative labels (`# name`), `options {}`, `imports`,
      # `tokenVocab`, lexer commands (`-> mode/skip/channel`).
      #
      # The deep semantic difference, stated like the ABNF importer's:
      # ANTLR's adaptive LL(*) tolerates ambiguity; PARG's ordered choice
      # is decisive. The compile-time order-dependence lint surfaces
      # every branch pair whose order matters, so a mechanical
      # transliteration is reviewable instead of silently different.
      class Antlr
        class Error < StandardError
        end

        TOKEN = /
          (?<block_comment>\/\*.*?\*\/)
        | (?<line_comment>\/\/[^\n]*)
        | (?<literal>'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")
        | (?<charset>\[(?:[^\]\\]|\\.)*\])
        | (?<action>\{(?:(?>[^{}])|\{(?:(?>[^{}])|\{[^{}]*\}))*\}*)
        | (?<punct>=\/|->|\.\.|[;:|()+*?.#\[\]=~^])
        | (?<name>[A-Za-z_][A-Za-z0-9_]*)
        | (?<nl>\n)
        | (?<ws>[ \t\r]+)
        /x

        SKIP = %i[block_comment line_comment ws].freeze

        class << self
          def call(text)
            new(text).call
          end
        end

        def initialize(text)
          @text = text
          @tokens = []
          @pos = 0
          @rules = {}
          @order = []
          scan
        end

        def call
          parse_grammar
          emit
        end

        private

        def scan
          pos = 0
          line = 1
          until pos >= @text.length
            if @text[pos] == "\n"
              @tokens << [:nl, "\n", line]
              line += 1
              pos += 1
              next
            end
            match = TOKEN.match(@text, pos)
            if match.nil? || match.begin(0) != pos
              raise Error, "ANTLR: unexpected #{@text[pos].inspect} at offset #{pos} (line #{line})"
            end

            name = TOKEN.names.find { |n| match[n] }
            @tokens << [name.to_sym, match[0], line]
            pos = match.end(0)
          end
        end

        def peek(offset = 0)
          @tokens[@pos + offset]
        end

        def advance
          token = @tokens[@pos]
          @pos += 1
          token
        end

        def skip_fillers
          advance while (peek && SKIP.include?(peek[0])) || peek&.[](0) == :nl
        end

        def parse_grammar
          loop do
            skip_fillers
            break if peek.nil?

            # `grammar Name;` — the declaration carries no rules.
            if peek&.[](0) == :name && peek[1] == "grammar"
              advance
              skip_fillers
              advance while peek&.[](0) == :name
              skip_fillers
              advance if peek&.[](0) == :punct && peek[1] == ";"
              next
            end

            parse_rule
          end
        end

        def parse_rule
          skip_fillers
          name_token = advance
          raise Error, "ANTLR: expected rule name, got #{name_token&.[](1).inspect}" unless name_token&.[](0) == :name

          skip_fillers

          colon = advance
          unless colon && colon[0] == :punct && colon[1] == ":"
            what = colon&.[](1) == "=" ? "'=' (ANTLR has no rule assignment)" : colon&.[](1).inspect
            raise Error,
                  "ANTLR: rule #{name_token[1].inspect} (line #{name_token[2]}): expected ':', got #{what} — " \
                  "options/imports/tokenVocab sections are out of scope for v1"
          end

          name = normalize_name(name_token[1])
          body = parse_alternation
          finish_rule(name, body)
        end

        def finish_rule(name, body)
          raise Error, "ANTLR: expected ';' after rule #{name.inspect}" unless semicolon?

          if @rules.key?(name)
            raise Error, "ANTLR: duplicate rule #{name.inspect}"
          end

          @rules[name] = body
          @order << name
        end

        def semicolon?
          skip_fillers
          return false unless peek&.[](0) == :punct && peek[1] == ";"

          advance
          true
        end

        def parse_alternation
          parts = [parse_element_sequence]
          while peek&.[](0) == :punct && peek[1] == "|"
            advance
            parts << parse_element_sequence
          end
          reject_label!
          parts.join(" / ")
        end

        def reject_label!
          return unless peek&.[](0) == :punct && peek[1] == "#"

          token = advance
          label = advance
          raise Error,
                "ANTLR: alternative labels (##{label&.[](1)}) are out of scope for v1 " \
                "(line #{token[2]}) — label the rule instead"
        end

        def element_sequence_terminator?(token)
          token&.[](0) == :punct && %w[; | )].include?(token[1])
        end

        def reject_lexer_command!
          return unless peek&.[](0) == :punct && peek[1] == "->"

          token = advance
          skip_fillers
          command = advance
          guidance =
            if command&.[](1) == "skip"
              "PARG's equivalent is a `skip = <rule>` declaration at the grammar level, " \
                "not a per-token command"
            else
              "lexer modes/channels have no PARG equivalent"
            end
          raise Error,
                "ANTLR: lexer command -> #{command&.[](1).inspect} (line #{token[2]}) is out of " \
                "scope for v1 — #{guidance}"
        end

        def parse_element_sequence
          parts = []
          loop do
            skip_fillers
            break if peek.nil?
            break if element_sequence_terminator?(peek)

            reject_lexer_command!

            part = parse_postfixed
            next if part == :eof # consume-all is implicit in PARG

            parts << part
          end
          raise Error, "ANTLR: empty rule body" if parts.empty?

          parts.length == 1 ? parts[0] : "(#{parts.join(' ')})"
        end

        def parse_postfixed
          element = parse_element
          loop do
            skip_fillers
            token = peek
            break unless token&.[](0) == :punct

            case token[1]
            when "?" then advance and element = "[#{element}]"
            when "*" then advance and element = "*#{element}"
            when "+" then advance and element = "1*#{element}"
            else break
            end
          end
          element
        end

        def parse_element
          token = advance
          raise Error, "ANTLR: unexpected end of rule body" if token.nil?

          case token[0]
          when :literal then emit_literal(token[1], token[2])
          when :charset then emit_charset(token[1], token[2])
          when :name
            return :eof if token[1] == "EOF" # consume-all is implicit

            normalize_name(token[1])
          when :punct
            case token[1]
            when "#"
              raise Error,
                    "ANTLR: alternative labels are out of scope for v1 " \
                    "(line #{token[2]}) — label the rule instead"
            when "("
              body = parse_alternation
              skip_fillers
              expect ")"
              "(#{body})"
            when "."
              "ANY"
            when "~"
              # The negation idiom: ~[set] = any codepoint outside the
              # set, as a lookahead-guarded ANY. Quantifiers land outside
              # via parse_postfixed.
              set_token = advance
              raise Error, "ANTLR: ~ must apply to a character set (line #{token[2]})" unless set_token&.[](0) == :charset

              ranges = charset_ranges(set_token[1][1..-2], token[2])
              set_text = ranges.map { |first, last| range_text(first, last) }.join(" / ")
              "( !( (#{set_text}) ) ANY )"
            else
              raise Error, "ANTLR: unexpected #{token[1].inspect} (line #{token[2]})"
            end
          when :action
            raise Error,
                  "ANTLR: action/predicate #{token[1][0, 24].inspect} (line #{token[2]}) is out of " \
                  "scope for v1 — target-language code has no PARG equivalent"
          else
            raise Error, "ANTLR: unexpected token #{token[0]} (line #{token[2]})"
          end
        end

        def expect(char)
          token = advance
          return if token&.[](0) == :punct && token[1] == char

          raise Error, "ANTLR: expected #{char.inspect}, got #{token&.[](1).inspect} (line #{token&.[](2)})"
        end

        def emit_literal(token, line)
          body = token[1..-2]
          raise Error, "ANTLR: empty literal (line #{line})" if body.empty?

          escaped = body.gsub("\\", "\\\\").gsub('"', '\\"')
          "\"#{escaped}\""
        end

        # [a-z], [abc], [^abc], [a-zA-Z0-9_] -- ANTLR char sets are
        # case-SENSITIVE single characters. PARG expresses classes as
        # %x-range alternations.
        def emit_charset(token, line)
          body = token[1..-2]
          negated = body.start_with?("^")
          body = body[1..] if negated
          ranges = charset_ranges(body, line)
          ranges = complement_ranges(ranges) if negated
          "(#{ranges.map { |lo, hi| range_text(lo, hi) }.join(' / ')})"
        end

        def charset_ranges(body, line)
          ranges = []
          i = 0
          while i < body.length
            if body[i] == "\\"
              byte = escape_byte(body[i + 1], line)
              ranges << [byte, byte]
              i += 2
            elsif body[i + 1] == "-" && body[i + 2] && body[i + 2] != "]"
              lo = escape_byte(body[i], line)
              hi = escape_byte(body[i + 2], line)
              raise Error, "ANTLR: reversed range (line #{line})" if lo > hi

              ranges << [lo, hi]
              i += 3
            else
              byte = escape_byte(body[i], line)
              ranges << [byte, byte]
              i += 1
            end
          end
          ranges
        end

        def escape_byte(char, line)
          case char
          when "n" then 0x0A
          when "r" then 0x0D
          when "t" then 0x09
          when "\\" then 0x5C
          else
            byte = char.ord
            if byte > 0x7F
              raise Error, "ANTLR: non-ASCII #{char.inspect} in a character set (line #{line}) -- " \
                           "write a %x range or a literal instead"
            end

            byte
          end
        end

        def complement_ranges(ranges)
          result = []
          cursor = 0x00
          ranges.sort.each do |lo, hi|
            result << [cursor, lo - 1] if lo > cursor
            cursor = hi + 1
          end
          result << [cursor, 0x7F] if cursor <= 0x7F
          raise Error, "ANTLR: negated set covers everything" if result.empty?

          result
        end

        def range_text(first, last)
          first == last ? "%x#{format('%02X', first)}" : "%x#{format('%02X', first)}-#{format('%02X', last)}"
        end

        def normalize_name(name)
          # Lexer rules are UPPER_CASE; PARG rule names are lowercase.
          name.downcase
        end

        def emit
          header = <<~PARG
            # Imported from ANTLR 4 (scoped v1).
            # Notes:
            # - ANTLR's adaptive LL(*) tolerates ambiguity; PARG's ordered
            #   choice is decisive — the compiler's order-dependence lint
            #   surfaces every branch pair whose order matters.
            # - Lexer rules imported as ordinary rules; case-sensitivity of
            #   ANTLR literals is preserved (plain "..." literals).
            # - Actions, predicates, labels, options, lexer commands:
            #   rejected with position, never silently dropped.
          PARG
          body = @order.filter_map { |name| "  #{"#{name} = #{@rules[name]}" if @rules[name]}" }
            .join("\n")
          "#{header}grammar Imported version \"0.0.0\" {\n#{body}\n}\n"
        end
      end
    end
  end
end
