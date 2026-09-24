# frozen_string_literal: true

require "strscan"
require "parsanol/atoms/can_flatten"

module Parsanol
  # Bytecode VM for the pure-Ruby parse path.
  #
  # Compiles an atom tree once into a flat integer program and executes it
  # with a single dispatch loop. Terminals record packed span Integers
  # ((pos << 20) | len) instead of allocating Slices; composite values
  # mirror the interpreter's tagged arrays exactly. A bottom-up
  # materialization pass turns spans into Slices and Named markers into
  # their eagerly-flattened hashes, so output is byte-identical to the
  # tree interpreter (mode: :ruby).
  #
  # Design notes: TODO.perf/6-ruby-vm.md
  module VM
    HALT = 0
    STR = 1
    RE = 2
    ANY = 3
    SEQ_BEGIN = 4
    SEQ_END = 5
    CHOICE = 6
    POPBT = 7
    JMP = 8
    NAME_END = 9
    CALL = 10
    RET = 11
    LOOK_POS = 12
    LOOK_POS_END = 13
    LOOK_NEG = 14
    LOOK_NEG_END = 15
    DROP = 16
    FAIL = 17
    REP_INIT = 18
    REP_TEST = 19
    REP_STEP = 20
    REP_EXIT = 21
    MAYBE_RE = 22
    MAYBE_STR = 23
    RUN_RE = 24
    RUN_STR = 25
    SEQ_SIMPLE = 26
    BYTE_DISPATCH = 27

    K_ALT = 0
    K_REP = 1
    K_LOOK_FAIL = 2
    K_NEG = 3

    SEQ_MARK = Object.new.freeze

    # Deferred Named wrapper; materialization produces
    # { name => flatten(inner, named: true) } like Named#apply.
    NamedValue = Struct.new(:name, :value)

    SINGLE_CLASS_RE = /\A(?:\^)?(?:\[[^\[\]]*\]|\\[dDwWsShH]|\\x[0-9a-fA-F]{2}|\\[0-7]{1,3}|[^\[\\\]|()?*+{}\^])\z/

    CHAR_WIDTH = Array.new(256, 0)
    (0...128).each { |b| CHAR_WIDTH[b] = 1 }
    (0xC2..0xDF).each { |b| CHAR_WIDTH[b] = 2 }
    (0xE0..0xEF).each { |b| CHAR_WIDTH[b] = 3 }
    (0xF0..0xF4).each { |b| CHAR_WIDTH[b] = 4 }

    MAX_PACK_LEN = (1 << 20) - 1
    FRAME_STRIDE = 4 # count, end_pos, rbase, min
    BT_STRIDE = 6    # pc, pos, rlen, cbase, clen, kind
    # Returned (as the sole value) when the VM cannot complete a parse
    # for internal reasons — callers should fall back to the interpreter
    # and may skip the VM for this grammar afterwards. A clean
    # [false, nil] means the input genuinely does not parse.
    BAIL = Object.new.freeze
    # Step budget exhausted on the naive pass — internal to #run, which
    # retries once with packrat memoization before giving up.
    BUDGET = Object.new.freeze
    # Memo marker for a subroutine currently being evaluated at a given
    # position. Re-entry (left recursion) fails that path instead of
    # looping forever.
    PENDING = Object.new.freeze

    STEP_BUDGET_FACTOR = 200
    STEP_BUDGET_FIXED = 10_000
    MEMO_BUDGET_FACTOR = 4_096
    MEMO_BUDGET_CELLS_FACTOR = 16

    class << self
      @programs = {}

      # Cached compile keyed by root-atom object identity. Atoms are
      # effectively immutable once constructed; false caches grammars the
      # VM cannot handle so we do not re-walk them on every parse.
      #
      # A grammar whose VM run failed once (unsupported backtracking shape
      # or step budget) is marked :fallback so later parses skip the VM
      # attempt entirely — the interpreter result is identical.
      def program_for(atom)
        root = atom.is_a?(Parsanol::Parser) ? atom.root : atom
        key = root.object_id
        cache = (@programs ||= {})
        cached = cache[key]
        return nil if cached == :fallback
        return cached if key?(cache, key)

        # A grammar the compiler cannot compile — e.g. one containing a
        # lazily resolved Entity that a select-first literal index would
        # never select — falls back to the interpreter, the source of
        # truth. The interpreter resolves such entities lazily, so an
        # unselected branch simply never raises.
        begin
          cache[key] = compile(atom)
        rescue NotImplementedError
          cache[key] = :fallback
          nil
        end
      end

      # Marks a grammar as VM-incompatible after a runtime failure.
      def disable_for!(atom)
        root = atom.is_a?(Parsanol::Parser) ? atom.root : atom
        (@programs ||= {})[root.object_id] = :fallback # rubocop:disable Lint/HashCompareByIdentity -- object_id keys avoid holding strong references to grammar atoms
      end

      def key?(cache, key) # rubocop:disable Naming/PredicateMethod -- mirrors Hash#key?
        cache.key?(key)
      end

      def clear_program_cache
        @programs&.clear
        @heavy&.clear
      end

      # Compiles the grammar rooted at +atom+. Returns the flat program
      # Array, or nil when the grammar uses unsupported atoms.
      def compile(atom)
        program = compile_with_inline(atom, true)
        # Inlining duplicates every non-recursive rule body at each
        # reference site; grammars with many cross-referencing rules
        # explode past the program cap even though the atom tree is
        # modest. Recompiling with inlining off (each rule a CALL/RET
        # subroutine) keeps the program O(atoms) at a small per-rule
        # dispatch cost — far better than refusing the grammar outright.
        return program unless program == :oversize

        compile_with_inline(atom, false)
      end

      def compile_with_inline(atom, inline)
        root = atom.is_a?(Parsanol::Parser) ? atom.root : atom
        compiler = Compiler.new(inline: inline)
        return nil unless compiler.compile_atom(root, true)

        # HALT terminates the MAIN program; subroutines follow it so the
        # root CALL's return address can never collide with a subroutine.
        compiler.ops << [HALT, nil, nil, nil]
        return nil unless compiler.append_subroutines

        # Terminal failures jump to pc = FAIL without testing the pc
        # register on the hot path; the dispatch case instead lands on
        # this dedicated instruction (the last slot in the flat program),
        # whose opcode is FAIL itself.
        compiler.ops << [FAIL, nil, nil, nil]

        # Structure-seeded memoization: a grammar containing repeat/maybe
        # starts memoized on its very first parse (fresh parser instances
        # included — the seed is recomputed at every compile), so the
        # cold-start never pays the doomed unmemoized exploration.
        if compiler.backtracking_prone
          # rubocop:disable Lint/HashCompareByIdentity -- object_id keys match run_for's heavy flag; would otherwise pin every grammar alive
          (@heavy ||= {})[root.object_id] = true
          # rubocop:enable Lint/HashCompareByIdentity
        end

        compiler.to_program
      end

      # Executes a compiled program. Returns [true, value] on success;
      # [false, nil] on failure or budget exhaustion — callers fall back
      # to the interpreter, which reproduces exact diagnostics.
      #
      # Heavy-backtracking grammars get a second chance: the naive pass
      # runs without memoization (zero overhead on the happy path), and
      # only if it blows the step budget does a memoized pass run. The
      # memo converts repeated rule+position work into single entries, so
      # grammars that the interpreter needed (slow) memoization for now
      # run at VM speed.
      def run(program, input, consume_all)
        executor = Executor.new(program, input, consume_all)
        result = executor.execute
        if result.equal?(BUDGET)
          executor = Executor.new(program, input, consume_all, memoize: true)
          result = executor.execute
          result = BAIL if result.equal?(BUDGET)
        end
        result
      end

      # Grammar-aware entry used by Base#parse. Grammars that have shown
      # heavy-backtracking behavior (budget bust, or a success that
      # burned the step-density threshold) memoize from the first
      # instruction on subsequent parses, skipping the doomed naive
      # pass; a heavy success is retried memoized in the same call so
      # the VM keeps the grammar instead of surrendering it to the
      # interpreter.
      def run_for(atom, program, input, consume_all)
        root = atom.is_a?(Parsanol::Parser) ? atom.root : atom
        id = root.object_id
        heavy = (@heavy ||= {})
        if heavy[id]
          result = Executor.new(program, input, consume_all,
                                memoize: true).execute
          return BAIL if result.equal?(BUDGET)

          return result
        end

        result = Executor.new(program, input, consume_all).execute
        if result.equal?(BUDGET) ||
            (result.is_a?(Array) && result.first == :heavy)
          heavy[id] = true
          memo_result = Executor.new(program, input, consume_all,
                                     memoize: true).execute
          # A heavy naive success already answered; the memo pass only
          # proves the grammar stays VM-viable (BUDGET would bail to the
          # interpreter). When the naive pass never answered, the memo
          # pass's outcome is the result.
          return BAIL if memo_result.equal?(BUDGET)

          result = memo_result if result.equal?(BUDGET)
        end
        result
      end

      # Converts the VM value tree into the interpreter's value tree.
      def materialize(value, input)
        case value
        when Integer
          pos = value >> 20
          Slice.new(pos, input.byteslice(pos, value & MAX_PACK_LEN), input)
        when NamedValue
          { value.name => Mat.flatten(materialize(value.value, input), true) }
        when Array
          value.map { |v| materialize(v, input) }
        when Hash
          value.transform_values { |v| materialize(v, input) }
        else
          value
        end
      end
    end

    module Mat
      extend Parsanol::Atoms::CanFlatten
    end
    private_constant :Mat

    # Compiles atoms into a flat stride-4 program. Entity bodies compile
    # as subroutines, keyed by [body object_id, consume_all] so spine
    # sites (consume_all=true) and inner sites stay semantically distinct.
    class Compiler
      def initialize(inline: true)
        @ops = []
        @inline = inline
        @subs = {}      # [obj_id, flag] => pc or :pending
        @pending = {}   # [obj_id, flag] => [[call_idx, body], ...]
        @backtracking_prone = false
      end

      attr_reader :ops, :backtracking_prone

      def to_program
        return :oversize if @ops.size > MAX_PROGRAM

        @ops.flatten!(1)
      end

      # Conservative lead-byte table for a branch: table[b] true iff the
      # atom can start with byte b. nil = cannot prove a constraint (no
      # guard emitted). Conservative in the safe direction only: a guard
      # may allow a branch that then fails normally, never reject one
      # that could match.
      def pairwise_disjoint?(tables)
        seen = Array.new(256, false)
        tables.each do |t|
          i = 0
          while i < 256
            return false if t[i] && seen[i]

            seen[i] = true if t[i]
            i += 1
          end
        end
        true
      end

      def first_byte_table(atom, depth = 0)
        return nil if depth > 10

        case atom
        when Parsanol::Atoms::Str
          b = atom.str.getbyte(0)
          return nil unless b

          t = Array.new(256, false)
          t[b] = true
          t
        when Parsanol::Atoms::Re
          byte_table(atom.re)
        when Parsanol::Atoms::Sequence
          t = nil
          nullable_all = true
          atom.parslets.each do |child|
            ct = first_byte_table(child, depth + 1)
            return nil if ct.nil?

            if t
              i = 0
              while i < 256
                t[i] ||= ct[i]
                i += 1
              end
            else
              t = ct
            end
            unless nullable?(child, depth + 1)
              nullable_all = false
              break
            end
          end
          nullable_all ? nil : t
        when Parsanol::Atoms::Alternative
          t = nil
          atom.alternatives.each do |branch|
            bt = first_byte_table(branch, depth + 1)
            return nil if bt.nil?

            if t
              i = 0
              while i < 256
                t[i] ||= bt[i]
                i += 1
              end
            else
              t = bt
            end
          end
          t
        when Parsanol::Atoms::Named
          first_byte_table(atom.parslet, depth + 1)
        when Parsanol::Atoms::Ignored
          first_byte_table(atom.wrapped_atom, depth + 1)
        when Parsanol::Atoms::Lookahead
          # Positive: body's lead bytes. Negative: body's lead bytes are
          # a safe superset (a failing !-check just fails the branch
          # normally).
          first_byte_table(atom.bound_parslet, depth + 1)
        when Parsanol::Atoms::Repetition
          # min 0 can match empty — no byte constraint exists.
          return nil if atom.min.zero?

          first_byte_table(atom.parslet, depth + 1)
        when Parsanol::Atoms::Entity
          inner = begin
            atom.parslet
          rescue StandardError
            nil
          end
          return nil if inner.nil?

          first_byte_table(inner, depth + 1)
        when Parsanol::Atoms::Scope
          inner = begin
            atom.block.call
          rescue StandardError
            nil
          end
          return nil if inner.nil?

          first_byte_table(inner, depth + 1)
        end
      end

      # Wrapper branches (Entity/Scope) share body shapes by design.
      # rubocop:disable-next Lint/DuplicateBranch
      def nullable?(atom, depth = 0)
        return false if depth > 10

        case atom
        when Parsanol::Atoms::Str then atom.str.bytesize.zero?
        when Parsanol::Atoms::Re then false
        when Parsanol::Atoms::Sequence
          atom.parslets.all? { |c| nullable?(c, depth + 1) }
        when Parsanol::Atoms::Alternative
          atom.alternatives.any? { |c| nullable?(c, depth + 1) }
        when Parsanol::Atoms::Repetition then atom.min.zero?
        when Parsanol::Atoms::Named then nullable?(atom.parslet, depth + 1)
        when Parsanol::Atoms::Ignored then nullable?(atom.wrapped_atom, depth + 1)
        when Parsanol::Atoms::Lookahead then true
        when Parsanol::Atoms::Entity, Parsanol::Atoms::Scope
          nullable_wrapped?( # rubocop:disable Lint/DuplicateBranch -- Entity/Scope differ only in accessor
            -> { atom.is_a?(Parsanol::Atoms::Entity) ? atom.parslet : atom.block.call }, depth
          )
        else false
        end
      end

      # Entity and Scope wrap lazily-resolvable inners through different
      # accessors; the nullability logic is shared.
      def nullable_wrapped?(resolver, depth)
        inner = begin
          resolver.call
        rescue StandardError
          nil
        end
        !inner.nil? && nullable?(inner, depth + 1)
      end

      def compile_atom(atom, consume_all)
        case atom
        when Parsanol::Atoms::Str
          bytes = atom.str.unpack("C*")
          emit(STR, bytes, bytes.size, atom.str.bytesize)
          self
        when Parsanol::Atoms::Re
          emit(RE, atom.re, byte_table(atom.re), nil)
          self
        when Parsanol::Atoms::Sequence
          parslets = atom.parslets
          n = parslets.size
          return nil if n.zero?

          simple = simple_children(parslets, consume_all)
          if simple
            emit(SEQ_SIMPLE, simple, nil, nil)
            return self
          end

          emit(SEQ_BEGIN)
          last = n - 1
          idx = 0
          while idx < n
            return nil unless compile_atom(parslets[idx], consume_all && idx == last)

            idx += 1
          end
          emit(SEQ_END)
          self
        when Parsanol::Atoms::Alternative
          alts = atom.alternatives
          count = alts.size
          return nil if count.zero?

          # First-set discrimination: when every branch has a provable
          # lead-byte table and the tables are pairwise disjoint, at most
          # one branch can match any input — dispatch directly to the
          # viable branch (or fail) in one lookup. Shared lead bytes
          # fall back to the plain CHOICE machinery untouched.
          tables = alts.map { |a| first_byte_table(a) }
          if tables.all? && pairwise_disjoint?(tables)
            dispatch_idx = emit(BYTE_DISPATCH, nil, nil, nil)
            starts = []
            idx = 0
            while idx < count
              starts << flat(@ops.size)
              return nil unless compile_atom(alts[idx], consume_all)

              idx += 1
            end
            table = Array.new(256, -1)
            tables.each_with_index do |t, bi|
              pc_i = starts[bi]
              bi2 = bi
              j = 0
              while j < 256
                table[j] = pc_i if t[j]
                j += 1
              end
              bi2
            end
            patch(dispatch_idx, 1, table)
            return self
          end

          jumps = []
          idx = 0
          while idx < count
            last_alt = idx == count - 1
            choice = (emit(CHOICE, nil, nil, nil) unless last_alt)
            return nil unless compile_atom(alts[idx], consume_all)

            unless last_alt
              # The branch matched: drop this CHOICE's backtrack entry
              # (ordered choice commits) before skipping the rest.
              emit(POPBT)
              jumps << emit(JMP, nil, nil, nil)
            end
            patch(choice, 1, flat(@ops.size)) if choice
            idx += 1
          end
          jumps.each { |j| patch(j, 1, flat(@ops.size)) }
          self
        when Parsanol::Atoms::Repetition
          compile_repetition(atom, consume_all)
        when Parsanol::Atoms::Named
          return nil unless compile_atom(atom.parslet, consume_all)

          emit(NAME_END, atom.name, nil, nil)
          self
        when Parsanol::Atoms::Entity
          compile_entity(atom, consume_all)
        when Parsanol::Atoms::Lookahead
          compile_lookahead(atom, consume_all)
        when Parsanol::Atoms::Ignored
          inner = atom.wrapped_atom
          return nil if inner.nil?
          return nil unless compile_atom(inner, consume_all)

          emit(DROP)
          self
        when Parsanol::Atoms::Scope
          # Scope only affects capture state; the result tree is the
          # inner atom's tree unchanged. The block is pure DSL evaluated
          # once at compile time. Any Capture/Dynamic inside still fails
          # compilation on its own, so passthrough cannot diverge.
          inner = begin
            atom.block.call
          rescue StandardError
            nil
          end
          return nil if inner.nil?
          return nil unless compile_atom(inner, consume_all)

          self
          # Dynamic, Capture, Cut, Custom, Infix, unknown
        end
      end

      def append_subroutines # rubocop:disable Naming/PredicateMethod -- mutating; returns compile success, not a predicate
        until @pending.empty?
          key, list = @pending.shift
          body = list.first[1]
          flag = key[1]
          sub = @ops.size
          # Register before compiling so recursive references resolve.
          @subs[key] = sub
          return false unless compile_atom(body, flag)

          emit(RET)
          list.each { |entry| patch(entry[0], 1, flat(sub)) } # rubocop:disable Style/HashEachMethods -- Array of [call_idx, body] pairs, not a Hash
        end
        true
      end

      MAX_PROGRAM = 40_000 # instructions; larger grammars fall back

      private

      def emit(op, a = nil, b = nil, c = nil) # rubocop:disable Naming/MethodParameterName -- opcode operand slots
        @ops << [op, a, b, c]
        @ops.size - 1
      end

      def patch(idx, slot, value)
        @ops[idx][slot] = value
      end

      # Compiler works in instruction indexes; the executor's pc indexes
      # the flattened array (4 slots per instruction).
      def flat(instr_index)
        instr_index * 4
      end

      # Returns a flat [op, a, b, c, ...] descriptor array when every
      # child compiles to a single-value fused op, else nil.
      def simple_children(parslets, consume_all)
        kids = []
        last = parslets.size - 1
        parslets.each_with_index do |child, idx|
          spine = consume_all && idx == last
          op = simple_child(child, spine)
          return nil if op.nil?

          kids.concat(op)
        end
        kids
      end

      def simple_child(atom, spine)
        case atom
        when Parsanol::Atoms::Str
          bytes = atom.str.unpack("C*")
          [STR, bytes, bytes.size, atom.str.bytesize]
        when Parsanol::Atoms::Re
          [RE, atom.re, byte_table(atom.re), nil]
        when Parsanol::Atoms::Repetition
          min = atom.min
          max = atom.max
          return nil if max&.zero? || spine

          body = atom.parslet
          if min.zero? && max == 1
            case body
            when Parsanol::Atoms::Re
              [MAYBE_RE, body.re, byte_table(body.re), nil]
            when Parsanol::Atoms::Str
              bytes = body.str.unpack("C*")
              [MAYBE_STR, bytes, bytes.size, body.str.bytesize]
            end
          elsif min >= 1 && max.nil?
            case body
            when Parsanol::Atoms::Re
              [RUN_RE, body.re, byte_table(body.re), min]
            when Parsanol::Atoms::Str
              bytes = body.str.unpack("C*")
              [RUN_STR, bytes, bytes.size, min]
            end
          end
        end
      end

      # Repetition compilation with terminal fusions:
      # * maybe(0,1) of a single terminal -> one MAYBE_* op (no backtrack
      #   entry, no unwind cycle on the empty path)
      # * unbounded-plus of a single terminal (non-spine sites) -> greedy
      #   RUN_* op
      def compile_repetition(atom, consume_all)
        # Any repetition (repeat, maybe, repeat(0)) can re-explore the
        # same rule+position pairs when a later sibling fails; grammars
        # containing one memoize from the first parse instead of waiting
        # for the naive pass to prove the need.
        @backtracking_prone = true
        min = atom.min
        max = atom.max
        return nil if max&.zero?

        body = atom.parslet
        if min.zero? && max == 1 && !consume_all
          case body
          when Parsanol::Atoms::Re
            emit(MAYBE_RE, body.re, byte_table(body.re), nil)
            return self
          when Parsanol::Atoms::Str
            bytes = body.str.unpack("C*")
            emit(MAYBE_STR, bytes, bytes.size, body.str.bytesize)
            return self
          end
        end
        if min >= 1 && max.nil? && !consume_all
          case body
          when Parsanol::Atoms::Re
            emit(RUN_RE, body.re, byte_table(body.re), min)
            return self
          when Parsanol::Atoms::Str
            bytes = body.str.unpack("C*")
            emit(RUN_STR, bytes, bytes.size, min)
            return self
          end
        end

        emit(REP_INIT, min, nil, nil)
        test = emit(REP_TEST, nil, max, nil)
        return nil unless compile_atom(body, false)

        step = emit(REP_STEP, nil, nil, max)
        exit_ = emit(REP_EXIT, atom.result_tag, consume_all ? 1 : 0, nil)
        patch(test, 1, flat(exit_))
        patch(step, 1, flat(test))
        patch(step, 2, flat(exit_))
        self
      end

      def compile_entity(atom, consume_all)
        body = begin
          atom.parslet
        rescue StandardError
          nil
        end
        return nil if body.nil?

        # Leaf entities are transparent: a rule whose body is a single
        # terminal compiles inline, skipping the CALL/RET round trip.
        case body
        when Parsanol::Atoms::Str
          bytes = body.str.unpack("C*")
          emit(STR, bytes, bytes.size, body.str.bytesize)
          return self
        when Parsanol::Atoms::Re
          emit(RE, body.re, byte_table(body.re), nil)
          return self
        end

        # Non-recursive rules inline: the body's ops replace the CALL/RET
        # round trip entirely. A body currently being compiled (directly
        # or indirectly) is recursive and must stay a subroutine.
        # rubocop:disable Lint/HashCompareByIdentity -- object_id keys; would otherwise pin every atom alive
        if @inline && !(@compiling ||= {})[body.object_id]
          @compiling[body.object_id] = true
          # rubocop:enable Lint/HashCompareByIdentity
          result = compile_atom(body, consume_all)
          @compiling.delete(body.object_id)
          return result if result

          return nil
        end

        key = [body.object_id, consume_all]
        sub = @subs[key]
        if sub.is_a?(Integer)
          emit(CALL, flat(sub), nil, nil)
        else
          call_idx = emit(CALL, nil, nil, nil)
          (@pending[key] ||= []) << [call_idx, body]
          @subs[key] = :pending if sub.nil?
        end
        self
      end

      def compile_lookahead(atom, consume_all)
        positive = atom.positive
        bound = atom.bound_parslet
        return nil if bound.nil?

        entry = emit(positive ? LOOK_POS : LOOK_NEG, nil, nil, nil)
        return nil unless compile_atom(bound, consume_all)

        emit(positive ? LOOK_POS_END : LOOK_NEG_END)
        patch(entry, 1, flat(@ops.size)) # continuation for K_NEG entries
        self
      end

      # 256-entry table: "regex matches a prefix consisting of exactly this
      # ASCII byte" — only when the regex is provably a single-char class.
      def byte_table(re) # rubocop:disable Naming/MethodParameterName
        return nil unless SINGLE_CLASS_RE.match?(re.source)
        return nil if re.match?("") # can match empty -> not byte-local

        table = Array.new(256, false)
        (1..127).each do |b|
          table[b] = true if re.match?(b.chr)
        end
        table
      end
    end

    # One execution of a compiled program over one input string.
    # When a parse succeeds but consumed a large fraction of the step
    # budget, the grammar backtracks heavily and the tree interpreter
    # (with its adaptive memoization) is the better engine; #run reports
    # this via :heavy so Base#parse can skip the VM for the grammar.
    class Executor
      def initialize(program, input, consume_all, memoize: false)
        @ops = program
        @input = input
        @consume_all = consume_all
        @memoize = memoize
      end

      def execute # rubocop:disable Metrics/MethodLength, Metrics/BlockLength, Metrics/BlockNesting -- single dispatch loop; hot path
        ops = @ops
        input = @input
        # Dedicated FAIL landing instruction appended after HALT and the
        # subroutines: `pc = fail_pc` dispatches straight into when-FAIL
        # on the next cycle, no sentinel comparison per step.
        fail_pc = ops.size - 4
        bytes = input.unpack("C*")
        # Regexp#match?(str, pos) searches FORWARD from pos (unanchored);
        # StringScanner#match? is position-anchored, matching the
        # interpreter's Source#matches? semantics exactly.
        scanner = StringScanner.new(input)
        n = bytes.size
        # The memoized pass is polynomial (bounded by distinct rule ×
        # position pairs); give it room proportional to grammar + input so
        # packrat coverage of failing inputs isn't cut short.
        budget = if @memoize
                   (MEMO_BUDGET_CELLS_FACTOR * ops.size) +
                     (MEMO_BUDGET_FACTOR * n) + STEP_BUDGET_FIXED
                 else
                   (STEP_BUDGET_FACTOR * n) + STEP_BUDGET_FIXED
                 end
        steps = 0

        pc = 0
        pos = 0
        rstack = []
        bt = []
        frames = []
        calls = []

        memo = @memoize ? {} : nil
        memo_stack = []
        trace = ENV["VM_TRACE"] ? [] : nil

        # rubocop:disable-next Metrics/BlockLength -- the dispatch loop IS execute
        loop do
          steps += 1
          if steps > budget
            if trace
              warn "BUDGET at steps=#{steps} pc=#{pc} pos=#{pos} rstack=#{rstack.size} bt=#{bt.size} calls=#{calls.size}"
              warn "trace tail: #{trace.last(30).inspect}"
            end
            return BUDGET
          end
          trace << [pc, pos] if trace

          case ops[pc]
          when FAIL
            pc, pos = unwind(bt, rstack, frames, calls, memo, memo_stack)
            return [false, nil] if pc == :fail
            return BAIL if pc == :bail

          when STR
            lit = ops[pc + 1]
            ln = ops[pc + 2]
            i = 0
            matched = true
            while i < ln
              if bytes[pos + i] != lit[i]
                matched = false
                break
              end
              i += 1
            end
            if matched
              rstack << ((pos << 20) | ln)
              pos += ops[pc + 3]
              pc += 4
            else
              pc = fail_pc
            end
          when RE
            b = bytes[pos]
            matched =
              if (table = ops[pc + 2]) && b && b < 128
                table[b]
              elsif pos < n
                (scanner.pos = pos) && scanner.match?(ops[pc + 1])
              else
                false
              end
            if matched
              w = CHAR_WIDTH[b]
              w = char_width_slow(input, pos) if w.zero?
              rstack << ((pos << 20) | w)
              pos += w
              pc += 4
            else
              pc = fail_pc
            end
          when ANY
            if pos < n
              w = CHAR_WIDTH[bytes[pos]]
              w = char_width_slow(input, pos) if w.zero?
              rstack << ((pos << 20) | w)
              pos += w
              pc += 4
            else
              pc = fail_pc
            end
          when SEQ_BEGIN
            rstack << SEQ_MARK
            pc += 4
          when SEQ_END
            # Pop pushes in reverse; append and single reverse (O(n), no
            # per-element unshift).
            values = []
            guard = rstack.size
            ok_seq = false
            while guard.positive?
              v = rstack.pop
              guard -= 1
              if v == SEQ_MARK
                ok_seq = true
                break
              end
              values << v
            end
            return [false, nil] unless ok_seq

            values << :sequence
            values.reverse!
            rstack << values
            pc += 4
          when CHOICE
            bt << ops[pc + 1] << pos << rstack.size << frames.size << calls.size << K_ALT
            pc += 4
          when POPBT
            bt.pop(BT_STRIDE)
            pc += 4
          when JMP
            pc = ops[pc + 1]
          when NAME_END
            rstack << VM::NamedValue.new(ops[pc + 1], rstack.pop)
            pc += 4
          when CALL
            sub = ops[pc + 1]
            if memo
              table = (memo[sub] ||= {})
              hit = table[pos]
              if hit
                if hit.equal?(PENDING) || hit.equal?(:fail)
                  # :fail — the body already failed at this position;
                  # replay the failure without re-running it.
                  # PENDING — re-entry at the same rule+position (left
                  # recursion); the interpreter loops forever here, so
                  # failing this path keeps the VM bounded.
                  pc = fail_pc
                  next
                end
                # Memo hit: replay the subroutine's stack effect without
                # executing it. Values are immutable (packed spans,
                # NamedValue, frozen-shape Arrays), so sharing is safe.
                rstack.concat(hit[1])
                pos = hit[0]
                pc += 4
                next
              end

              table[pos] = PENDING
              # Lockstep with calls: unwind rolls both back by clen.
              memo_stack << sub << pos << rstack.size
            end
            calls << (pc + 4)
            pc = sub
          when RET
            pc = calls.pop
            return BAIL if pc.nil?

            if memo
              mlen = memo_stack.pop
              mpos = memo_stack.pop
              msub = memo_stack.pop
              memo[msub][mpos] = [pos, rstack[mlen..]]
            end
          when LOOK_POS
            bt << ops[pc + 1] << pos << rstack.size << frames.size << calls.size << K_LOOK_FAIL
            pc += 4
          when LOOK_POS_END
            # Body matched: restore entry's saved pos, drop entry and the
            # body's value, push nil like Lookahead#try.
            pos = bt[-BT_STRIDE + 1]
            bt.pop(BT_STRIDE)
            rstack.pop
            rstack << nil
            pc += 4
          when LOOK_NEG
            bt << ops[pc + 1] << pos << rstack.size << frames.size << calls.size << K_NEG
            pc += 4
          when LOOK_NEG_END
            # Body matched: negative lookahead fails. Drop entry + body
            # values, then propagate failure outward.
            rlen = bt[-BT_STRIDE + 2]
            rstack.slice!(rlen..) if rstack.size > rlen
            bt.pop(BT_STRIDE)
            pc = fail_pc
          when DROP
            rstack.pop
            rstack << nil
            pc += 4
          when REP_INIT
            frames << 0 << pos << rstack.size << ops[pc + 1] # count,end,rbase,min
            pc += 4
          when REP_TEST
            cbase = frames.size - FRAME_STRIDE
            count = frames[cbase]
            return BAIL if count.nil?

            max = ops[pc + 2]
            if max && count >= max
              pc = ops[pc + 1] # exit
            else
              bt << ops[pc + 1] << frames[cbase + 1] << rstack.size << cbase << calls.size << K_REP
              pc += 4 # body
            end
          when REP_STEP
            bt.pop(BT_STRIDE)
            cbase = frames.size - FRAME_STRIDE
            count = frames[cbase]
            return BAIL if count.nil?

            count += 1
            frames[cbase] = count
            frames[cbase + 1] = pos
            max = ops[pc + 3]
            pc = if max && count >= max
                   ops[pc + 2] # exit
                 else
                   ops[pc + 1] # test
                 end
          when REP_EXIT
            cbase = frames.size - FRAME_STRIDE
            return BAIL if frames[cbase].nil?

            if ops[pc + 2] == 1 && pos != n
              frames.slice!(cbase..)
              pc = fail_pc
            else
              rbase = frames[cbase + 2]
              values = rstack.pop(rstack.size - rbase)
              values.unshift(ops[pc + 1])
              rstack << values
              frames.slice!(cbase..)
              pc += 4
            end
          when BYTE_DISPATCH
            table = ops[pc + 1]
            b = pos < n ? bytes[pos] : -1
            target = b == -1 ? -1 : table[b]
            pc = target >= 0 ? target : fail_pc
          when SEQ_SIMPLE
            kids = ops[pc + 1]
            kn = kids.size
            values = [:sequence]
            ki = 0
            failed = false
            while ki < kn
              kop = kids[ki]
              ka = kids[ki + 1]
              kb = kids[ki + 2]
              kc = kids[ki + 3]
              case kop
              when RE
                b = bytes[pos]
                m = if kb && b && b < 128
                      kb[b]
                    elsif pos < n
                      (scanner.pos = pos) && scanner.match?(ka)
                    else
                      false
                    end
                if m
                  w = CHAR_WIDTH[b]
                  w = char_width_slow(input, pos) if w.zero?
                  values << ((pos << 20) | w)
                  pos += w
                else
                  failed = true
                end
              when STR
                i = 0
                ln = kb
                m = true
                while i < ln
                  if bytes[pos + i] != ka[i] # rubocop:disable Metrics/BlockNesting -- fused byte-compare loop
                    m = false
                    break
                  end
                  i += 1
                end
                if m
                  values << ((pos << 20) | ln)
                  pos += kc
                else
                  failed = true
                end
              when MAYBE_RE
                b = bytes[pos]
                m = if kb && b && b < 128
                      kb[b]
                    elsif pos < n
                      (scanner.pos = pos) && scanner.match?(ka)
                    else
                      false
                    end
                if m
                  w = CHAR_WIDTH[b]
                  w = char_width_slow(input, pos) if w.zero?
                  values << [:maybe, (pos << 20) | w]
                  pos += w
                else
                  values << [:maybe]
                end
              when MAYBE_STR
                i = 0
                ln = kb
                m = true
                while i < ln
                  if bytes[pos + i] != ka[i] # rubocop:disable Metrics/BlockNesting -- fused byte-compare loop
                    m = false
                    break
                  end
                  i += 1
                end
                if m
                  values << [:maybe, (pos << 20) | ln]
                  pos += kc
                else
                  values << [:maybe]
                end
              when RUN_RE
                elem_start = pos
                count = 0
                loop do
                  b = bytes[pos]
                  m = if kb && b && b < 128
                        kb[b]
                      elsif pos < n
                        (scanner.pos = pos) && scanner.match?(ka)
                      else
                        false
                      end
                  break unless m

                  count += 1
                  w = CHAR_WIDTH[b]
                  w = char_width_slow(input, pos) if w.zero?
                  values << ((pos << 20) | w)
                  pos += w
                end
                if count < kc
                  pos = elem_start
                  failed = true
                end
              when RUN_STR
                elem_start = pos
                count = 0
                loop do
                  i = 0
                  ln = kb
                  m = true
                  while i < ln
                    if bytes[pos + i] != ka[i] # rubocop:disable Metrics/BlockNesting -- fused byte-compare loop
                      m = false
                      break
                    end
                    i += 1
                  end
                  break unless m

                  count += 1
                  values << ((pos << 20) | ln)
                  pos += ln
                end
                if count < kc
                  pos = elem_start
                  failed = true
                end
              end
              break if failed

              ki += 4
            end
            if failed
              pc = fail_pc
            else
              rstack << values
              pc += 4
            end
          when MAYBE_RE
            b = bytes[pos]
            matched =
              if (table = ops[pc + 2]) && b && b < 128
                table[b]
              elsif pos < n
                (scanner.pos = pos) && scanner.match?(ops[pc + 1])
              else
                false
              end
            if matched
              w = CHAR_WIDTH[b]
              w = char_width_slow(input, pos) if w.zero?
              rstack << [:maybe, (pos << 20) | w]
              pos += w
            else
              rstack << [:maybe]
            end
            pc += 4
          when MAYBE_STR
            lit = ops[pc + 1]
            ln = ops[pc + 2]
            i = 0
            matched = true
            while i < ln
              if bytes[pos + i] != lit[i]
                matched = false
                break
              end
              i += 1
            end
            if matched
              rstack << [:maybe, (pos << 20) | ln]
              pos += ops[pc + 3]
            else
              rstack << [:maybe]
            end
            pc += 4
          when RUN_RE
            re = ops[pc + 1]
            table = ops[pc + 2]
            min = ops[pc + 3]
            values = [:repetition]
            loop do
              b = bytes[pos]
              m = if table && b && b < 128
                    table[b]
                  elsif pos < n
                    (scanner.pos = pos) && scanner.match?(re)
                  else
                    false
                  end
              break unless m

              w = CHAR_WIDTH[b]
              w = char_width_slow(input, pos) if w.zero?
              values << ((pos << 20) | w)
              pos += w
            end
            if min && values.size - 1 < min
              pc = fail_pc
            else
              rstack << values
              pc += 4
            end
          when RUN_STR
            lit = ops[pc + 1]
            ln = ops[pc + 2]
            min = ops[pc + 3]
            values = [:repetition]
            loop do
              i = 0
              matched = true
              while i < ln
                if bytes[pos + i] != lit[i]
                  matched = false
                  break
                end
                i += 1
              end
              break unless matched

              values << ((pos << 20) | ln)
              pos += ln
            end
            if min && values.size - 1 < min
              pc = fail_pc
            else
              rstack << values
              pc += 4
            end
          when HALT
            if @consume_all && pos != n
              pc = fail_pc
              next
            end
            value = VM.materialize(rstack[0], input)
            # More than ~100 steps per input byte means heavy
            # backtracking; the memoizing interpreter wins there.
            if @memoize
              return [true, value]
            end

            return steps > (n << 9) + 1000 ? [:heavy, value] : [true, value]
          else
            return BAIL
          end
        end
      end

      private

      # Unwind one backtrack entry. Returns [pc, pos] or :fail. Repetition
      # entries with count >= min complete their tagged array and jump to
      # the exit continuation with the last iteration end position.
      def unwind(bt, rstack, frames, calls, memo, memo_stack) # rubocop:disable Naming/MethodParameterName -- stack register names
        return :fail if bt.empty?

        # Everything above this entry belongs to constructs being
        # abandoned by the jump (inner alternatives, repetitions, or
        # subroutine state); discard it along with the entry itself.
        blen = bt.size - BT_STRIDE
        if ENV["VM_TRACE"]
          warn "  UNWIND bt=#{bt.each_slice(6).map { |e| "[#{e[0]},#{e[1]},#{e[2]},#{e[3]},#{e[4]},#{e[5]}" }.join(' ')}"
        end
        kind = bt.pop
        clen = bt.pop
        cbase = bt.pop
        rlen = bt.pop
        epos = bt.pop
        epc = bt.pop
        bt.slice!(blen..) if bt.size > blen

        rstack.slice!(rlen..) if rstack.size > rlen
        calls.slice!(clen..) if calls.size > clen
        if memo
          # memo_stack carries three slots per live call, so the frames of
          # every call abandoned by this unwind are the tail above 3*clen.
          # Every abandoned frame is a call whose body failed — cache that
          # failure too (full packrat memoization), so later explorations
          # that reach the same rule+position fail immediately instead of
          # re-running the body. Grammar inputs that don't parse explore
          # every alternative; without failure entries those explorations
          # repeat exponentially and blow the step budget.
          floor = clen * 3
          while memo_stack.size > floor
            memo_stack.pop
            mpos = memo_stack.pop
            msub = memo_stack.pop
            table = memo[msub]
            table[mpos] = :fail if table
          end
        end

        case kind
        when K_ALT
          frames.slice!(cbase..) if frames.size > cbase
          [epc, epos]
        when K_REP
          count = frames[cbase]
          min = frames[cbase + 3]
          if count.nil? || min.nil?
            return :bail
          end

          if count >= min
            # Repetition succeeds with the completed prefix.
            rbase = frames[cbase + 2]
            end_pos = frames[cbase + 1]
            tag = @ops[epc + 1]
            check_full = @ops[epc + 2]
            if check_full == 1 && end_pos != @input.bytesize
              frames.slice!(cbase..)
              unwind(bt, rstack, frames, calls, memo, memo_stack)
            else
              values = rstack.pop(rstack.size - rbase)
              values.unshift(tag)
              rstack << values
              frames.slice!(cbase..)
              [epc + 4, end_pos]
            end
          else
            frames.slice!(cbase..)
            unwind(bt, rstack, frames, calls, memo, memo_stack)
          end
        when K_LOOK_FAIL
          frames.slice!(cbase..) if frames.size > cbase
          unwind(bt, rstack, frames, calls, memo, memo_stack)
        when K_NEG
          # Negative lookahead body failed -> lookahead succeeds.
          frames.slice!(cbase..) if frames.size > cbase
          rstack << nil
          [epc, epos]
        end
      end

      def char_width_slow(input, pos)
        w = CHAR_WIDTH[input.getbyte(pos)]
        w.zero? ? 1 : w
      end
    end
  end
end
