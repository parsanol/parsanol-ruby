# frozen_string_literal: true

require "json"
require "yaml"

module Parsanol
  module PG
    # A compiled artifact envelope: load, verify checksum, parse inputs.
    #
    # The envelope's grammar section is the portable JSON the native engines
    # consume; the embedded PG source lets a Ruby runtime recompile the atom
    # tree locally without any other dependency.
    class Artifact
      attr_reader :envelope, :path, :tables_dir

      def self.load(path, tables_dir: nil)
        envelope = JSON.parse(File.read(path))
        new(envelope, path, tables_dir || File.dirname(path))
      end

      def self.from_json(text, tables_dir: nil)
        new(JSON.parse(text), nil, tables_dir)
      end

      def initialize(envelope, path, tables_dir)
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

      def parse_and_bind(entry_name, input, mode: :native)
        apply_bindings(entry_name, parse(entry_name, input, mode: mode))
      end

      # Re-run the grammar's in-file tests against this artifact. Returns
      # the failure descriptions; empty means every test passes.
      def run_tests(mode: :native)
        envelope.fetch("tests", []).filter_map do |test|
          entry_name = test["entry"] || entries.first
          begin
            bound = parse_and_bind(entry_name, test["input"], mode: mode)
            if test["kind"] == "reject"
              "test #{test['input'].inspect}: expected the input to be rejected"
            elsif test["kind"] == "example"
              mismatched = test["expect"].reject do |key, value|
                bound.key?(key.to_sym) && bound[key.to_sym] == value
              end
              next if mismatched.empty?

              "test #{test['input'].inspect}: expected captures " \
                "#{mismatched.transform_values(&:inspect).inspect}, got #{bound.inspect}"
            end
          rescue Parsanol::ParseFailed
            unless test["kind"] == "reject"
              "test #{test['input'].inspect}: expected the input to parse"
            end
          end
        end
      end

      # Rule documentation embedded from ## doc comments.
      def rule_docs = envelope.fetch("docs", {})

      def table_rows(name)
        @table_cache ||= {}
        return @table_cache[name] if @table_cache.key?(name)

        file = envelope["tables"].fetch(name) do
          raise ArtifactError, "artifact does not declare table #{name.inspect}"
        end
        path = File.join(@tables_dir.to_s, file)
        raw = path.end_with?(".json") ? JSON.parse(File.read(path)) : YAML.safe_load_file(path, aliases: true)
        rows = case raw
               when Hash
                 raw.map { |key, value| { "name" => key.to_s }.merge(value.to_h.transform_keys(&:to_s)) }
               when Array then raw.map { |row| row.to_h.transform_keys(&:to_s) }
               else raise ArtifactError, "table #{name.inspect} must be a map or array"
               end
        @table_cache[name] = rows
      end

      def compiler
        @compiler ||= begin
          document = Parser.new(envelope.fetch("source")).parse
          Compiler.new(document, @tables_dir)
        end
      end

      private

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
