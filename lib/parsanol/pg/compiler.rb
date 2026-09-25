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
        errors = lint
        raise CompileError, errors.join("\n") unless errors.empty?

        envelope = build_envelope
        Result.new(@atom_cache, @warnings, envelope)
      end

      def atom_for(name)
        @atom_cache[name] ||= build_atom(fetch_rule(name))
      end

      private

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
        body = ranges.flat_map do |lo, hi|
          if lo == hi
            [escape_class_char(lo.chr)]
          elsif (hi - lo + 1) > 256
            [escape_class_char(lo.chr), "-", escape_class_char(hi.chr)]
          else
            lo.upto(hi).map { |byte| escape_class_char(byte.chr) }
          end
        end
        "[#{body.join}]"
      end

      def escape_class_char(char)
        return format("\\x%02x", char.ord) if char.ord < 0x20 || char.ord == 0x7F
        return "\\#{char}" if ["\\", "]", "[", "^", "-"].include?(char)

        char
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
          next unless nullable(branch) && index < branches.length - 1

          errors << "rule #{name}: branch #{index + 1} can match empty input " \
                    "and shadows all later branches"
        end
        branches.each_with_index do |earlier, i|
          branches[(i + 1)..].each_with_index do |later, j|
            compare_branches(name, earlier, i + 1, later, i + j + 2, errors)
          end
        end
        errors
      end

      def compare_branches(name, earlier, earlier_n, later, later_n, errors)
        earlier_lit = literal_string(earlier)
        later_lit = literal_string(later)
        shadowed = false
        if earlier_lit && later_lit
          if earlier_lit == later_lit
            errors << "rule #{name}: branches #{earlier_n} and #{later_n} are identical"
            return
          elsif later_lit.start_with?(earlier_lit)
            errors << "rule #{name}: branch #{earlier_n} (#{earlier_lit.inspect}) " \
                      "shadows branch #{later_n} (#{later_lit.inspect}) — " \
                      "reorder longest-first or the shorter always wins"
            shadowed = true
          end
        end
        first_earlier = first_set(earlier) - [EPS]
        first_later = first_set(later) - [EPS]
        return if shadowed

        if first_earlier.include?(ANY) || first_later.include?(ANY)
          @warnings << "rule #{name}: branches #{earlier_n} and #{later_n} are " \
                       "order-dependent (first set not statically known)"
          return
        end
        return if !first_earlier.intersect?(first_later)

        @warnings << "rule #{name}: branches #{earlier_n} and #{later_n} are " \
                     "order-dependent (shared first bytes); ordered choice is decisive"
      end

      def literal_string(node)
        case node.kind
        when :lit then node.a
        when :seq
          node.a.map { |child| literal_string(child) }.join if node.a.all? { |child| child.kind == :lit }
        end
      end

      def find_left_cycle(name)
        find_left_cycle_from(name, [], {})
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
            break unless nullable(item)
          end
          refs.uniq
        when :alt then node.a.flat_map { |branch| leftmost_refs(branch) }.uniq
        when :rep, :opt then leftmost_refs(node.a)
        when :pred, :cap then leftmost_refs(node.b)
        else []
        end
      end

      def nullable(node)
        first_set(node).include?(EPS)
      end

      def first_set(node)
        @first_cache[node] ||= compute_first(node)
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
          "source" => @document.source,
        }
        envelope["checksum"] = Compiler.checksum(envelope)
        envelope
      end

      def entry_envelope(rule)
        {
          "root" => rule,
          "grammar" => JSON.parse(portable_json(rule)),
          "bindings" => @document.bindings[rule].to_a.map do |binding|
            {
              "capture" => binding.capture,
              "path" => binding.path,
              "type" => binding.type,
              "card" => binding.card,
              "preprocess" => binding.preprocess,
            }
          end,
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
