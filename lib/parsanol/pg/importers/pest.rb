# frozen_string_literal: true

module Parsanol
  module PG
    module Import
      # pest (Rust PEG) importer — the common subset, mapped to PG.
      #
      # Conversions:
      # - ordered choice "|", predicates "!"/"&", postfix "*"/"+"/"?" map
      #   directly (PG: *x / 1*x / [ x ])
      # - "lit" exact; ^"lit" case-insensitive -> %i"..."
      # - 'a'..'z' ranges -> %x61-7A
      # - builtin character classes (ASCII_DIGIT, ...) -> %x ranges
      # - "a" ~ "b": pest inserts implicit WHITESPACE at ~; PG emits plain
      #   sequence — whitespace must be explicit (recorded in the header)
      # - rule modifiers _/@/$ are accepted and noted (PG captures stay
      #   enabled inside them); silent name_ rules keep their name
      # - PUSH/POP/PEEK/EOI/SOI and the implicit WHITESPACE/Comment rules
      #   are rejected with an explanatory error
      class Pest
        TOKEN = /
          (?<ws>\s+)
        | (?<comment>\/\/[^\n]*)
        | (?<insens>\^(?:"(?:[^"\\]|\\.)*"|i"(?:[^"\\]|\\.)*"))
        | (?<str>"(?:[^"\\]|\\.)*")
        | (?<range>'(?:[^'\\]|\\.)'\.\.'(?:[^'\\]|\\.)')
        | (?<ident>[A-Za-z_][A-Za-z0-9_]*)
        | (?<punct>[|~!&*+?(){}=@$])
        /x

        BUILTINS = {
          "ANY" => "%x00-FF",
          "ASCII_DIGIT" => "%x30-39",
          "ASCII_NONZERO_DIGIT" => "%x31-39",
          "ASCII_BIN_DIGIT" => "%x30-31",
          "ASCII_OCT_DIGIT" => "%x30-37",
          "ASCII_HEX_DIGIT" => "%x30-39 / %x41-46 / %x61-66",
          "ASCII_ALPHA" => "%x41-5A / %x61-7A",
          "ASCII_ALPHA_LOWER" => "%x61-7A",
          "ASCII_ALPHA_UPPER" => "%x41-5A",
          "ASCII_ALPHANUMERIC" => "%x30-39 / %x41-5A / %x61-7A",
          "NEWLINE" => '"\n" / "\r\n"',
        }.freeze

        SKIPPED_NAMES = %w[ws comment].freeze
        MODIFIER_CHARS = %w[_ @ $].freeze

        REJECTED = %w[SOI EOI WHITESPACE COMMENT PUSH POP PEEK PEEK_ALL DROP
                      RESET].freeze

        class << self
          def call(text)
            new(text).call
          end
        end

        def initialize(text)
          @tokens = []
          @pos = 0
          @rules = {}
          @notes = []
          scan(text)
        end

        def call
          parse_rules
          emit
        end

        private

        def scan(text)
          pos = 0
          until pos >= text.length
            match = TOKEN.match(text, pos)
            if match.nil? || match.begin(0) != pos
              raise Error,
                    "pest: unexpected #{text[pos].inspect} at offset #{pos}"
            end

            name = TOKEN.names.find { |n| match[n] }
            @tokens << [name.to_sym, match[0], pos] unless SKIPPED_NAMES.include?(name)
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

        def parse_rules
          until peek.nil?
            token = advance
            unless token[0] == :ident
              raise Error, "pest: expected rule name, got #{token[1].inspect}"
            end

            name = token[1]
            if REJECTED.include?(name)
              raise Error,
                    "pest: #{name} is not importable — " \
                    "#{name == 'WHITESPACE' ? 'pest applies it implicitly; define whitespace explicitly in PG' : 'express it in PG syntax'}"
            end
            @notes << "silent rule #{name.inspect} imported as a normal rule" if name.end_with?("_")
            equals = advance
            unless equals && equals[0] == :punct && equals[1] == "="
              raise Error, "pest: expected '=' after #{name.inspect}"
            end

            nil
            if peek&.[](0) == :punct && MODIFIER_CHARS.include?(peek[1])
              modifier = advance[1]
              @notes << "rule #{name.inspect}: modifier #{modifier.inspect} " \
                        "accepted; PG captures stay enabled inside it"
            end
            expect_punct("{")
            if @rules.key?(name)
              raise Error, "pest: duplicate rule #{name.inspect}"
            end

            @rules[name] = parse_alt
            expect_punct("}")
          end
        end

        def parse_alt
          branches = [parse_seq]
          while peek&.[](0) == :punct && peek[1] == "|"
            advance
            branches << parse_seq
          end
          branches.length == 1 ? branches.first : Node.new(:alt, branches)
        end

        def parse_seq
          items = [parse_prefixed]
          until seq_stops?
            items << parse_prefixed
          end
          items.length == 1 ? items.first : Node.new(:seq, items)
        end

        def seq_stops?
          token = peek
          return true if token.nil?

          token[0] == :punct && %w[| ) }].include?(token[1])
        end

        def parse_prefixed
          sign = nil
          if peek&.[](0) == :punct && %w[! &].include?(peek[1])
            sign = advance[1] == "&"
          end
          node = parse_suffixed
          sign.nil? ? node : Node.new(:pred, sign, node)
        end

        def parse_suffixed
          node = parse_primary
          op = peek
          return node unless op&.[](0) == :punct && %w[* + ?].include?(op[1])

          advance
          case op[1]
          when "*" then Node.new(:rep, node, 0, nil)
          when "+" then Node.new(:rep, node, 1, nil)
          else Node.new(:opt, node)
          end
        end

        def parse_primary
          token = advance
          raise Error, "pest: unexpected end of rule body" if token.nil?

          case token[0]
          when :str then Node.new(:lit, unescape(token[1][1..-2]), false)
          when :insens
            body = token[1][1..]
            body = body[1..] if body.start_with?("i")
            Node.new(:lit, unescape(body[1..-2]), true)
          when :range
            lo = token[1][1]
            hi = token[1][-2]
            Node.new(:class, [[lo.ord, hi.ord]])
          when :ident
            if BUILTINS.key?(token[1])
              parse_builtin(token[1])
            elsif REJECTED.include?(token[1])
              raise Error,
                    "pest: #{token[1]} is not importable — " \
                    "#{token[1] == 'WHITESPACE' ? 'pest applies it implicitly; define whitespace explicitly in PG' : 'express it in PG syntax'}"
            else
              Node.new(:ref, token[1])
            end
          when :punct
            if token[1] == "("
              node = parse_alt
              expect_punct(")")
              node
            elsif token[1] == "~"
              unless @noted_tilde
                @notes << "~ treated as plain sequence (pest inserts implicit " \
                          "WHITESPACE; PG does not)"
              end
              @noted_tilde = true
              Node.new(:lit, " ", false)
            else
              raise Error, "pest: unexpected #{token[1].inspect}"
            end
          else
            raise Error, "pest: unexpected token #{token[0]}"
          end
        end

        def parse_builtin(name)
          spec = BUILTINS.fetch(name)
          branches = spec.split(" / ").map do |part|
            if part.start_with?("%x")
              parse_hex_node(part)
            else
              Node.new(:lit, unescape(part[1..-2]), false)
            end
          end
          branches.length == 1 ? branches.first : Node.new(:alt, branches)
        end

        def parse_hex_node(spec)
          body = spec[2..]
          if body.include?("-")
            lo, hi = body.split("-")
            Node.new(:class, [[lo.to_i(16), hi.to_i(16)]])
          else
            byte = body.to_i(16)
            Node.new(:class, [[byte, byte]])
          end
        end

        def expect_punct(char)
          token = advance
          unless token && token[0] == :punct && token[1] == char
            raise Error, "pest: expected #{char.inspect}"
          end
        end

        def unescape(body)
          body.gsub(/\\(.)/) do
            case Regexp.last_match(1)
            when "n" then "\n"
            when "t" then "\t"
            when "r" then "\r"
            when "0" then "\0"
            else Regexp.last_match(1)
            end
          end
        end

        # ---- emission ------------------------------------------------------

        def emit
          lines = [
            "# Imported from pest (Rust PEG).",
            "# Notes:",
            "# - ordered choice and predicates map directly",
          ]
          @notes.each { |note| lines << "# - #{note}" }
          lines << "grammar imported_pest version \"0.0.0\" {"
          lines.concat(@rules.map { |name, node| "  #{name} = #{emit_node(node, :top)}" })
          lines << "}"
          "#{lines.join("\n")}\n"
        end

        def emit_node(node, context)
          case node.kind
          when :lit then emit_string(node.a, fold: node.b)
          when :class
            node.a.map { |lo, hi| "%x#{lo.to_s(16)}-#{hi.to_s(16)}" }.join(" ")
          when :ref then node.a
          when :alt
            text = node.a.map { |branch| emit_node(branch, :branch) }.join(" / ")
            context == :branch ? "(#{text})" : text
          when :seq
            text = node.a.map { |item| emit_node(item, :seq_item) }.join(" ")
            context == :branch ? "(#{text})" : text
          when :rep
            prefix = node.b.zero? ? "*" : "#{node.b}*"
            "#{prefix}#{emit_operand(node.a)}"
          when :opt then "[ #{emit_node(node.a, :top)} ]"
          when :pred
            "#{node.a ? '&' : '!'}#{emit_operand(node.b)}"
          end
        end

        def emit_operand(node)
          case node.kind
          when :lit, :class, :ref then emit_node(node, :top)
          else "(#{emit_node(node, :top)})"
          end
        end

        def emit_string(body, fold:)
          escaped = body.gsub("\\", "\\\\").gsub('"', '\\"')
          fold ? "%i\"#{escaped}\"" : "\"#{escaped}\""
        end
      end
    end
  end
end
