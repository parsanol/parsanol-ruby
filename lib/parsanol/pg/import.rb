# frozen_string_literal: true

module Parsanol
  module PG
    # Foreign-grammar importers. Each converts a foreign grammar notation to
    # PG source text — the .pg file is committed as the single source of
    # truth, then compiled like any hand-written grammar. Import results are
    # self-checked: the emitted source must round-trip through PG::Parser.
    module Import
      class Error < PG::Error; end

      autoload :Abnf, "parsanol/pg/importers/abnf"
      autoload :Ebnf, "parsanol/pg/importers/ebnf"
      autoload :Pest, "parsanol/pg/importers/pest"

      KINDS = %i[abnf ebnf pest].freeze

      module_function

      def import(kind, text)
        source = case kind
                 when :abnf then Abnf.call(text)
                 when :ebnf then Ebnf.call(text)
                 when :pest then Pest.call(text)
                 else
                   raise Error,
                         "unknown import kind #{kind.inspect} (supported: #{KINDS.map(&:inspect).join(', ')})"
                 end
        Parser.new(source).parse
        source
      end
    end
  end
end
