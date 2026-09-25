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

      def parse(entry_name, input)
        root_atom(entry_name).parse(input)
      end

      def apply_bindings(entry_name, shape)
        Bindings.apply(self, entry(entry_name), shape)
      end

      def parse_and_bind(entry_name, input)
        apply_bindings(entry_name, parse(entry_name, input))
      end

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
