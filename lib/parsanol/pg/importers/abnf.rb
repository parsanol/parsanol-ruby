# frozen_string_literal: true

module Parsanol
  module PG
    module Import
      # RFC 5234 (+ RFC 7405 case prefixes) ABNF importer.
      #
      # Semantic conversions (recorded in the emitted header):
      # - bare ABNF strings are CASE-INSENSITIVE -> emitted as %i"..."
      # - %s"..." (case-sensitive) -> emitted as plain "..."
      # - ABNF alternation is unordered; PG's is ordered. The PG compiler's
      #   first-set lint flags order-dependent branches after import.
      # - rule names are case-insensitive in ABNF -> normalized to snake_case
      # - prose-vals (<...>) are rejected: they are not machine-parseable
      class Abnf
        TOKEN = /
          (?<ws>[ \t]+)
        | (?<comment>;[^\n]*)
        | (?<crlf>\r?\n)
        | (?<sstr>%s"(?:[^"\\]|\\.)*")
        | (?<cistr>"(?:[^"\\]|\\.)*")
        | (?<numval>%[xbdo][0-9A-Za-z]+(?:-[0-9A-Za-z]+|(?:\.[0-9A-Za-z]+)+)?)
        | (?<prose><[^>\n]*>)
        | (?<definedas>=\/|=)
        | (?<name>[A-Za-z][A-Za-z0-9-]*)
        | (?<num>\d+)
        | (?<punct>[*\/()\[\]])
        /x

        CORE_RULES = {
          "ALPHA" => "%x41-5A / %x61-7A",
          "BIT" => '"0" / "1"',
          "CHAR" => "%x01-7F",
          "CR" => "%x0D",
          "CRLF" => "%x0D %x0A",
          "CTL" => "%x00-1F / %x7F",
          "DIGIT" => "%x30-39",
          "DQUOTE" => "%x22",
          "HEXDIG" => '%x30-39 / %i"a" / %i"b" / %i"c" / %i"d" / %i"e" / %i"f"',
          "HTAB" => "%x09",
          "LF" => "%x0A",
          "OCTET" => "%x00-FF",
          "SP" => "%x20",
          "VCHAR" => "%x21-7E",
          "WSP" => "%x20 / %x09",
        }.freeze

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
          scan
        end

        def call
          parse_rules
          emit
        end

        private

        def scan
          pos = 0
          until pos >= @text.length
            match = TOKEN.match(@text, pos)
            if match.nil? || match.begin(0) != pos
              raise Error,
                    "ABNF: unexpected #{@text[pos].inspect} at offset #{pos}"
            end

            name = TOKEN.names.find { |n| match[n] }
            @tokens << [name.to_sym, match[0], pos]
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

        def skip_inline_ws
          advance while peek && %i[ws comment].include?(peek[0])
        end

        def parse_rules
          loop do
            skip_leading
            break if peek.nil?

            parse_rule
          end
        end

        def skip_leading
          loop do
            token = peek
            break unless token && %i[ws comment crlf].include?(token[0])

            advance
          end
        end

        def parse_rule
          token = advance
          unless token[0] == :name
            raise Error, "ABNF: expected rule name, got #{token[1].inspect}"
          end

          name = normalize_name(token[1])
          skip_inline_ws
          defined = advance
          unless defined && defined[0] == :definedas
            raise Error, "ABNF: expected '=' after #{token[1].inspect}"
          end

          body = parse_alternation
          if defined[1] == "=/"
            @rules[name] = @rules[name] ? "#{@rules[name]} / #{body}" : body
          elsif @rules.key?(name)
            raise Error, "ABNF: duplicate rule #{name.inspect}"
          else
            @rules[name] = body
          end
        end

        def parse_alternation
          parts = [parse_concatenation]
          while peek&.[](0) == :punct && peek[1] == "/"
            advance
            parts << parse_concatenation
          end
          parts.join(" / ")
        end

        def parse_concatenation
          parts = [parse_repetition]
          while continuation?
            parts << parse_repetition
          end
          parts.join(" ")
        end

        def continuation?
          skip_inline_ws
          token = peek
          return false if token.nil?

          if token[0] == :crlf
            unless peek(1)&.[](0) == :ws
              return false
            end

            advance
            advance
            return true
          end
          element_start?(token)
        end

        def element_start?(token)
          %i[name cistr sstr numval num].include?(token[0]) ||
            (token[0] == :punct && %w[* ( \[].include?(token[1]))
        end

        def parse_repetition
          skip_inline_ws
          if peek&.[](0) == :num
            prefix = advance[1]
            if peek&.[](0) == :punct && peek[1] == "*"
              advance
              prefix += "*"
              prefix += advance[1] if peek&.[](0) == :num
            end
            return "#{prefix}#{parse_element}"
          elsif peek&.[](0) == :punct && peek[1] == "*"
            advance
            prefix = "*"
            prefix += advance[1] if peek&.[](0) == :num
            return "#{prefix}#{parse_element}"
          end
          parse_element
        end

        def parse_element
          skip_inline_ws
          token = advance
          raise Error, "ABNF: unexpected end of rule body" if token.nil?

          case token[0]
          when :cistr then emit_string(token[1][1..-2], fold: true)
          when :sstr then emit_string(token[1][3..-2], fold: false)
          when :numval then emit_numval(token[1])
          when :name then normalize_name(token[1])
          when :prose
            raise Error,
                  "ABNF: prose-val #{token[1].inspect} cannot be imported — " \
                  "replace it with a machine-parseable rule"
          when :punct
            case token[1]
            when "("
              body = parse_alternation
              expect_punct(")")
              "(#{body})"
            when "["
              body = parse_alternation
              expect_punct("]")
              "[#{body}]"
            else
              raise Error, "ABNF: unexpected #{token[1].inspect}"
            end
          else
            raise Error, "ABNF: unexpected token #{token[0]}"
          end
        end

        def expect_punct(char)
          skip_inline_ws
          token = advance
          unless token && token[0] == :punct && token[1] == char
            raise Error, "ABNF: expected #{char.inspect}"
          end
        end

        def emit_string(body, fold:)
          escaped = body.gsub("\\", "\\\\").gsub('"', '\\"')
          fold ? "%i\"#{escaped}\"" : "\"#{escaped}\""
        end

        def emit_numval(spec)
          kind = spec[1]
          body = spec[2..]
          if body.include?("-")
            lo, hi = body.split("-")
            "%x#{convert_value(kind, lo)}-#{convert_value(kind, hi)}"
          elsif body.include?(".")
            body.split(".").map { |value| "%x#{convert_value(kind, value)}" }.join(" ")
          else
            "%x#{convert_value(kind, body)}"
          end
        end

        def convert_value(kind, value)
          case kind
          when "x" then format("%02x", value.to_i(16))
          when "d" then format("%02x", value.to_i)
          when "b" then format("%02x", value.to_i(2))
          when "o" then format("%02x", value.to_i(8))
          else raise Error, "ABNF: unknown numeric value kind #{kind.inspect}"
          end
        end

        def normalize_name(name)
          name.downcase.tr("-", "_")
        end

        def emit
          preamble = CORE_RULES.filter_map do |name, body|
            normalized = normalize_name(name)
            next if @rules.key?(normalized)

            "  #{normalized} = #{body}"
          end
          rules = @rules.map { |name, body| "  #{name} = #{body}" }
          lines = [
            "# Imported from ABNF (RFC 5234/7405).",
            "# Notes:",
            "# - bare ABNF strings are case-insensitive; imported as %i\"...\"",
            "# - ABNF alternation is unordered; PG's is ordered — the compiler",
            "#   lints order-dependent branches",
            "grammar imported_abnf version \"0.0.0\" {",
          ]
          lines.concat(preamble)
          lines << "" unless preamble.empty?
          lines.concat(rules)
          lines << "}"
          "#{lines.join("\n")}\n"
        end
      end
    end
  end
end
