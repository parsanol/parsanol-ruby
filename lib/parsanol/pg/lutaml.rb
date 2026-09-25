# frozen_string_literal: true

module Parsanol
  module PG
    # lutaml-model integration: register a PG artifact as a lutaml-model
    # string format, giving every Serializable class from_<format> —
    # artifact parse -> bindings -> model instance.
    #
    #   Parsanol::PG::Lutaml.register(
    #     IsoIdentifier,
    #     format_name: :pubid_iso,
    #     artifact: "artifacts/iso.json",
    #     entry: "identifier",
    #   )
    #   IsoIdentifier.from_pubid_iso("ISO/IEC 12345-1:2020")
    #
    # Registration goes through ::Lutaml::Model::FormatRegistry (the same
    # extension point as xml/json/yaml), so the format participates in the
    # framework's format metadata and error typing. to_<format> (render)
    # arrives with artifact render specs.
    module Lutaml
      module_function

      def register(model_class, format_name:, artifact:, entry:, tables_dir: nil)
        unless defined?(::Lutaml::Model)
          raise Error, "lutaml-model is not available; add it to your bundle"
        end

        art = Artifact.load(artifact, tables_dir: tables_dir)
        entry_name = entry

        adapter = Class.new do
          define_singleton_method(:parse) do |data, _options = {}|
            art.parse_and_bind(entry_name, data)
          end
        end

        ::Lutaml::Model::FormatRegistry.register(
          format_name,
          mapping_class: ::Lutaml::Model::Mapping,
          adapter_class: adapter,
          transformer: artifact_transformer(model_class, art, entry_name),
          error_types: [Parsanol::ParseFailed],
        )

        model_class.define_singleton_method(:"from_#{format_name}") do |input, _options = {}|
          new(art.parse_and_bind(entry_name, input))
        end
        format_name
      end

      def artifact_transformer(model_class, artifact, entry_name)
        Class.new do
          define_singleton_method(:name) { "#{model_class.name}PGTransform" }

          define_method(:data_to_model) do |data, _format, _options = {}|
            model_class.new(data)
          end

          define_singleton_method(:from_pg) do |input|
            model_class.new(artifact.parse_and_bind(entry_name, input))
          end
        end
      end
    end
  end
end
