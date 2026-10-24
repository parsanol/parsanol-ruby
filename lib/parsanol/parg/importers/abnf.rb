# frozen_string_literal: true

module Parsanol
  module PARG
    module Import
      # RFC 5234 (+ RFC 7405 case prefixes) ABNF importer.
      #
      # Semantic conversions (recorded in the emitted header):
      # - bare ABNF strings are CASE-INSENSITIVE -> emitted as %i"..."
      # - %s"..." (case-sensitive) -> emitted as plain "..."
      # - ABNF alternation is unordered; PARG's is ordered. The PARG compiler's
      #   first-set lint flags order-dependent branches after import.
      # - rule names are case-insensitive in ABNF -> normalized to snake_case
      # - prose-vals (<...>) are rejected: they are not machine-parseable
      # - quoted strings have NO escape mechanism (RFC 5234 3.4): a bare
      #   backslash is an ordinary character; a literal DQUOTE needs the
      #   DQUOTE core rule, not a backslash
      class Abnf
        TOKEN = /
          (?<ws>[ \t]+)
        | (?<comment>;[^\n]*)
        | (?<crlf>\r?\n)
        | (?<sstr>%s"[^"]*")
        | (?<istr>%i"[^"]*")
        | (?<cistr>"[^"]*")
        | (?<numval>%[xbdo][0-9A-Za-z]+(?:-[0-9A-Za-z]+|(?:\.[0-9A-Za-z]+)+)?)
        | (?<prose><[^>\n]*>)
        | (?<definedas>=\/|=)
        | (?<name>[A-Za-z][A-Za-z0-9-]*)
        | (?<num>\d+)
        | (?<punct>[*\/()\[\]])
        /x

        INLINE_WS = %i[ws comment].freeze
        LEADING = %i[ws comment crlf].freeze
        ELEMENT_START_TYPES = %i[name cistr sstr numval num].freeze
        ELEMENT_START_PUNCT = ["*", "(", "["].freeze

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

        # RFC 3986's `0<pchar>` empty idiom lowers to a captured empty
        # literal — the compiler's documented marker form (bare ""
        # zero-width matches are rejected). The sentinel is replaced
        # with the rule's own capture name in parse_rule.
        EMPTY_IDIOM = ":empty0:"

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
          @nullable = nullable_rules
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
          advance while peek && INLINE_WS.include?(peek[0])
        end

        # A CRLF followed by an indented line is a continuation: body
        # whitespace, not the end of the rule (RFC 5234 section 3.4 —
        # RFC 3986's IPv6address styles its alternations this way).
        def skip_body_ws
          loop do
            skip_inline_ws
            break unless peek&.[](0) == :crlf && peek(1)&.[](0) == :ws

            advance
            advance
          end
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
            break unless token && LEADING.include?(token[0])

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
          body = body.gsub(EMPTY_IDIOM) { %(("" as #{name})) }
          if defined[1] == "=/"
            merged = @rules[name] ? "#{@rules[name]} / #{body}" : body
            # Incremental definitions may restate a branch; identical
            # branches are one branch in ABNF's unordered semantics and
            # a compile error in PARG's.
            @rules[name] = split_top_level(merged, " / ").uniq.join(" / ")
          elsif @rules.key?(name)
            raise Error, "ABNF: duplicate rule #{name.inspect}"
          else
            @rules[name] = body
          end
        end

        def parse_alternation
          parts = [parse_concatenation]
          loop do
            skip_body_ws
            break unless peek&.[](0) == :punct && peek[1] == "/"

            advance
            parts << parse_concatenation
          end
          parts.join(" / ")
        end

        def parse_concatenation
          parts = [parse_repetition]
          loop do
            save = @pos
            skip_body_ws
            if peek && element_start?(peek)
              parts << parse_repetition
            else
              # A close paren, an alternation slash, or end of rule:
              # not ours to consume.
              @pos = save
              break
            end
          end
          parts.join(" ")
        end

        def element_start?(token)
          ELEMENT_START_TYPES.include?(token[0]) ||
            (token[0] == :punct && ELEMENT_START_PUNCT.include?(token[1]))
        end

        def parse_repetition
          skip_body_ws
          # RFC 3986's empty idiom: `0<pchar>` — zero of an unparseable
          # prose-val is exactly the empty match.
          if peek&.[](0) == :num && peek[1] == "0" && peek(1)&.[](0) == :prose
            advance
            advance
            return EMPTY_IDIOM
          end
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
          skip_body_ws
          token = advance
          raise Error, "ABNF: unexpected end of rule body" if token.nil?

          case token[0]
          when :cistr then emit_string(token[1][1..-2], fold: true)
          when :istr then emit_string(token[1][3..-2], fold: true)
          when :sstr then emit_string(token[1][3..-2], fold: false)
          when :numval then emit_numval(token[1])
          when :name then normalize_name(token[1])
          when :prose
            # RFC 3986's `0<pchar>` idiom: zero occurrences of anything
            # is the empty match. A real prose-val stays unimportable.
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
          skip_body_ws
          token = advance
          unless token && token[0] == :punct && token[1] == char
            raise Error, "ABNF: expected #{char.inspect}"
          end
        end

        def emit_string(body, fold:)
          # Block form: a String replacement treats backslash escapes
          # specially, so "\\\\" would emit ONE backslash (the silent
          # no-op this bug was).
          escaped = body.gsub("\\") { "\\\\" }.gsub('"') { '\\"' }
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

        # ABNF alternation is unordered; PARG's is ordered. A branch
        # that provably matches empty (repetitions of zero, optionals,
        # the empty idiom) would shadow everything after it in ordered
        # choice, so definitely-nullable branches move last — the same
        # acceptance, no shadowing. Branches with rule references are
        # never moved: their nullability is not provable textually.
        def reorder_nullable_branches_last(body)
          return body unless body.include?(" / ")

          branches = split_top_level(body, " / ")
          return body unless branches.size > 1

          nullable, ordered = branches.partition { |branch| branch_nullable?(branch, @nullable) }
          return body if nullable.empty?

          (ordered + nullable).join(" / ")
        end

        # Fixpoint over the rule graph: a rule is nullable when any
        # alternative's every item is nullable — repetitions of zero,
        # optionals, the empty idiom, or references to nullable rules.
        def nullable_rules
          nullable = {}
          changed = true
          while changed
            changed = false
            @rules.each do |name, body|
              next if nullable[name]

              if split_top_level(body, " / ").any? { |branch| branch_nullable?(branch, nullable) }
                nullable[name] = true
                changed = true
              end
            end
          end
          nullable
        end

        def branch_nullable?(branch, nullable)
          items = split_top_level(branch, " ").reject(&:empty?)
          !items.empty? && items.all? { |item| item_nullable?(item, nullable) }
        end

        def item_nullable?(item, nullable)
          return true if item.start_with?("*")
          return true if item.start_with?("[") && item.end_with?("]")
          return true if item.start_with?('("" as')

          name = item[/\A[a-z0-9_]+\z/]
          name ? nullable[name] == true : false
        end

        def split_top_level(text, separator)
          out = []
          depth = 0
          current = +""
          index = 0
          while index < text.length
            piece = text[index..]
            if piece.start_with?(separator) && depth.zero?
              out << current
              current = +""
              index += separator.length
              next
            end
            case piece[0]
            when "(" then depth += 1
            when ")" then depth -= 1
            end
            current << piece[0]
            index += 1
          end
          out << current
          out
        end

        def provably_empty?(branch)
          items = split_top_level(branch, " ").reject(&:empty?)
          !items.empty? && items.all? do |item|
            item.start_with?("*", "[", '("" as')
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
          rules = @rules.map { |name, body| "  #{name} = #{reorder_nullable_branches_last(body)}" }
          lines = [
            "# Imported from ABNF (RFC 5234/7405).",
            "# Notes:",
            "# - bare ABNF strings are case-insensitive; imported as %i\"...\"",
            "# - ABNF alternation is unordered; PARG's is ordered — the compiler",
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
