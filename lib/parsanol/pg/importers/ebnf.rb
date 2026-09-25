# frozen_string_literal: true

module Parsanol
  module PG
    module Import
      # ISO 14977 EBNF importer.
      #
      # Semantic conversions (recorded in the emitted header):
      # - meta-identifiers are case-insensitive in ISO EBNF -> downcased
      # - terminals are exact -> emitted as plain PG strings
      # - sequence "," -> juxtaposition; "|" -> ordered "/"
      # - { x } (zero-or-more) -> *( x )
      # - syntactic exceptions "term - exception" are approximated as
      #   !( exception ) term — exact whenever the exception matches a
      #   prefix of the term's match; each occurrence is commented
      # - special sequences ? ... ? are rejected
      class Ebnf
        COMMENT = /\(\*(?:[^*]|\*(?!\)))*\*\)/m

        TOKEN = /
          (?<ws>\s+)
        | (?<squote>'[^']*')
        | (?<dquote>"[^"]*")
        | (?<special>\?[^?\n]*\?)
        | (?<name>[A-Za-z][A-Za-z0-9]*)
        | (?<punct>[=;,|()\[\]{}-])
        /x

        class << self
          def call(text)
            new(text).call
          end
        end

        def initialize(text)
          @text = text.gsub(COMMENT, "")
          @tokens = []
          @pos = 0
          @rules = {}
          @notes = []
          @current_name = nil
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
                    "EBNF: unexpected #{@text[pos].inspect} at offset #{pos}"
            end

            name = TOKEN.names.find { |n| match[n] }
            unless name == "ws"
              if name == "special"
                raise Error,
                      "EBNF: special sequence #{match[0].inspect} cannot be " \
                      "imported — express it with PG syntax"
              end
              @tokens << [name.to_sym, match[0], pos]
            end
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
            unless token[0] == :name
              raise Error, "EBNF: expected rule name, got #{token[1].inspect}"
            end

            name = normalize_name(token[1])
            equals = advance
            unless equals && equals[0] == :punct && equals[1] == "="
              raise Error, "EBNF: expected '=' after #{token[1].inspect}"
            end

            if @rules.key?(name)
              raise Error, "EBNF: duplicate rule #{name.inspect}"
            end

            @current_name = name
            @rules[name] = parse_alternation
            terminator = advance
            unless terminator && terminator[0] == :punct && terminator[1] == ";"
              raise Error, "EBNF: expected ';' after rule #{name.inspect}"
            end
          end
        end

        def parse_alternation
          parts = [parse_sequence]
          while peek&.[](0) == :punct && peek[1] == "|"
            advance
            parts << parse_sequence
          end
          parts.join(" / ")
        end

        def parse_sequence
          parts = [parse_term]
          while peek&.[](0) == :punct && peek[1] == ","
            advance
            parts << parse_term
          end
          parts.join(" ")
        end

        def parse_term
          factor = parse_factor
          if peek&.[](0) == :punct && peek[1] == "-"
            advance
            exception = parse_factor
            @notes << "rule '#{@current_name}': syntactic exception " \
                      "'#{factor} - #{exception}' approximated as " \
                      "'!(#{exception}) #{factor}'"
            "!(#{exception}) #{factor}"
          else
            factor
          end
        end

        def parse_factor
          token = advance
          raise Error, "EBNF: unexpected end of rule body" if token.nil?

          case token[0]
          when :squote, :dquote then emit_string(token[1][1..-2])
          when :name then normalize_name(token[1])
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
            when "{"
              body = parse_alternation
              expect_punct("}")
              "*(#{body})"
            else
              raise Error, "EBNF: unexpected #{token[1].inspect}"
            end
          else
            raise Error, "EBNF: unexpected token #{token[0]}"
          end
        end

        def expect_punct(char)
          token = advance
          unless token && token[0] == :punct && token[1] == char
            raise Error, "EBNF: expected #{char.inspect}"
          end
        end

        def emit_string(body)
          body.gsub("\\", "\\\\").gsub('"', '\\"').then { |escaped| "\"#{escaped}\"" }
        end

        def normalize_name(name)
          name.downcase
        end

        def emit
          lines = [
            "# Imported from ISO 14977 EBNF.",
            "# Notes:",
            "# - meta-identifiers were case-insensitive; downcased",
          ]
          @notes.each { |note| lines << "# - #{note}" }
          lines << "grammar imported_ebnf version \"0.0.0\" {"
          lines.concat(@rules.map { |name, body| "  #{name} = #{body}" })
          lines << "}"
          "#{lines.join("\n")}\n"
        end
      end
    end
  end
end
