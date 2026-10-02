# frozen_string_literal: true

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
      attr_reader :envelope, :path, :tables_dir

      def self.load(path, tables_dir: nil)
        envelope = JSON.parse(PARG.read_utf8(path))
        new(envelope, path, tables_dir || File.dirname(path))
      end

      def self.from_json(text, tables_dir: nil)
        new(JSON.parse(text), nil, tables_dir)
      end

      SUPPORTED_SHAPE = "parsanol-tree/v2"

      def initialize(envelope, path, tables_dir)
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
        @path = path
        @tables_dir = tables_dir
        verify_checksum!
        @compiler = nil
      end

      def version = envelope["version"]

      def entries = envelope["entries"].keys

      def entry(name)
        envelope["entries"].fetch(name) do
          raise ArtifactError, "unknown entry #{name.inspect}"
        end
      end

      # Parse via the native engine: the envelope's grammar section is the
      # exact portable JSON the Rust side registers, so the artifact parse
      # path is a straight register-and-run — no Ruby recompilation. The
      # Ruby atom runtime (mode: :ruby) remains available explicitly, and
      # serves as the fallback on platforms without the extension.
      def parse(entry_name, input, mode: :native)
        case mode
        when :native
          if Native.available?
            return Native.parse(JSON.generate(entry(entry_name).fetch("grammar")), input)
          end

          root_atom(entry_name).parse(input)
        when :ruby
          root_atom(entry_name).parse(input)
        else
          raise ArgumentError, "unknown mode #{mode.inspect} (use :native or :ruby)"
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
      def run_test_list(tests, mode: :native)
        tests.filter_map do |test|
          hash = test.is_a?(Document::Test) ? test_to_hash(test) : test
          entry_name = hash["entry"] || entries.first
          begin
            bound = parse_and_bind(entry_name, hash["input"], mode: mode)
            if hash["kind"] == "reject"
              "test #{hash['input'].inspect}: expected the input to be rejected"
            elsif hash["kind"] == "example"
              expect = hash["expect"].to_h { |key, value| [key.to_sym, value] }
              mismatched = expect.reject { |key, value| bound.key?(key) && bound[key] == value }
              next if mismatched.empty?

              "test #{hash['input'].inspect}: expected captures " \
                "#{mismatched.transform_values(&:inspect).inspect}, got #{bound.inspect}"
            end
          rescue Parsanol::ParseFailed
            unless hash["kind"] == "reject"
              "test #{hash['input'].inspect}: expected the input to parse"
            end
          end
        end
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
          # `use`-importing grammars carry dotted cross-grammar rule
          # references that only resolve once the imported sources merge;
          # without this the pure-Ruby path fails on artifacts whose
          # native atom graphs inline everything. The imported sources
          # sit beside the artifact (vendors ship them together).
          imports_dir = path && File.directory?(File.dirname(path)) ? File.dirname(path) : nil
          Imports.merge!(document, [imports_dir].compact) if imports_dir
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
