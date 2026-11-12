# frozen_string_literal: true

module Parsanol
  module PARG
    # Base class for all PARG errors.
    class Error < StandardError; end

    # Raised when .parg source text cannot be tokenized or parsed.
    # `offset` is the character offset the parser failed at (from the
    # lexer's token stream), when known — the LSP maps it to a
    # line/character diagnostic position (F11).
    class ParseError < Error
      attr_reader :offset

      def initialize(message = nil, offset = nil)
        super(message)
        @offset = offset
      end
    end

    # Raised when a parsed document is semantically invalid: left recursion,
    # unknown rule references, shadowed alternatives, missing tables.
    class CompileError < Error; end

    # Raised when an artifact envelope is corrupt or its checksum mismatches.
    class ArtifactError < Error; end

    # A declared capture is present in the parse tree but reached the
    # bound map nowhere (parsanol-ruby#413): silent data loss made loud.
    class BindError < ArtifactError; end
  end
end
