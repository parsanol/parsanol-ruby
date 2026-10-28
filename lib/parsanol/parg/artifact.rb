# frozen_string_literal: true

require "digest"
require "json"
require "yaml"

module Parsanol
  module PARG
    # A compiled artifact envelope: load, verify checksum, parse inputs.
    #
    # The envelope's grammar section is the portable JSON the native engines
    # consume; the embedded PARG source lets a Ruby runtime recompile the atom
    # tree locally without any other dependency.
    class Artifact
      attr_reader :envelope, :path, :tables_dir, :imports_dir

      def self.load(path, tables_dir: nil, imports_dir: nil)
        envelope = JSON.parse(PARG.read_utf8(path))
        new(envelope, path, tables_dir || File.dirname(path),
            imports_dir: imports_dir)
      end

      def self.from_json(text, tables_dir: nil, imports_dir: nil)
        new(JSON.parse(text), nil, tables_dir, imports_dir: imports_dir)
      end

      SUPPORTED_SHAPE = "parsanol-tree/v2"

      # The editions this runtime parses (ruby#357's consolidation):
      # v1 = the legacy shapes; v2 = named trees + explicit spans.
      SUPPORTED_EDITIONS = %w[v1 v2].freeze

      def initialize(envelope, path, tables_dir, imports_dir: nil)
        unless envelope["shape"] == SUPPORTED_SHAPE
          raise ArtifactError,
                "unsupported artifact shape #{envelope['shape'].inspect} " \
                "(this runtime implements #{SUPPORTED_SHAPE.inspect}; the " \
                "contract is docs/PARSANOL-SHAPE-v2.md in parsanol-rs — " \
                "a shape bump requires a new engine family, artifacts " \
                "declaring #{SUPPORTED_SHAPE.inspect} parse identically forever)"
        end
        bindings = envelope["bindings"]
        validate_bindings!(bindings) unless bindings.nil?
        @envelope = envelope
        # ruby#353: absent field = the pre-1.3.109 semantics. A level
        # above this runtime's is a hard error (the trees would carry
        # nodes this engine never emits); a lower one warns — parsing
        # works, but frozen tree comparisons will differ.
        # The declared edition must be one this runtime understands
        # (ruby#357's consolidation: one axis, `edition`, values v1/v2).
        edition = envelope["edition"] || "v1"
        unless SUPPORTED_EDITIONS.include?(edition)
          raise ArtifactError,
                "artifact declares edition #{edition.inspect}; this " \
                "runtime supports #{SUPPORTED_EDITIONS.map(&:inspect).join(', ')}"
        end
        @path = path
        @tables_dir = tables_dir
        # parsanol-ruby#208: `use`-importing grammars need the imported
        # sources when the pure-Ruby path recompiles the embedded source;
        # in-memory artifacts (path nil) pass the directory explicitly.
        @imports_dir = imports_dir
        verify_checksum!
        @compiler = nil
      end

      def version = envelope["version"]

      # Freshness (parsanol-ruby#209): what source revision and compiler
      # produced this artifact. `source_hash` is the SHA-256 of the .parg
      # text at compile time; nil on artifacts baked before the field
      # existed, so `fresh_against?` answers false rather than guessing.
      def source_hash = envelope["source_hash"]

      def compiler_version = envelope["compiler_version"]

      def fresh_against?(source_text)
        return false if source_hash.nil?

        source_hash == Digest::SHA256.hexdigest(source_text.to_s)
      end

      def entries = envelope["entries"].keys

      def entry(name)
        envelope["entries"].fetch(name) do
          raise ArtifactError, "unknown entry #{name.inspect}"
        end
      end

      # Parse via the native engine. Both engines run the atom tree that
      # #compiler rebuilds from the embedded source (under the envelope's
      # recorded capture mode); the native lane registers that tree with
      # the Rust side once and then runs by handle. The Ruby atom runtime
      # (mode: :ruby) remains available explicitly, and serves as the
      # fallback on platforms without the extension.
      #
      # Dynamic artifacts (runtime state, custom atoms — #129) route to
      # the Ruby engine: the envelope carries the PARG source precisely
      # so a Ruby runtime can rebuild the live atom tree; the closures
      # are not portable JSON.
      def parse(entry_name, input, mode: :native)
        case mode
        when :native
          if Native.available?
            # Fast lane (parsanol-ruby#162): Native.parse with the
            # per-instance root atom registers the grammar once
            # (GRAMMAR_CACHE / HANDLE_CACHE keyed on the stable root
            # atom) and every parse after the first runs the native
            # engine by handle — the same path a DSL parser's
            # mode: :native takes. Atoms::Base#parse must NOT carry
            # this lane: it ignores :mode, so it would silently run
            # the pure-Ruby VM and its interpreter fallback (the
            # 5-7x real-document gap in #162, and the root-position
            # diagnostics in #171 before the wire fallback).
            #
            # Dynamic-flagged artifacts parse natively too (rs#204):
            # the state atoms (StateSet/StateMatch/StateSwitch)
            # evaluate in the engine, riding the capture store's
            # rollback discipline. Reaching a CustomRef aborts the
            # native pass outright — Native.parse's error path then
            # re-runs the interpreter, so customs stay Ruby-tier with
            # identical trees.
            return Native.parse(root_atom(entry_name), input)
          end

          root_atom(entry_name).parse(input)
        when :reference
          # The plain recursive relation (TODO.sota/8 B1): same shaping
          # pipeline, no VM, no memo tables, no fused scans. Never falls
          # back to :ruby — a reference result produced by another
          # engine would defeat the differential. Deliberately slow.
          unless Native.reference_available?
            raise NotImplementedError, "reference mode requires the native " \
                                       "extension with parsanol >= 0.18.18"
          end

          Native.parse_reference(root_atom(entry_name), input)
        when :ruby
          # Deepest-failure reporting parity with the native engine: the
          # default Tree reporter keeps the most recent (root) failure,
          # which reports position 1:1 for grammars with entry wrappers.
          root_atom(entry_name).parse(input, reporter: ErrorReporter::Deepest.new)
        else
          raise ArgumentError, "unknown mode #{mode.inspect} (use :native, :reference or :ruby)"
        end
      end

      def apply_bindings(entry_name, shape)
        Bindings.apply(self, entry(entry_name), shape)
      end

      # Render the identifier string from a bound attribute map (F6).
      def render(_entry_name, bound, variant: "default")
        Render.apply(envelope["render"] || {}, variant, bound)
      end

      def render_string(entry_name, input, variant: "default")
        render(entry_name, parse_and_bind(entry_name, input), variant: variant)
      end

      # Evaluate a named derive spec against a bound map (F6).
      def derive(name, bound)
        Derive.apply(envelope["derive"] || {}, name, bound)
      end

      def derive_string(entry_name, input, name)
        derive(name, parse_and_bind(entry_name, input))
      end

      def parse_and_bind(entry_name, input, mode: :native)
        apply_bindings(entry_name, parse(entry_name, input, mode: mode))
      end

      # Re-run the grammar's in-file tests against this artifact. Returns
      # the failure descriptions; empty means every test passes.
      def run_tests(mode: :native)
        run_test_list(envelope.fetch("tests", []), mode: mode)
      end

      # Run an external test list (suite files yield Document::Test
      # structs; embedded tests are artifact-shaped hashes).
      # parse_with overrides how the input is turned into a shape
      # (the envelope self-test drives the baked grammar JSON natively
      # instead of root_atom's source rebuild); bindings and
      # expectations still flow through the standard surface.
      def run_test_list(tests, mode: :native, parse_with: nil)
        tests.filter_map do |test|
          hash = test.is_a?(Document::Test) ? test_to_hash(test) : test
          entry_name = hash["entry"] || entries.first
          begin
            shape = parse_with ? parse_with.call(hash["input"]) : parse(entry_name, hash["input"], mode: mode)
            case hash["kind"]
            when "reject"
              "test #{hash['input'].inspect}: expected the input to be rejected"
            when "shape"
              actual = Bindings.canonical(shape)
              expected = Bindings.canonical(hash["expect"])
              next if actual == expected

              "test #{hash['input'].inspect}: expected shape #{expected.inspect}, " \
                "got #{actual.inspect}"
            when "example"
              bound = apply_bindings(entry_name, shape)
              expect = hash["expect"].to_h { |key, value| [key.to_sym, value] }
              mismatched = expect.reject do |key, value|
                bound.key?(key) && Bindings.canonical(bound[key]) == Bindings.canonical(value)
              end
              next if mismatched.empty?

              "test #{hash['input'].inspect}: expected captures " \
                "#{mismatched.transform_values(&:inspect).inspect}, got #{bound.inspect}"
            when "capture"
              captures = Bindings.collect_captures(shape)
              mismatched = hash["expect"].reject do |key, value|
                values = captures[key.to_sym]
                values && !values.empty? &&
                  Bindings.canonical(values.first) == Bindings.canonical(value)
              end
              next if mismatched.empty?

              actuals = mismatched.keys.to_h do |key|
                [key, Bindings.canonical(captures[key.to_sym]&.first)]
              end
              "test #{hash['input'].inspect}: expected captures " \
                "#{mismatched.transform_values(&:inspect).inspect}, got #{actuals.inspect}"
            end
          rescue Parsanol::ParseFailed
            unless hash["kind"] == "reject"
              "test #{hash['input'].inspect}: expected the input to parse"
            end
          end
        end
      end

      # Best-effort recovery (TODO.sota/1, R1): on success returns
      # {"ok": true, "shape": tree}; on ParseFailed returns
      # {"ok": false, "error": {"offset", "message"}, "captures":
      # {name => [values...]}} — the captures observed before the
      # failure, from a journaling re-parse on the Ruby engine (tree
      # parity with the native engine is enforced by the differential
      # specs). The journal is best-effort: it may include captures
      # from branches that later failed.
      def parse_recovering(entry_name, input, mode: :native)
        shape = parse(entry_name, input, mode: mode)
        { "ok" => true, "shape" => shape }
      rescue Parsanol::ParseFailed => e
        # The journaling re-parse fails at the same point with the
        # interpreter's deepest cause — report ITS error, not the
        # initial parse's (the native FFI's coarse failure position
        # loses the deepest offset).
        captures, reparse_error = recovery_journal(entry_name, input, mode)
        # The spine boundary, not the failure offset, is where the
        # resync scan starts (rs#304 convergence): junk frequently lies
        # BEFORE the deepest failure (the failed iteration consumed its
        # own prefix), and the scan from the failure offset can never
        # match it. When no iteration matched, the boundary is 0 —
        # recovery still runs (rs#304 Gap B: a declared pattern is
        # usable from the start).
        stash = Parsanol::Recovery.take_partial
        partial = recovery_partial(entry_name, stash)
        boundary = stash&.first || 0
        resyncs = []
        if reparse_error
          root_name = entry(entry_name)["root"].to_sym
          items = partial&.values&.first
          created_partial = items.nil?
          items ||= []
          extended, resyncs = resync_extension(entry_name, input, boundary)
          items.concat(extended)
          # Recovered iterations with no prior partial form the partial
          # (the rs engine's stash exists from offset 0).
          partial = { root_name => items } if created_partial && !items.empty?
        end
        { "ok" => false,
          "error" => reparse_error || recovery_error(e),
          "captures" => captures,
          "partial" => partial,
          "resyncs" => resyncs }
      end

      # R2 (TODO.sota/1), inferred resync on the interpreter — the same
      # policy as the rs engine (parsanol-rs#280): from the failure
      # offset, scan forward for the next byte position where a
      # spine-body iteration matches with progress; the skipped span is
      # annotated and the recovered items join the partial tree.
      # Bounded (8 rounds, each must advance) so recovery stays linear.
      # Returns [items, resyncs]; [nil, []] when the grammar has no
      # resolvable spine.
      def resync_extension(entry_name, input, cursor)
        body_rule = spine_body_rule(entry_name)
        return [[], []] unless body_rule

        body_atom = compiler.atom_for(body_rule)
        # R2 declared form: the baked resync pattern owns the skip
        # spans (author-deterministic — no trial scanning). Falls back
        # to the inferred trial scan when the rule declares none.
        pattern_atom = compiler.resync_atom_for(body_rule) ||
          compiler.resync_atom_for(entry(entry_name)["root"])
        max = input.length
        resyncs = []
        items = []
        rounds = 0
        while rounds < 8
          attempt = try_iteration(body_atom, input, cursor)
          if attempt
            items << root_atom(entry_name).flatten(attempt[0])
            cursor = attempt[1]
            until cursor >= max
              attempt = try_iteration(body_atom, input, cursor)
              break unless attempt

              items << root_atom(entry_name).flatten(attempt[0])
              cursor = attempt[1]
            end
            break if cursor >= max
          end
          if pattern_atom
            # Declared: the pattern match (gap + delimiter) is the
            # annotated error span.
            span = scan_pattern(pattern_atom, input, cursor)
            break unless span

            resume = span[1]
            resyncs << {
              "offset" => cursor,
              "skipped" => input[cursor...resume],
              "resumed_at" => resume,
            }
          else
            # Inferred: scan for the next viable iteration start.
            found = nil
            scan = cursor
            while scan < max
              attempt = try_iteration(body_atom, input, scan)
              if attempt && attempt[1] > scan
                found = [scan, attempt[1], attempt[0]]
                break
              end
              scan += 1
            end
            break unless found

            skip_start, resume, value = found
            resyncs << {
              "offset" => cursor,
              "skipped" => input[cursor...skip_start],
              "resumed_at" => skip_start,
            }
            items << root_atom(entry_name).flatten(value)
          end
          cursor = resume
          rounds += 1
        end
        [items, resyncs]
      end

      # Scan forward from `from` for the first position where the
      # declared pattern matches with progress: [match_start, match_end].
      def scan_pattern(pattern_atom, input, from)
        scan = from
        while scan < input.length
          attempt = try_iteration(pattern_atom, input, scan)
          return [scan, attempt[1]] if attempt

          scan += 1
        end
        nil
      end

      # Apply the body atom at one position: [value, end_pos] on a
      # progressing match, nil otherwise.
      def try_iteration(atom, input, pos)
        source = Parsanol::Source.new(input)
        source.bytepos = pos
        context = Parsanol::Atoms::Context.new(nil, parser_class: atom.class)
        success, value = atom.apply(source, context, false)
        success && source.bytepos > pos ? [value, source.bytepos] : nil
      end

      # The root rule's repetition-body rule name, when the grammar is
      # a repetition spine (root = rep of a single rule reference).
      # Conservative: anything but rep/opt/cap wrapping a bare ref
      # returns nil and resync is skipped.
      SPINE_UNWRAP_KINDS = %i[rep opt cap].freeze

      def spine_body_rule(entry_name)
        root_rule = entry(entry_name)["root"]
        node = compiler.document.rules[root_rule.to_sym] ||
          compiler.document.rules[root_rule]
        while node.is_a?(Parsanol::PARG::Node) &&
            SPINE_UNWRAP_KINDS.include?(node.kind)
          node = node.a
        end
        node.is_a?(Parsanol::PARG::Node) && node.kind == :ref ? node.a : nil
      end

      # R1.5 (TODO.sota/1): the deepest repetition prefix the failed
      # journaling pass matched, shaped like the root (the item array
      # under the root rule's name). Nil when nothing matched.
      def recovery_partial(entry_name, stash = Parsanol::Recovery.take_partial)
        return nil if stash.nil?

        _end_pos, items, _tag = stash
        # The stash holds raw per-iteration results; the root atom's
        # flatten (the same laws the success shape goes through) turns
        # sequence-tagged iterations into their shaped values.
        flattened = items.map { |item| root_atom(entry_name).flatten(item) }
        root_name = entry(entry_name)["root"].to_sym
        { root_name => flattened }
      end

      # Recovery error wire — the rs engine's F7 shape (offset, line,
      # column, expected at the deepest position, ranked distinct
      # positions deepest-first), computed from the interpreter's cause
      # tree. `message` rides along for consumers that surface the
      # rendered text (lutaml-lml digs line/column from it).
      # Parity with parsanol::portable::parser::MAX_RANKED_FAILURES.
      MAX_RANKED_FAILURES = 8

      def recovery_error(err)
        cause = err.parse_failure_cause
        return { "offset" => nil, "message" => err.message } unless cause

        ranks = collect_ranks(cause)
        offset = ranks.keys.max
        line, column = cause.source&.line_and_column(offset)
        {
          "offset" => offset,
          "line" => line,
          "column" => column,
          # The deepest entry mirrors ranked's head — same as the rs
          # wire, where failure_wire and ranked[0] agree.
          "expected" => ranks[offset] || [],
          "ranked" => ranks.sort_by { |pos, _| -pos }
            .first(MAX_RANKED_FAILURES)
            .map { |pos, labels| [pos, labels] },
          "message" => err.message,
        }
      end

      def deepest_position(cause)
        max = cause.position
        Array(cause.children).each do |child|
          next if child.nil?

          max = [max, deepest_position(child)].max
        end
        max
      end

      # Distinct failure positions with the labels expected at each —
      # every cause node contributes its position and message; deeper
      # duplicates of the same position merge. Capped like the rs wire
      # (MAX_RANKED_FAILURES) at the reader, deepest first.
      def collect_ranks(cause, into = {})
        labels = into[cause.position] ||= []
        text = cause.message.to_s
        labels << text unless labels.include?(text)
        Array(cause.children).each do |child|
          next if child.nil?

          collect_ranks(child, into)
        end
        into
      end

      # Journaling re-parse — always on the Ruby engine (journaling
      # rides the interpreter's diagnostic reparse; the native engine
      # has no journal). Tree parity with the native engine is enforced
      # by the differential specs, so the observed captures agree.
      def recovery_journal(entry_name, input, _mode)
        Parsanol::Recovery.start_journal
        reparse_error = nil
        begin
          parse(entry_name, input, mode: :ruby)
        rescue Parsanol::ParseFailed => e
          # expected: the journaling pass fails at the same point
          reparse_error = recovery_error(e)
        end
        captures = Parsanol::Recovery.stop_journal.each_with_object({}) do |(name, value), out|
          # Both the initial attempt and the diagnostic re-parse journal
          # into the shared thread-local; identical observations dedupe.
          wire = value.is_a?(Slice) ? slice_wire(value) : value
          (out[name.to_s] ||= []) << wire
          out[name.to_s].uniq!
        end
        [captures, reparse_error]
      end

      def slice_wire(slice)
        { "value" => slice.to_s, "offset" => slice.offset,
          "length" => slice.content.length }
      end

      def test_to_hash(test)
        {
          "entry" => test.entry,
          "kind" => test.kind.to_s,
          "input" => test.input,
          "expect" => test.expect,
        }
      end

      # Rule documentation embedded from ## doc comments.
      def rule_docs = envelope.fetch("docs", {})

      # Structured parse diagnostics (PN 2): {offset, message} for the
      # deepest failure of the most recent parse attempt on this entry.
      # Structured parse diagnostics — the flat v1 wire format every
      # backend agrees on (parsanol-rs#145): offset, the expected-symbol
      # list, and a message, fetched out-of-band so success paths pay
      # nothing. Full cause trees stay a Ruby-side diagnostic.
      def parse_with_diagnostics(entry_name, input, mode: :native)
        shape = parse(entry_name, input, mode: mode)
        { "ok" => true, "offset" => nil, "expected" => [],
          "message" => nil, "shape" => shape }
      rescue Parsanol::ParseFailed => e
        cause = deepest_cause(e.parse_failure_cause)
        { "ok" => false, "offset" => cause&.position,
          "expected" => expected_labels_for(cause),
          "message" => cause&.message || e.message, "shape" => nil }
      end

      def expected_labels_for(cause)
        return [] unless cause.respond_to?(:expected)

        Array(cause.expected)
      end

      def deepest_cause(cause)
        return cause if cause.nil? || cause.children.empty?

        deepest = cause.children.filter_map { |child| deepest_cause(child) }
          .max_by { |node| node.position.to_i }
        (deepest&.position.to_i >= cause.position.to_i ? deepest : cause)
      end

      def table_rows(name)
        @table_cache ||= {}
        return @table_cache[name] if @table_cache.key?(name)

        declared = envelope["tables"].fetch(name) do
          raise ArtifactError, "artifact does not declare table #{name.inspect}"
        end
        if declared.is_a?(Hash) && declared.key?("rows")
          return @table_cache[name] = declared["rows"]
        end

        file = declared
        path = File.join(@tables_dir.to_s, file)
        raw = path.end_with?(".json") ? JSON.parse(PARG.read_utf8(path)) : YAML.safe_load(PARG.read_utf8(path), aliases: true)
        rows = case raw
               when Hash
                 raw.map { |key, value| { "name" => key.to_s }.merge(value.to_h.transform_keys(&:to_s)) }
               when Array then raw.map { |row| row.to_h.transform_keys(&:to_s) }
               else raise ArtifactError, "table #{name.inspect} must be a map or array"
               end
        @table_cache[name] = rows
      end

      # The envelope's optional grammar-to-model bindings section
      # (envelope v2, parsanol-rs#143): capture name -> model attribute
      # paths, type casts, cardinality, and preprocessing step refs,
      # declared once and consumed identically by every tier's binder.
      # Phase 1 validates the section's shape and exposes it as data.
      def bindings
        envelope["bindings"]
      end

      BINDINGS_ALLOWED_KEYS = %w[captures entries version].freeze

      def validate_bindings!(bindings)
        unless bindings.is_a?(Hash)
          raise ArtifactError, "bindings section must be a map (got #{bindings.class})"
        end

        unknown = bindings.keys - BINDINGS_ALLOWED_KEYS
        unless unknown.empty?
          raise ArtifactError, "bindings section has unknown keys: #{unknown.inspect}"
        end

        (bindings["captures"] || {}).each do |name, spec|
          unless spec.is_a?(Hash) && spec["path"].is_a?(String)
            raise ArtifactError,
                  "bindings capture #{name.inspect} must declare a string :path"
          end
        end
      rescue ArtifactError
        raise
      rescue StandardError => e
        raise ArtifactError, "malformed bindings section: #{e.class}: #{e.message}"
      end

      def compiler
        @compiler ||= begin
          document = Parser.new(envelope.fetch("source")).parse
          # The capture dialect is part of the baked contract. Envelopes
          # written before 1.3.110 carry no "mode" key and were compiled
          # as v1; re-parsing their source under today's v2 default would
          # silently reshape their trees (parsanol-ruby#350).
          document.mode = envelope.fetch("mode", "v1")
          # `use`-importing grammars carry dotted cross-grammar rule
          # references that only resolve once the imported sources merge;
          # without this the pure-Ruby path fails on artifacts whose
          # native atom graphs inline everything. The imported sources
          # sit beside the artifact (vendors ship them together).
          dirs = [path ? File.dirname(path) : nil, @imports_dir]
            .compact
            .select { |dir| File.directory?(dir) }
          Imports.merge!(document, dirs) unless dirs.empty?
          Compiler.new(document, @tables_dir)
        end
      end

      def root_atom(entry_name)
        rule = entry(entry_name).fetch("root")
        @compiled ||= {}
        @compiled[rule] ||= compiler.atom_for(rule)
      end

      def verify_checksum!
        stored = envelope["checksum"]
        computed = Compiler.checksum(envelope)
        return if stored == computed

        raise ArtifactError,
              "artifact checksum mismatch: stored #{stored.inspect}, " \
              "computed #{computed.inspect}"
      end
    end
  end
end
