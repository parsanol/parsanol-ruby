# frozen_string_literal: true

require "digest"
require "json"
require "yaml"

module Parsanol
  module PG
    # Compiles a Document to executable atoms and an artifact envelope.
    #
    # Responsibilities:
    # - build the parsanol atom tree (lazy Entity web; recursive grammars OK)
    # - reject left recursion at compile time (would hang every PEG engine)
    # - reject shadowed alternatives; warn on order-dependent first-set overlap
    # - expand `alt from_table` data-driven alternatives (longest-first)
    # - emit the artifact envelope: portable Grammar JSON (the same format the
    #   native engines register), bindings, preprocess steps, checksum
    class Compiler
      EPS = :eps
      ANY = :any

      Result = Struct.new(:atoms, :warnings, :envelope)

      def self.compile(document, tables_dir: nil)
        new(document, tables_dir).compile
      end

      # Canonical checksum over an envelope (everything except the checksum
      # itself). Used both when building an artifact and when verifying one.
      def self.checksum(envelope)
        payload = envelope.except("checksum")
        "sha256:#{Digest::SHA256.hexdigest(JSON.generate(canonicalize(payload)))}"
      end

      def self.canonicalize(obj)
        case obj
        when Hash then obj.sort.to_h.transform_values { |value| canonicalize(value) }
        when Array then obj.map { |value| canonicalize(value) }
        else obj
        end
      end

      def initialize(document, tables_dir)
        @document = document
        @tables_dir = tables_dir
        @atom_cache = {}
        @first_cache = {}.compare_by_identity
        @ref_stack = []
        @tables = {}
        @warnings = []
      end

      def compile
        @document.rules.each_key { |name| atom_for(name) }
        errors = Lints.errors(@document, self)
        raise CompileError, errors.join("\n") unless errors.empty?

        @warnings = Lints.warnings(@document, self)
        failures = run_tests
        raise CompileError, failures.join("\n") unless failures.empty?

        envelope = build_envelope
        Result.new(@atom_cache, @warnings, envelope)
      end

      def atom_for(name)
        @atom_cache[name] ||= build_atom(fetch_rule(name))
      end

      def record_warning(message)
        @warnings << message
      end

      def nullable?(node)
        first_set(node).include?(EPS)
      end

      def first_set(node)
        @first_cache[node] ||= compute_first(node)
      end

      def find_left_cycle(name)
        find_left_cycle_from(name, [], {})
      end

      private

      # In-file grammar tests run at compile time: the build fails when an
      # accept/example test does not parse or an example's expected capture
      # pairs do not match the bound result.
      def run_tests
        return [] if @document.tests.empty?

        default_entry = resolve_default_entry
        view = test_view
        @document.tests.filter_map do |test|
          entry_name = test.entry || default_entry
          rule = @document.entries.fetch(entry_name)
          begin
            shape = atom_for(rule).parse(test.input)
            if test.kind == :reject
              "test #{test.input.inspect}: expected the input to be rejected"
            elsif test.kind == :example
              bound = Bindings.apply(view, { "bindings" => binding_list(rule) }, shape)
              mismatched = test.expect.reject { |key, value| bound.key?(key) && bound[key] == value }
              next if mismatched.empty?

              "test #{test.input.inspect}: expected captures " \
                "#{mismatched.transform_values(&:inspect).inspect}, got #{bound.inspect}"
            end
          rescue Parsanol::ParseFailed
            unless test.kind == :reject
              "test #{test.input.inspect}: expected the input to parse"
            end
          end
        end
      end

      def resolve_default_entry
        entries = @document.entries.keys
        return entries.first if entries.size == 1

        raise CompileError,
              "tests need an explicit entry (grammar has #{entries.size})"
      end

      # Bindings.apply needs the envelope-shaped preprocess/tables surface;
      # at compile time the document and loaded tables play that role.
      def test_view
        @test_view ||= Object.new.tap do |view|
          view.define_singleton_method(:envelope) do
            { "preprocess" => @document.preprocess }
          end
          view.define_singleton_method(:table_rows) { |name| table_rows(name) }
        end
      end

      def binding_list(rule)
        @document.bindings[rule].to_a.map do |binding|
          {
            "capture" => binding.capture,
            "path" => binding.path,
            "type" => binding.type,
            "card" => binding.card,
            "preprocess" => binding.preprocess,
          }
        end
      end

      def fetch_rule(name)
        @document.rules[name] || raise(CompileError, "unknown rule #{name.inspect}")
      end

      def build_atom(node)
        case node.kind
        when :lit
          if node.b
            Atoms::Re.new("(?i:#{Regexp.escape(node.a)})")
          else
            Atoms::Str.new(node.a)
          end
        when :class then Atoms::Re.new(class_pattern(node.a))
        when :seq
          atoms = node.a.map { |child| build_atom(child) }
          atoms.length == 1 ? atoms.first : Atoms::Sequence.new(*atoms)
        when :alt
          Atoms::Alternative.new(*node.a.map { |child| build_atom(child) })
        when :rep
          Atoms::Repetition.new(build_atom(node.a), node.b, node.c)
        when :opt then Atoms::Repetition.new(build_atom(node.a), 0, 1, :maybe)
        when :pred then Atoms::Lookahead.new(build_atom(node.b), node.a)
        when :cap then Atoms::Named.new(build_atom(node.b), node.a.to_sym)
        when :ref then Atoms::Entity.new(node.a) { atom_for(node.a) }
        when :table
          values = table_column(node.a, node.b)
          Atoms::Alternative.new(*values.map { |value| Atoms::Str.new(value) })
        else
          raise CompileError, "unknown node kind #{node.kind.inspect}"
        end
      end

      def class_pattern(ranges)
        body = ranges.map do |lo, hi|
          if lo == hi
            escape_codepoint(lo)
          elsif hi - lo + 1 > 2
            "#{endpoint(lo)}-#{endpoint(hi)}"
          else
            lo.upto(hi).map { |code| escape_codepoint(code) }.join
          end
        end
        "[#{body.join}]"
      end

      # Range endpoints always use explicit escapes so the range operator
      # can never be ambiguous with an escaped literal.
      def endpoint(code)
        code < 0x7F ? format("\\x%02x", code) : format("\\u%04x", code)
      end

      def escape_codepoint(code)
        return format("\\x%02x", code) if code < 0x20 || code == 0x7F
        return format("\\u%04x", code) if code > 0x7E
        return "\\#{code.chr}" if ["\\", "]", "[", "^", "-"].include?(code.chr)

        code.chr
      end

      def table_column(table, column)
        rows = table_rows(table)
        values = rows.filter_map { |row| row[column] }.map(&:to_s).reject(&:empty?)
        if values.empty?
          raise CompileError,
                "table #{table.inspect} has no column #{column.inspect}"
        end

        values.uniq.sort_by { |value| [-value.length, value] }
      end

      def table_rows(name)
        return @tables[name] if @tables.key?(name)

        path = %w[.yaml .yml .json]
          .map { |ext| File.join(@tables_dir.to_s, "#{name}#{ext}") }
          .find { |candidate| File.file?(candidate) }
        if path.nil?
          raise CompileError,
                "table #{name.inspect} not found under #{@tables_dir.inspect}"
        end

        raw = if path.end_with?(".json")
                JSON.parse(File.read(path))
              else
                YAML.safe_load_file(path, aliases: true)
              end
        rows = case raw
               when Hash
                 raw.map do |key, value|
                   { "name" => key.to_s }.merge(value.to_h.transform_keys(&:to_s))
                 end
               when Array then raw.map { |row| row.to_h.transform_keys(&:to_s) }
               else
                 raise CompileError, "table #{name.inspect} must be a map or array"
               end
        @tables[name] = rows
      end

      # ---- analysis ------------------------------------------------------

      def lint
        errors = []
        @document.rules.each do |name, node|
          if (cycle = find_left_cycle(name))
            errors << "left recursion detected: #{cycle.join(' -> ')}"
          end
          errors.concat(check_alternatives(name, node)) if node.kind == :alt
        end
        errors
      end

      def check_alternatives(name, node)
        errors = []
        branches = node.a
        branches.each_with_index do |branch, index|
          if nullable?(branch) && index < branches.length - 1
            errors << "rule #{name}: branch #{index + 1} can match empty input " \
                      "and shadows all later branches"
          end
          branches[(index + 1)..].each_with_index do |later, j|
            compare_branches(name, branch, index + 1, later, index + j + 2, errors)
          end
        end
        errors
      end

      def find_left_cycle_from(name, path, visiting)
        return path[(path.index(name))..] if path.include?(name)
        return nil if visiting[name] == :done

        visiting[name] = :active
        leftmost_refs(fetch_rule(name)).each do |dep|
          cycle = find_left_cycle_from(dep, path + [name], visiting)
          return cycle if cycle
        end
        visiting[name] = :done
        nil
      end

      def leftmost_refs(node)
        case node.kind
        when :ref then [node.a]
        when :seq
          refs = []
          node.a.each do |item|
            refs.concat(leftmost_refs(item))
            break unless nullable?(item)
          end
          refs.uniq
        when :alt then node.a.flat_map { |branch| leftmost_refs(branch) }.uniq
        when :rep, :opt then leftmost_refs(node.a)
        when :pred, :cap then leftmost_refs(node.b)
        else []
        end
      end

      def compute_first(node)
        case node.kind
        when :lit
          set = Set.new(node.a[0].bytes)
          set += node.a[0].upcase.bytes + node.a[0].downcase.bytes if node.b
          set
        when :class
          total = node.a.inject(0) { |acc, (lo, hi)| acc + (hi - lo + 1) }
          if total > 256
            Set.new([ANY])
          else
            node.a.inject(Set.new) do |acc, (lo, hi)|
              acc + lo.upto(hi).to_set
            end
          end
        when :seq
          set = Set.new
          node.a.each do |item|
            item_first = first_set(item)
            set += item_first - [EPS]
            break if item_first.include?(ANY) || !item_first.include?(EPS)
          end
          set << EPS if node.a.all? { |item| first_set(item).include?(EPS) }
          set
        when :alt
          node.a.inject(Set.new) { |acc, branch| acc + first_set(branch) }
        when :rep
          set = first_set(node.a).dup
          set << EPS if node.b.zero?
          set
        when :opt then first_set(node.a) + [EPS]
        when :pred
          node.a ? first_set(node.b) : Set.new([ANY])
        when :cap then first_set(node.b)
        when :ref
          if @ref_stack.include?(node.a)
            Set.new([ANY, EPS])
          else
            @ref_stack << node.a
            begin
              first_set(fetch_rule(node.a))
            ensure
              @ref_stack.pop
            end
          end
        when :table
          values = begin
            table_column(node.a, node.b)
          rescue CompileError
            []
          end
          values.inject(Set.new) { |acc, value| acc + value[0].bytes }
        else
          Set.new([ANY])
        end
      end

      # ---- artifact envelope ----------------------------------------------

      def build_envelope
        entries = @document.entries.to_h do |name, rule|
          [name, entry_envelope(rule)]
        end
        envelope = {
          "version" => @document.version,
          "grammar" => @document.grammar_name,
          "shape" => "parsanol-tree/v2",
          "binding_version" => 1,
          "entries" => entries,
          "preprocess" => @document.preprocess,
          "tables" => table_manifest,
          "lint" => { "order_warnings" => @warnings.uniq },
          "tests" => @document.tests.map do |test|
            {
              "entry" => test.entry,
              "kind" => test.kind.to_s,
              "input" => test.input,
              "expect" => test.expect.transform_keys(&:to_s),
            }
          end,
          "docs" => @document.docs,
          "source" => @document.source,
        }
        envelope["checksum"] = Compiler.checksum(envelope)
        envelope
      end

      def entry_envelope(rule)
        {
          "root" => rule,
          "grammar" => JSON.parse(portable_json(rule)),
          "bindings" => binding_list(rule),
        }
      end

      def portable_json(rule)
        Parsanol::Native::Parser.serialize_grammar(atom_for(rule))
      end

      def table_manifest
        @document.rules.each_value { |node| collect_tables(node) }
        @tables.keys.to_h { |name| [name, "#{name}.yaml"] }
      end

      def collect_tables(node)
        case node.kind
        when :table then table_rows(node.a)
        when :seq, :alt then node.a.each { |child| collect_tables(child) }
        when :rep, :opt then collect_tables(node.a)
        when :pred, :cap then collect_tables(node.b)
        end
      end
    end
  end
end
