# frozen_string_literal: true

module Parsanol
  module PARG
    # F10 phase 2 (gate slice): every .parg source must parse under the parg
    # artifact — the language definition validates itself and every
    # grammar written in it. The artifact is authoritative for document
    # structure; the full shape->IR front end builds on this gate.
    module SelfHost
      module_function

      def artifact_path
        ENV["PG_ARTIFACT"] || begin
          dir = __dir__
          ancestors = []
          cursor = dir
          6.times do
            cursor = File.expand_path("..", cursor)
            ancestors << File.join(cursor, "pubid", "pubid-grammar", "artifacts", "parg.json")
          end
          ancestors.find { |candidate| File.file?(candidate) }
        end
      end

      def available?
        !artifact_path.nil?
      end

      # Parse `source` under the parg artifact. Returns the shape tree, or
      # raises ParseFailed with the native position when the source is not
      # valid PARG as defined by the self-hosting grammar.
      def validate(source)
        raise ArtifactError, "parg artifact not found (set PG_ARTIFACT)" unless available?

        envelope = JSON.parse(PARG.read_utf8(artifact_path))
        artifact = Artifact.new(envelope, nil, nil)
        artifact.parse("file", source)
      end

      # true when the source parses under the self-hosting artifact.
      def valid?(source)
        validate(source)
        true
      rescue Parsanol::ParseFailed, ArtifactError
        false
      end
    end
  end
end
