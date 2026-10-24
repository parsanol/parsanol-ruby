# frozen_string_literal: true

# ruby#321 slice 2: a strict parser + whole-input matcher for the
# EXPORTED EBNF dialect (test tool, deliberately disposable — the B2
# validator precedent). Parses what PARG::Export::Xgrammar emits —
# one rule, "literals", [\xHH-\xHH] classes, ( ... ), |, and the
# * + ? {m,n} suffixes — and matches inputs. The differential spec
# replays the corpus's acceptance sets through it: the lowering's
# language equivalence pinned from OUR side (the external half — the
# actual XGrammar runtime — is the follow-up slice).
module EbnfMatcher
  class Error < StandardError
  end

  class << self
    # Returns a match tree for a single "name ::= expr" rule text.
    def parse(text)
      _name, expr = text.strip.split("::=", 2)
      raise Error, "no ::= in export" unless expr

      parser = Parser.new(expr.strip)
      node = parser.expr
      parser.expect_end
      node
    end

    def matches?(node, input)
      match(node, input, 0) == input.length
    end
  end

  Node = Struct.new(:kind, :a, :b)

  class Parser
    def initialize(text)
      @text = text
      @pos = 0
    end

    def expr
      alts = [sequence]
      alts << sequence while accept?("|")
      alts.length == 1 ? alts.first : Node.new(:alt, alts)
    end

    def sequence
      items = []
      while (item = primary_with_suffix)
        items << item
      end
      raise Error, "empty sequence at #{@pos}" if items.empty?

      items.length == 1 ? items.first : Node.new(:seq, items)
    end

    def primary_with_suffix
      skip_ws
      primary = case peek
                when "(" then group
                when '"' then literal
                when "[" then char_class
                when nil, ")", "|", /\s/ then nil
                else raise Error, "unexpected #{peek.inspect} at #{@pos}"
                end
      return nil unless primary

      apply_suffix(primary)
    end

    def group
      expect("(")
      node = expr
      expect(")")
      node
    end

    def literal
      expect('"')
      chars = []
      chars << read_char until peek == '"'
      expect('"')
      Node.new(:lit, chars.join)
    end

    def char_class
      expect("[")
      ranges = []
      until peek == "]"
        lo = read_char
        if peek == "-"
          expect("-")
          hi = read_char
          ranges << [lo.ord, hi.ord]
        else
          ranges << [lo.ord, lo.ord]
        end
      end
      expect("]")
      Node.new(:class, ranges)
    end

    # A "character" is one source char or a \xHH / \n / \t / \r escape
    # or an escaped quote/backslash.
    def read_char
      raise Error, "unexpected end of export" unless peek

      char = advance
      return char unless char == "\\"

      case peek
      when "x"
        advance
        hex = advance + advance
        hex.hex.chr(Encoding::UTF_8)
      when "n" then advance && "\n"
      when "t" then advance && "\t"
      when "r" then advance && "\r"
      else advance
      end
    end

    def apply_suffix(node)
      case peek
      when "*"
        advance
        Node.new(:rep, node, [0, nil])
      when "+"
        advance
        Node.new(:rep, node, [1, nil])
      when "?"
        advance
        Node.new(:rep, node, [0, 1])
      when "{"
        expect("{")
        min = number
        max = if peek == ","
                advance
                peek == "}" ? nil : number
              else
                min
              end
        expect("}")
        Node.new(:rep, node, [min, max])
      else
        node
      end
    end

    def number
      digits = +""
      digits << advance while peek && peek =~ /\d/
      raise Error, "bad repetition bound at #{@pos}" if digits.empty?

      digits.to_i
    end

    def peek
      @text[@pos]
    end

    def advance
      char = @text[@pos]
      @pos += 1
      char
    end

    def accept?(char)
      skip_ws
      return false unless peek == char

      advance
      true
    end

    def skip_ws
      @pos += 1 while peek && peek =~ /\s/
    end

    def expect(char)
      skip_ws
      raise Error, "expected #{char.inspect} at #{@pos}, got #{peek.inspect}" unless peek == char

      advance
    end

    def expect_end
      skip_ws
      raise Error, "trailing input at #{@pos}: #{@text[@pos, 24].inspect}" unless @pos >= @text.length
    end
  end

  # Matcher: each construct returns the end position on success, nil
  # on failure. Repetition tracks endings PER REP COUNT so min/max are
  # exact; a zero-width iteration counts once and stops expansion (the
  # engines' empty-iteration law).
  class << self
    def match(node, input, pos)
      case node.kind
      when :lit
        text = node.a
        input[pos, text.length] == text && (pos + text.length)
      when :class
        return nil unless pos < input.length

        code = input[pos].ord
        node.a.any? { |lo, hi| code.between?(lo, hi) } && (pos + 1)
      when :seq
        node.a.reduce(pos) { |current, child| current && match(child, input, current) }
      when :alt
        node.a.each do |branch|
          if (end_pos = match(branch, input, pos))
            return end_pos
          end
        end
        nil
      when :rep
        min, max = node.b
        endings = { 0 => [pos] }
        reps = 0
        loop do
          break if max && reps == max

          next_endings = {}
          endings[reps].each do |start|
            if (e = match(node.a, input, start))
              next_endings[e] = true
            end
          end
          break if next_endings.empty?

          reps += 1
          endings[reps] = next_endings.keys
          # No-progress guard: every iteration of the last round
          # consumed nothing — further rounds cannot differ.
          break if next_endings.keys.length == 1 && next_endings.key?(endings[reps - 1].first) &&
            endings[reps].all? { |e| endings[reps - 1].include?(e) }
        end
        valid = endings.flat_map { |count, positions| count >= min ? positions : [] }
        valid.max
      end
    end
  end
end
