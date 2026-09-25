# frozen_string_literal: true

module Parsanol
  module PG
    # Tokenizer for PG source text.
    #
    # Emits Token structs. Comments (# to end of line) and whitespace are
    # dropped. Punctuation arrives as :punct tokens carrying the character.
    class Lexer
      Token = Struct.new(:type, :value, :offset)

      DROPPED = %i[ws comment].freeze

      TOKEN = /
        (?<newline>\r?\n)
      | (?<ws>[ \t]+)
      | (?<doc>\#\#[^\n]*)
      | (?<comment>\#[^\n]*)
      | (?<hex>%x[0-9A-Fa-f]{2,6}(?:-[0-9A-Fa-f]{2,6}|(?:\.[0-9A-Fa-f]{2,6})+)?)
      | (?<istr>%i"(?:[^"\\]|\\.)*")
      | (?<sstr>%s"(?:[^"\\]|\\.)*")
      | (?<str>"(?:[^"\\]|\\.)*")
      | (?<arrow>->)
      | (?<num>\d+)
      | (?<ident>[A-Za-z_][A-Za-z0-9_]*)
      | (?<punct>[=\/()\[\]{}*!&:,.])
      /x

      def initialize(text)
        @text = text
        @tokens = []
        scan
      end

      attr_reader :tokens

      private

      def scan
        pos = 0
        until pos >= @text.length
          match = TOKEN.match(@text, pos)
          if match.nil? || match.begin(0) != pos
            raise ParseError,
                  "unexpected character #{@text[pos].inspect} at offset #{pos}"
          end

          type = matched_type(match)
          if type && !DROPPED.include?(type)
            value = token_value(type, match)
            @tokens << Token.new(type, value, pos)
          end
          pos = match.end(0)
        end
      end

      def matched_type(match)
        TOKEN.names.each do |name|
          return name.to_sym if match[name]
        end
        nil
      end

      def token_value(type, match)
        case type
        when :hex, :istr, :sstr then match[0][2..]
        else match[0]
        end
      end
    end
  end
end
