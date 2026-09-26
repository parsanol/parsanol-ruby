# frozen_string_literal: true

module Parsanol
  module PG
    # Recursive-descent parser for PG source text.
    #
    #   grammar PubidIso version "1.2.0" {
    #     digit = %x30-39
    #     year  = 4digit
    #     root  = %i"iso" [dash number as part]
    #   }
    #
    # Keywords: grammar version as alt from_table column bindings
    #           preprocess entry table_lookup
    class Parser
      PATH_CONTINUATION = [".", "["].freeze
      CARD_CONTINUATION = [".", "*"].freeze

      IN_BLOCK_SECTIONS = %w[entry bindings preprocess test].freeze

      KEYWORDS = %w[grammar as alt from_table column bindings
                    preprocess entry table_lookup].freeze

      def initialize(text)
        @tokens = Lexer.new(text).tokens
        @pos = 0
        @source_text = text
      end

      def parse
        document = Document.new
        document.source = @source_text
        skip_newlines
        until eof?
          take_doc_comments
          break if eof?

          section = expect(:ident)
          case section.value
          when "use" then document.uses << ident.value
          when "grammar" then parse_grammar(document)
          when "entry" then parse_entry(document)
          when "bindings" then parse_bindings(document)
          when "preprocess" then parse_preprocess(document)
          when "test" then parse_test(document)
          else
            raise ParseError,
                  "expected a section (grammar/entry/bindings/preprocess/test), " \
                  "got #{section.value.inspect} at offset #{section.offset}"
          end
          skip_newlines
        end
        document.validate!
        document.own_entries = document.entries.keys
        document
      end

      private

      def skip_newlines
        advance while peek&.type == :newline
      end

      # Doc comments (##) accumulate and attach to the next rule.
      def take_doc_comments
        docs = []
        while peek&.type == :doc
          docs << advance.value[2..].strip
          skip_newlines
        end
        docs
      end

      def parse_test(document, default_entry: nil)
        entry = peek&.type == :ident && peek.value != "{" ? advance.value : default_entry
        punct("{")
        skip_newlines
        until peek&.type == :punct && peek.value == "}"
          kind = ident.value
          input = unquote(expect(:str).value)
          expect_pairs = {}
          if kind == "example" && peek&.type == :punct && peek.value == "{"
            advance
            skip_newlines
            until peek&.type == :punct && peek.value == "}"
              key = ident.value
              punct(":")
              expect_pairs[key.to_sym] = parse_test_value
              skip_newlines
            end
            punct("}")
          end
          document.tests << Document::Test.new(entry, kind.to_sym, input, expect_pairs)
          skip_newlines
        end
        punct("}")
        skip_newlines
      end

      def parse_test_value
        token = advance
        case token&.type
        when :str then unquote(token.value)
        when :num then token.value.to_i
        when :ident
          raise ParseError, "expected true or false" unless %w[true false].include?(token.value)

          token.value == "true"
        else
          raise ParseError, "expected a string, number, true or false"
        end
      end

      def eof? = @pos >= @tokens.length

      def peek = @tokens[@pos]

      def advance
        token = @tokens[@pos]
        @pos += 1
        token
      end

      def expect(type, value = nil)
        token = advance
        if token.nil? || token.type != type || (value && token.value != value)
          found = token ? "#{token.type}:#{token.value.inspect}" : "EOF"
          raise ParseError,
                "expected #{value ? value.inspect : type}, got #{found}"
        end
        token
      end

      def ident(value = nil) = expect(:ident, value)

      def punct(char) = expect(:punct, char)

      def parse_grammar(document)
        document.grammar_name = ident.value
        ident("version")
        document.version = unquote(expect(:str).value)
        punct("{")
        skip_newlines
        until peek&.type == :punct && peek.value == "}"
          docs = take_doc_comments
          break if peek.nil? || (peek&.type == :punct && peek.value == "}")

          # Sections may be authored inside the grammar block: the
          # natural placement for entry/bindings/preprocess/test.
          if peek&.type == :ident && IN_BLOCK_SECTIONS.include?(peek.value)
            section = advance
            case section.value
            when "entry" then parse_entry(document)
            when "bindings" then parse_bindings(document)
            when "preprocess" then parse_preprocess(document)
            when "test" then parse_test(document)
            end
            skip_newlines
            next
          end
          name = rule_name
          document.docs[name] = docs.join("\n") unless docs.empty?
          punct("=")
          node = parse_choice
          if document.rules.key?(name)
            raise ParseError, "duplicate rule #{name.inspect}"
          end

          document.rules[name] = node
          skip_newlines
        end
        punct("}")
      end

      def rule_name
        token = ident
        if KEYWORDS.include?(token.value)
          raise ParseError,
                "#{token.value.inspect} is a keyword and cannot name a rule"
        end
        token.value
      end

      def parse_choice
        branches = [parse_seq]
        while peek&.type == :punct && peek.value == "/"
          advance
          branches << parse_seq
        end
        branches.length == 1 ? branches.first : Node.new(:alt, branches)
      end

      def parse_seq
        items = [parse_element]
        until stop_element?
          items << parse_element
        end
        items.length == 1 ? items.first : Node.new(:seq, items)
      end

      def stop_element?
        peek.nil? || peek.type == :newline ||
          (peek.type == :punct && ["/", ")", "]", "}"].include?(peek.value))
      end

      def parse_element
        token = peek
        if token.nil?
          raise ParseError, "unexpected end of input inside sequence"
        end

        if token.type == :num
          advance
          min = token.value.to_i
          if peek&.type == :punct && peek.value == "*"
            advance
            max = peek&.type == :num ? advance.value.to_i : nil
            node = Node.new(:rep, parse_postfixed, min, max)
          else
            node = Node.new(:rep, parse_postfixed, min, min)
          end
          return node
        elsif token.type == :punct && token.value == "*"
          advance
          max = peek&.type == :num ? advance.value.to_i : nil
          return Node.new(:rep, parse_postfixed, 0, max)
        end
        parse_postfixed
      end

      def parse_postfixed
        sign = nil
        if peek&.type == :punct && %w[! &].include?(peek.value)
          sign = advance.value == "&"
        end
        node = parse_primary
        if peek&.type == :ident && peek.value == "as"
          advance
          node = Node.new(:cap, ident.value, node)
        end
        sign.nil? ? node : Node.new(:pred, sign, node)
      end

      def parse_primary
        token = advance
        raise ParseError, "unexpected end of input" if token.nil?

        case token.type
        when :str, :sstr then Node.new(:lit, unquote(token.value), false)
        when :istr then Node.new(:lit, unquote(token.value), true)
        when :hex then parse_hex(token.value)
        when :punct then parse_punctuated(token)
        when :ident then parse_ident(token)
        else raise ParseError, "unexpected token #{token.type}:#{token.value}"
        end
      end

      def parse_punctuated(token)
        case token.value
        when "("
          node = parse_choice
          punct(")")
          node
        when "["
          node = parse_choice
          punct("]")
          Node.new(:opt, node)
        else
          raise ParseError, "unexpected #{token.value.inspect} in expression"
        end
      end

      def parse_ident(token)
        case token.value
        when "alt"
          ident("from_table")
          table = unquote(expect(:str).value)
          ident("column")
          column = unquote(expect(:str).value)
          Node.new(:table, table, column)
        when *KEYWORDS
          raise ParseError,
                "#{token.value.inspect} is a keyword and cannot be referenced"
        else
          name = token.value
          # Dotted cross-grammar references: `use cen_cenelec` makes
          # cen_cenelec.identifier addressable.
          while peek&.type == :punct && peek.value == "." &&
              @tokens[@pos + 1]&.type == :ident
            advance
            name = "#{name}.#{advance.value}"
          end
          Node.new(:ref, name)
        end
      end

      def parse_hex(spec)
        if spec.include?("-")
          lo, hi = spec.split("-")
          Node.new(:class, [[lo.to_i(16), hi.to_i(16)]])
        elsif spec.include?(".")
          parts = spec.split(".").map { |h| Node.new(:class, [[h.to_i(16), h.to_i(16)]]) }
          parts.length == 1 ? parts.first : Node.new(:seq, parts)
        else
          byte = spec.to_i(16)
          Node.new(:class, [[byte, byte]])
        end
      end

      def parse_entry(document)
        name = ident.value
        punct(":")
        document.entries[name] = rule_name
      end

      def parse_bindings(document)
        rule = ident.value
        punct("{")
        list = document.bindings[rule] ||= []
        skip_newlines
        until peek&.type == :punct && peek.value == "}"
          capture = ident.value
          expect(:arrow)
          path = parse_path
          type = "string"
          card = nil
          preprocess = nil
          if peek&.type == :punct && peek.value == "("
            advance
            type = ident.value
            if peek&.type == :punct && peek.value == ","
              advance
              card = parse_card
            end
            punct(")")
          end
          if peek&.type == :ident && peek.value == "preprocess"
            advance
            punct(":")
            preprocess = ident.value
          end
          list << Document::Binding.new(capture, path, type, card, preprocess)
          skip_newlines
        end
        punct("}")
      end

      def parse_path
        parts = [ident.value]
        loop do
          token = peek
          break unless token&.type == :punct && PATH_CONTINUATION.include?(token.value)

          advance
          if token.value == "."
            parts << ".#{ident.value}"
          else
            punct("]")
            parts << "[]"
          end
        end
        parts.join
      end

      def parse_card
        pieces = []
        loop do
          token = peek
          break unless token&.type == :num ||
            (token&.type == :punct && CARD_CONTINUATION.include?(token.value))

          pieces << advance.value
        end
        pieces.join
      end

      def parse_preprocess(document)
        name = ident.value
        punct("{")
        steps = document.preprocess[name] ||= []
        skip_newlines
        until peek&.type == :punct && peek.value == "}"
          op = ident("table_lookup").value
          table = ident.value
          from = ident.value
          expect(:arrow)
          to = ident.value
          steps << { "op" => op, "table" => table, "from" => from, "to" => to }
          skip_newlines
        end
        punct("}")
      end

      def unquote(raw)
        body = raw.start_with?("%") ? raw[2..] : raw
        body = body[1..-2]
        body.gsub(/\\(.)/) do
          case Regexp.last_match(1)
          when "n" then "\n"
          when "t" then "\t"
          when "r" then "\r"
          else Regexp.last_match(1)
          end
        end
      end
    end
  end
end
