# frozen_string_literal: true

require "strscan"

module Parsanol
  module PARG
    # Tokenizer for PARG source text.
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
      | (?<category>%p\{[A-Za-z]{1,2}\})
      | (?<istr>%i"(?:[^"\\]|\\.)*")
      | (?<sstr>%s"(?:[^"\\]|\\.)*")
      | (?<str>"(?:[^"\\]|\\.)*")
      | (?<arrow>->)
      | (?<num>\d+)
      | (?<ident>[A-Za-z_][A-Za-z0-9_]*)
      | (?<punct>[=\/()\[\]{}*!&:,.<-])
      /x

      # Named groups are numbered 1..n in TOKEN.names order; looking them
      # up by number avoids a name lookup per group per token.
      TYPES = TOKEN.names.map(&:to_sym).freeze

      def initialize(text, keep_layout: false)
        @text = text
        @keep_layout = keep_layout
        @tokens = []
        scan
      end

      attr_reader :tokens

      private

      # One StringScanner pass. Regexp#match(text, pos) per token cost
      # time proportional to pos, so lexing grew quadratically with the
      # source (about 5 s for a 216 KB grammar). Offsets stay character
      # offsets, counted as each token is consumed. `keep_layout` keeps
      # the ws/newline/comment tokens the parser drops — the formatter's
      # row segmentation rides them.
      def scan
        scanner = StringScanner.new(@text)
        offset = 0
        until scanner.eos?
          unless scanner.scan(TOKEN)
            raise ParseError,
                  "unexpected character #{@text[offset].inspect} at offset #{offset}"
          end

          type = matched_type(scanner)
          if type && (@keep_layout || !DROPPED.include?(type))
            value = token_value(type, scanner)
            @tokens << Token.new(type, value, offset)
          end
          offset += scanner.matched.length
        end
      end

      def matched_type(match)
        TYPES.each_with_index do |type, index|
          return type if match[index + 1]
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
