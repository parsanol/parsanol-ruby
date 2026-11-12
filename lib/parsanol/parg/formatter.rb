# frozen_string_literal: true

module Parsanol
  module PARG
    # `parg fmt` — the canonical formatter for PARG sources (ruby#494).
    #
    # A layout-aware token walk, not a re-writer: the source lexes with
    # the keep-layout mode (every token the parser drops — whitespace,
    # newlines, `#` comments — stays in the stream), the walk segments
    # the stream into statements on bracket depth, and each statement
    # re-emits under fixed spacing, nesting, and blank-line rules.
    # Token ORDER never changes, so the formatter cannot alter
    # semantics — and the gates prove it anyway: recompiling a
    # formatted source yields the same `semantics_hash`, and formatting
    # twice is the identity.
    #
    # Canonical form: rules start on their own line at two-space
    # nesting; `x = { ... }` alternative groups break at each top-level
    # `/` of the group, one level deeper than the brace; `bindings`/
    # `preprocess` bodies keep their source rows (they are
    # line-oriented) with arrows aligned; `##` doc comments attach
    # verbatim above their statement at the statement's indent; one
    # blank line before each section keyword (`entry`/`test`/
    # `bindings`/`preprocess`/`derive`) and before the grammar header.
    # An unparseable file raises the parser's error — never a partial
    # reformat.
    module Formatter
      SECTION_KEYWORDS = %w[entry test bindings preprocess derive].freeze
      STATEMENT_KEYWORDS = (%w[resync] + SECTION_KEYWORDS).freeze
      LAYOUT = %i[newline ws comment doc].freeze
      INLINE_COMMENT = %i[comment doc].freeze
      COMMENT_HEAD = (LAYOUT + INLINE_COMMENT).freeze
      NO_SPACE_AFTER = ["(", "[", "!", "&", "."].freeze
      NO_SPACE_BEFORE = [")", "]", ",", ":", "."].freeze
      INDENT = "  "

      module_function

      # The canonical text for a PARG source. Raises ParseError when the
      # source does not parse — a formatter never reformats garbage.
      def format(source)
        Parser.new(source).parse
        tokens = Lexer.new(source, keep_layout: true).tokens
        restore_raw!(tokens, source)
        render_segments(segments(tokens))
      end

      # The parser-facing lexer strips the %x/%i/%s prefixes (the value
      # is the pattern); the formatter emits source text verbatim, so
      # every token's value becomes its exact source slice.
      def restore_raw!(tokens, source)
        tokens.each_with_index do |token, index|
          following = tokens[index + 1]
          raw = source[token.offset...(following ? following.offset : source.length)].rstrip
          token.value = raw unless raw.empty?
        end
      end

      # -- segmentation ------------------------------------------------------

      # [depth, tokens] statements: depth is the bracket depth at the
      # statement's first real token (the grammar body lives at 1). A
      # statement starts at depth 0 (top level: header comments, `use`,
      # the `grammar` header, the final `}`) or at depth 1 after a
      # line break on a statement starter.
      def segments(tokens)
        out = []
        current = []
        depth = 0
        seg_depth = 0
        at_line_start = true
        pending = []
        tokens.each_with_index do |token, index|
          case token.type
          when :newline
            # Newlines ride inside the statement (row-oriented renderers
            # segment on them); the parser-facing renderers skip them.
            # A pending comment TRAILS the line only when tokens
            # precede it on the line; after a break it stays pending
            # (it leads whatever comes next).
            unless pending.empty? || current.last&.type == :newline
              current.concat(pending)
              pending = []
            end
            current << token
            at_line_start = true if depth <= 1
            next
          when :ws
            next
          when :comment, :doc
            pending << token
            next
          end
          if statement_starts?(token, depth, current, at_line_start, next_real(tokens, index))
            flush(out, current, seg_depth)
            seg_depth = depth
            # comments collected since the last real token LEAD the new
            # statement (## doc blocks above a rule)
            current.concat(pending)
            pending = []
          elsif pending.any?
            # mid-statement comments: an interior `#` line or a
            # trailing `# why` — they ride with the statement
            current.concat(pending)
            pending = []
          end
          current << token
          depth += bracket_delta(token)
          at_line_start = false
        end
        flush_trailing(out, current, pending, seg_depth)
        out
      end

      # A statement opens when: at the top level, the token is a
      # comment, a `use`/`grammar` head, or the grammar's closing brace;
      # or inside the grammar body (depth 1) after a line break, the
      # token is a comment, a section/resync keyword, a `}` closer, or
      # an identifier directly followed by `=` (a rule head).
      def statement_starts?(token, depth, _current, at_line_start, following)
        if depth.zero?
          case token.type
          when :doc, :comment then true
          when :ident then %w[use grammar].include?(token.value)
          when :punct then token.value == "}"
          else false
          end
        else
          return false unless at_line_start

          case token.type
          when :doc, :comment then true
          when :punct then token.value == "}"
          when :ident
            return true if STATEMENT_KEYWORDS.include?(token.value)

            following&.type == :punct && following.value == "="
          else false
          end
        end
      end

      def next_real(tokens, index)
        tokens[(index + 1)..].find { |t| !LAYOUT.include?(t.type) }
      end

      def bracket_delta(token)
        return 0 unless token.type == :punct

        case token.value
        when "{", "(", "[" then 1
        when "}", ")", "]" then -1
        else 0
        end
      end

      def flush(out, current, depth)
        out << [depth, current.dup] unless current.empty?
        current.clear
      end

      def flush_trailing(out, current, pending, depth)
        current.concat(pending)
        pending.clear
        out << [depth, current.dup] unless current.empty?
        current.clear
      end

      # -- emission ----------------------------------------------------------

      def render_segments(segments)
        out = +""
        previous_kind = nil
        segments.each do |depth, tokens|
          comments = tokens.take_while { |t| INLINE_COMMENT.include?(t.type) }
          body = tokens.drop(comments.length)
          kind = classify(body)
          out << "\n" if blank_line_before?(kind, previous_kind) && comments.empty?
          indent = indent_for(depth, body, kind)
          comments.each do |comment|
            out << indent << comment.value.rstrip << "\n"
          end
          out << indent << render_statement(body, depth, kind) << "\n"
          previous_kind = kind
        end
        out
      end

      def classify(tokens)
        head = tokens.find { |t| !COMMENT_HEAD.include?(t.type) }
        case head&.type
        when nil then :comment
        when :ident
          return head.value.to_sym if %w[grammar use entry test bindings preprocess derive resync].include?(head.value)

          :rule
        else
          :other
        end
      end

      def blank_line_before?(kind, previous_kind)
        return false if previous_kind.nil?
        return true if kind == :grammar
        return false if previous_kind == :comment

        SECTION_KEYWORDS.include?(kind.to_s)
      end

      # The statement's base indent: top-level statements (header
      # comments, `use`, the `grammar` header) sit at the margin; the
      # grammar body lives at depth 1 and indents one level. The lone
      # `}` closing the grammar block decrements first — it indents at
      # depth - 1.
      def indent_for(depth, tokens, kind)
        if kind == :other && tokens.first&.type == :punct && tokens.first&.value == "}"
          return INDENT * [depth - 1, 0].max
        end

        INDENT * depth
      end

      def render_statement(tokens, depth, kind)
        case kind
        when :comment
          render_comment_only(tokens)
        when :rule, :resync then render_rule(tokens, depth)
        when :bindings, :preprocess then render_rows(tokens, depth, aligned: true)
        when :test then render_rows(tokens, depth, aligned: false)
        else render_inline(tokens)
        end
      end

      # One rule-pattern token walk: braces drive the nesting, the
      # brace-group slash breaks, comments keep their stream position,
      # everything else emits with canonical spacing.
      RuleState = Struct.new(:out, :base, :level, :previous, :groups,
                             :at_line_start)

      def render_rule(tokens, depth)
        state = RuleState.new(+"", INDENT * depth, 0, nil, [], false)
        tokens.each_with_index do |token, index|
          case token.type
          when :comment, :doc
            render_rule_comment(state, token, tokens, index)
          when :ws, :newline
            nil
          when :punct
            next if render_rule_brace?(state, token)

            emit_rule_token(state, token)
          else
            emit_rule_token(state, token)
          end
        end
        state.out
      end

      # A comment keeps its stream position: after a newline it owns
      # the line and whatever follows starts fresh (a comment eats to
      # end of line — anything glued after it would be swallowed);
      # otherwise it trails the line it sits on.
      def render_rule_comment(state, token, tokens, index)
        first = index.zero? || tokens[index - 1]&.type == :newline
        if first
          state.out << "\n" unless state.out.empty? || state.out.end_with?("\n")
          state.out << (state.base + (INDENT * state.level)) << token.value.rstrip
          state.at_line_start = true
        else
          state.out << "  " << token.value.rstrip
        end
      end

      # Braces, the group-leading slash, and the bracket stack return
      # true (fully handled); a plain operator falls through to the
      # ordinary emitter.
      def render_rule_brace?(state, token)
        case token.value
        when "{"
          state.out << spacing(state.previous, token) << token.value << "\n"
          state.level += 1
          state.groups.push("{")
          state.previous = token
          state.at_line_start = true
          true
        when "}"
          state.level -= 1
          state.groups.pop
          state.out << "\n" << (state.base + (INDENT * state.level)) << token.value
          state.previous = token
          state.at_line_start = false
          true
        when "/"
          if state.groups.last == "{"
            # A top-level alternative of the brace group: the slash
            # leads the continuation line at the group's indent.
            # Slashes inside parenthesized sub-expressions stay inline
            # — the parser reads them there.
            state.out << "\n" << (state.base + (INDENT * state.level)) << token.value
            state.previous = token
            true
          else
            false
          end
        when "(", "["
          state.groups.push(token.value)
          false
        when ")", "]"
          state.groups.pop
          false
        else
          false
        end
      end

      # The ordinary emitter: a fresh line at the current indent when
      # at line start, canonical spacing otherwise.
      def emit_rule_token(state, token)
        if state.at_line_start
          state.out << "\n" unless state.out.empty? || state.out.end_with?("\n")
          state.out << (state.base + (INDENT * state.level))
          state.at_line_start = false
        else
          state.out << spacing(state.previous, token)
        end
        state.out << token.value
        state.previous = token
      end

      # A comment-only statement (a header comment block line).
      def render_comment_only(tokens)
        tokens.filter_map do |token|
          token.value.rstrip if INLINE_COMMENT.include?(token.type)
        end.join("\n")
      end

      # `##` doc comments and `#` comments ride as their own statements
      # (or attached heads) and emit verbatim at the statement's indent.
      def render_comments(tokens, indent)
        out = +""
        tokens.each do |token|
          next unless INLINE_COMMENT.include?(token.type)

          out << (out.empty? ? indent : "\n#{indent}") << token.value.rstrip
        end
        out
      end

      # The default: canonical single spacing, layout tokens skipped,
      # trailing comments kept on the line.
      def render_inline(tokens)
        out = +""
        previous = nil
        tokens.each do |token|
          next if LAYOUT.include?(token.type)

          if INLINE_COMMENT.include?(token.type)
            out << "  " << token.value.rstrip
            next
          end
          out << spacing(previous, token) << token.value
          previous = token
        end
        out
      end

      # The lexer emits `->` as its own :arrow type.
      def arrow_token?(token)
        token.type == :arrow || (token.type == :punct && token.value == "->")
      end

      # The column the arrow occupies: the rendered width of everything
      # before the `->`.
      def arrow_column(row)
        width = 0
        previous = nil
        row.each do |token|
          return width if arrow_token?(token)

          width += spacing(previous, token).length + token.value.length
          previous = token
        end
        nil
      end

      def leading_width(row)
        width = 0
        previous = nil
        row.each do |token|
          break if arrow_token?(token)

          width += spacing(previous, token).length + token.value.length
          previous = token
        end
        width
      end

      # Line-oriented bodies (bindings, preprocess, test): the header
      # runs through the `{`; the body keeps its source row boundaries
      # (rows are semantic units — one binding, one op, one test case);
      # `#` comments render verbatim at the body indent; bindings and
      # preprocess rows align their arrows on the widest left side.
      def render_rows(tokens, depth, aligned:)
        body_indent = INDENT * (depth + 1)
        closer_indent = INDENT * depth
        header = []
        rows = [[]]
        tokens.each do |token|
          case token.type
          when :newline
            rows << [] unless header.empty? && rows.last.empty?
            next
          when :ws
            next
          end
          if header.empty? || header.last.type != :punct || header.last.value != "{"
            header << token
          else
            rows.last << token
          end
        end
        # The block's own closing brace: a lone-`}` row, or riding the
        # end of the final row (a one-line body) — split it off so the
        # closer always renders on its own line.
        closer = rows.rindex { |row| row.length == 1 && row.first&.type == :punct && row.first&.value == "}" }
        rider = rows.rindex { |row| row.last&.type == :punct && row.last&.value == "}" }
        if closer
          body = (rows[0...closer] || []).reject(&:empty?)
        elsif rider
          body = (rows[0...rider] || []).reject(&:empty?)
          tail = rows[rider][0...-1]
          body << tail unless tail.empty?
        else
          body = rows.reject(&:empty?)
        end
        arrows = aligned ? body.filter_map { |row| arrow_column(row) }.max : nil
        out = render_inline(header)
        body.each do |row|
          out << "\n"
          comments = row.take_while { |t| INLINE_COMMENT.include?(t.type) }
          comments.each { |comment| out << body_indent << comment.value.rstrip << "\n" }
          rest = row.drop(comments.length)
          next if rest.empty?

          pad = arrows ? [arrows - leading_width(rest), 0].max : nil
          out << body_indent << render_inline_with_pad(rest, pad)
        end
        out << "\n" << closer_indent << "}"
        out
      end

      def render_inline_with_pad(tokens, pad)
        out = +""
        previous = nil
        padded = false
        tokens.each do |token|
          if !padded && arrow_token?(token) && pad&.positive?
            out << (" " * pad)
            padded = true
          end
          out << spacing(previous, token) << token.value
          previous = token
        end
        out
      end

      def spacing(previous, token)
        return "" if previous.nil?
        return "" if previous.type == :punct && NO_SPACE_AFTER.include?(previous.value)
        return "" if token.type == :punct && NO_SPACE_BEFORE.include?(token.value)
        # A bracket hard against an identifier is the capture suffix
        # (`items[].n`), not an optional group (`= [space]`).
        return "" if token.type == :punct && token.value == "[" && previous.type == :ident
        # The repetition operator tightens only behind its count
        # (`1*(x)`); after an atom it opens the next sequence element.
        return "" if token.type == :punct && token.value == "*" && previous.type == :num

        " "
      end
    end
  end
end
