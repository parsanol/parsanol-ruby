# frozen_string_literal: true

module Parsanol
  module PARG
    # Base class for all PARG errors.
    class Error < StandardError; end

    # Raised when .parg source text cannot be tokenized or parsed.
    class ParseError < Error; end

    # Raised when a parsed document is semantically invalid: left recursion,
    # unknown rule references, shadowed alternatives, missing tables.
    class CompileError < Error; end

    # Raised when an artifact envelope is corrupt or its checksum mismatches.
    class ArtifactError < Error; end
  end
end
