# frozen_string_literal: true

module Parsanol
  # PG — the parsanol grammar language.
  #
  # A text source format for parsanol grammars: human-readable, ABNF/RFC
  # flavoured, PEG semantics (ordered choice). PG sources compile to a
  # checksummed artifact envelope whose grammar section is the same portable
  # JSON the native engines register — the text is the contract, the JSON is
  # its compiled form.
  module PG
    autoload :Error, "parsanol/pg/error"
    autoload :ParseError, "parsanol/pg/error"
    autoload :CompileError, "parsanol/pg/error"
    autoload :ArtifactError, "parsanol/pg/error"
    autoload :Node, "parsanol/pg/node"
    autoload :Lexer, "parsanol/pg/lexer"
    autoload :Parser, "parsanol/pg/parser"
    autoload :Document, "parsanol/pg/document"
    autoload :Compiler, "parsanol/pg/compiler"
    autoload :Artifact, "parsanol/pg/artifact"
    autoload :Bindings, "parsanol/pg/bindings"
    autoload :Lutaml, "parsanol/pg/lutaml"
    autoload :Import, "parsanol/pg/import"
    autoload :CLI, "parsanol/pg/cli"
    autoload :Suite, "parsanol/pg/authoring"
    autoload :Schema, "parsanol/pg/authoring"
  end
end
