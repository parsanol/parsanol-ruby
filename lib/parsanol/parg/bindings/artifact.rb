# frozen_string_literal: true

require "json"

module Parsanol
  module PARG
    module Bindings
      # The declared per-target binding artifact (parsanol-ruby#432): from
      # one compiled grammar the toolchain emits one checksummed bindings
      # artifact per target, each carrying the entry binding records and
      # pinned to its grammar by source hash. Declared and diffable, not
      # baked: consumers pin and verify what they load.
      #
      # Boundary: the records carry AST construction only — the
      # production-to-binding mapping. Semantics live in the model layer
      # (LML), never here. Execution resources (preprocess steps and their
      # tables) resolve from the PAIRED parse artifact, which is why
      # #pair_with! is mandatory before #apply.
      class Artifact
        KIND = "parg-bindings"
        TARGETS = %w[ruby rs ts python].freeze
        SUPPORTED_BINDING_VERSION = 1

        attr_reader :target, :binding_version, :grammar, :grammar_version,
                    :grammar_source_hash, :entries, :payload

        class << self
          # Emit the per-target bindings artifact from a compiled parse
          # artifact envelope. Returns the verified artifact; the payload
          # is checksummed with the artifact checksum scheme (canonical
          # JSON sha256 over everything except the checksum itself), so
          # every engine re-derives it identically.
          def emit(envelope, target)
            target = target.to_s
            unless TARGETS.include?(target)
              raise ArtifactError,
                    "unknown binding target #{target.inspect}; known: #{TARGETS.join(', ')}"
            end

            artifact = new(build(envelope, target))
            artifact.verify
          end

          # The emitted artifact as JSON (the bake/CLI surface).
          def emit_json(envelope, target)
            JSON.generate(emit(envelope, target).payload)
          end

          # Parse and fully verify an emitted bindings artifact. `target:`
          # pins the expected target; omit it in multi-target tooling that
          # accepts any declared target.
          def from_json(json, target: nil)
            artifact = new(JSON.parse(json))
            artifact.verify
            artifact.verify_target!(target) unless target.nil?
            artifact
          end

          private

          def build(envelope, target)
            payload = {
              "artifact_kind" => KIND,
              "target" => target,
              "binding_version" => SUPPORTED_BINDING_VERSION,
              "grammar" => envelope["grammar"],
              "grammar_version" => envelope["version"],
              "grammar_source_hash" => envelope["source_hash"],
              "shape" => envelope["shape"],
              "entries" => envelope["entries"].to_h do |name, entry|
                [name, { "bindings" => entry["bindings"].to_a }]
              end,
            }
            payload.merge("checksum" => Compiler.checksum(payload))
          end
        end

        def initialize(payload)
          raise ArtifactError, "bindings artifact payload must be an object" unless payload.is_a?(Hash)

          @payload = payload
          @target = payload["target"]
          @binding_version = payload["binding_version"]
          @grammar = payload["grammar"]
          @grammar_version = payload["grammar_version"]
          @grammar_source_hash = payload["grammar_source_hash"]
          @entries = payload["entries"]
          @parg_artifact = nil
        end

        # Structural verification: kind, checksum, binding version,
        # target, entries map. Every loader path goes through here.
        def verify
          unless @payload["artifact_kind"] == KIND
            raise ArtifactError,
                  "not a #{KIND} artifact (artifact_kind #{@payload['artifact_kind'].inspect})"
          end

          expected = Compiler.checksum(@payload)
          actual = @payload["checksum"]
          unless actual.is_a?(String) && actual == expected
            raise ArtifactError,
                  "bindings artifact checksum mismatch: expected #{expected}, got #{actual.inspect}"
          end

          unless TARGETS.include?(@target)
            raise ArtifactError,
                  "unknown binding target #{@target.inspect}; known: #{TARGETS.join(', ')}"
          end
          unless @binding_version == SUPPORTED_BINDING_VERSION
            raise ArtifactError,
                  "unsupported binding_version #{@binding_version.inspect} " \
                  "(supported: #{SUPPORTED_BINDING_VERSION})"
          end
          unless @entries.is_a?(Hash)
            raise ArtifactError, "bindings artifact carries no entries map"
          end

          self
        end

        def verify_target!(target)
          target = target.to_s
          return if @target == target

          raise ArtifactError,
                "bindings artifact targets #{@target.inspect}, not #{target.inspect}"
        end

        # Pair with the parse artifact this layer was compiled from: same
        # grammar, same version, same source. The pairing is what lets
        # apply resolve preprocess references — they live in the parse
        # artifact's checksummed envelope.
        def pair_with!(parg_artifact)
          envelope = parg_artifact.envelope
          mismatches = []
          mismatches << "grammar (#{@grammar.inspect} vs #{envelope['grammar'].inspect})" if @grammar != envelope["grammar"]
          if @grammar_version != envelope["version"]
            mismatches << "version (#{@grammar_version.inspect} vs #{envelope['version'].inspect})"
          end
          if @grammar_source_hash != envelope["source_hash"]
            mismatches << "source_hash (#{@grammar_source_hash.inspect} vs #{envelope['source_hash'].inspect})"
          end
          unless mismatches.empty?
            raise ArtifactError,
                  "bindings artifact does not pair with the parse artifact: #{mismatches.join(', ')}"
          end

          @parg_artifact = parg_artifact
          self
        end

        def entry(name)
          @entries.fetch(name) { raise ArtifactError, "unknown entry #{name.inspect}" }
        end

        def bindings(name)
          entry(name)["bindings"]
        end

        def entry_names
          @entries.keys
        end

        # Materialize the bound map from a parse shape using the DECLARED
        # records. The paired parse artifact supplies entry context and
        # preprocess resolution; the same Bindings.apply runs as for the
        # embedded records, so a standalone artifact and its parse
        # artifact's baked records produce identical bound maps.
        def apply(entry_name, shape)
          parg = @parg_artifact
          if parg.nil?
            raise ArtifactError,
                  "pair_with! the parse artifact before applying bindings"
          end

          crafted = { "name" => entry_name, "bindings" => bindings(entry_name) }
          Bindings.apply(parg, crafted, shape)
        end
      end
    end
  end
end
