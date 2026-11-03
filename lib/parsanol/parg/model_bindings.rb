# frozen_string_literal: true

require "json"
require "yaml"

module Parsanol
  module PARG
    # The rule -> model binding table embedded in an artifact (coradoc#307).
    #
    # A sidecar (JSON or YAML) declares, per rule, which model a raw-tree
    # node inflates to:
    #
    #   version: 1
    #   rules:
    #     thematic_break:
    #       keys: [hr]                  # exact capture-key set of the node
    #       model: HorizontalRule
    #       captures: {}                # attribute => scalar capture key
    #       children: {}                # attribute => nested-node capture key
    #       defaults: { style: "---" }  # attributes fixed by the rule
    #
    # `parg compile --model-bindings FILE` embeds it under the envelope's
    # additive "model_bindings" key; artifacts compiled without a sidecar
    # carry no such key and are byte-identical to before. The table is not
    # parse semantics, so semantics_hash ignores it; the checksum covers it.
    module ModelBindings
      KEY = "model_bindings"
      VERSION = 1
      RULE_FIELDS = %w[keys model captures children defaults].freeze

      module_function

      # @param path [String] a .json / .yml / .yaml sidecar
      # @return [Hash] the validated, string-keyed table
      def load(path)
        text = File.read(path, encoding: Encoding::UTF_8)
        raw = File.extname(path).match?(/\.ya?ml\z/i) ? YAML.safe_load(text) : JSON.parse(text)
        normalize(raw)
      rescue JSON::ParserError, Psych::SyntaxError => e
        raise ArtifactError, "model bindings #{path}: #{e.message}"
      end

      # @return [Hash] the table with every rule filled to the full shape
      def normalize(raw)
        raise ArtifactError, "model bindings: expected a mapping" unless raw.is_a?(Hash)

        table = stringify(raw)
        unless table["version"] == VERSION
          raise ArtifactError, "model bindings: unsupported version #{table['version'].inspect} (want #{VERSION})"
        end

        rules = table["rules"]
        raise ArtifactError, "model bindings: `rules` must be a mapping" unless rules.is_a?(Hash)

        { "version" => VERSION, "rules" => rules.to_h { |name, rule| [name, normalize_rule(name, rule)] } }
      end

      def normalize_rule(name, rule)
        raise ArtifactError, "model bindings: rule #{name.inspect} must be a mapping" unless rule.is_a?(Hash)

        unknown = rule.keys - RULE_FIELDS
        raise ArtifactError, "model bindings: rule #{name.inspect} has unknown field #{unknown.first.inspect}" unless unknown.empty?
        unless rule["model"].is_a?(String) && !rule["model"].empty?
          raise ArtifactError, "model bindings: rule #{name.inspect} needs a `model`"
        end
        unless rule["keys"].is_a?(Array) && !rule["keys"].empty?
          raise ArtifactError, "model bindings: rule #{name.inspect} needs non-empty `keys`"
        end

        {
          "keys" => rule["keys"].map(&:to_s),
          "model" => rule["model"],
          "captures" => hash_field(name, rule, "captures"),
          "children" => hash_field(name, rule, "children"),
          "defaults" => hash_field(name, rule, "defaults"),
        }
      end

      def hash_field(name, rule, field)
        value = rule.fetch(field, {})
        raise ArtifactError, "model bindings: rule #{name.inspect} `#{field}` must be a mapping" unless value.is_a?(Hash)

        value
      end

      def stringify(value)
        case value
        when Hash then value.to_h { |key, item| [key.to_s, stringify(item)] }
        when Array then value.map { |item| stringify(item) }
        else value
        end
      end

      # Embed a table in an envelope and re-seal the canonical checksum.
      def embed(envelope, table)
        sealed = envelope.merge(KEY => table)
        sealed["checksum"] = Compiler.checksum(sealed)
        sealed
      end

      # Read an artifact file for the dump: JSON plus checksum verification
      # only, so no grammar source and no custom-atom class is needed.
      def read_envelope(path)
        envelope = JSON.parse(File.read(path, encoding: Encoding::UTF_8))
        unless envelope.is_a?(Hash) && envelope["checksum"] == Compiler.checksum(envelope)
          raise ArtifactError, "#{path}: artifact checksum mismatch"
        end

        envelope
      rescue JSON::ParserError => e
        raise ArtifactError, "#{path}: #{e.message}"
      end

      # @return [Hash, nil] the embedded table, nil for an artifact without one
      def from(envelope)
        envelope[KEY]
      end

      # The machine-readable dump: rule -> model/keys/captures/children/defaults.
      def dump(envelope)
        table = from(envelope) || { "version" => VERSION, "rules" => {} }
        JSON.pretty_generate(table)
      end
    end
  end
end
