# frozen_string_literal: true

module Parsanol
  module PG
    # Registry of preprocessing operations (OCP): deterministic, data-only
    # transformations applied between capture collection and type cast.
    # New ops register here — neither Bindings nor the compiler changes.
    # Non-deterministic rules are NOT registrable: they belong to the
    # language-specific data-model ingestion end (PN 5).
    module Preprocess
      class << self
        def register(name, &operation)
          operations[name.to_sym] = operation
        end

        def apply(step, value, source)
          operation = operations.fetch(step["op"].to_sym) do
            raise ArtifactError, "unknown preprocess op #{step['op'].inspect}"
          end
          operation.call(step, value, source)
        end

        def operations
          @operations ||= {}
        end
      end

      register :table_lookup do |step, value, source|
        map = source.table_rows(step["table"]).to_h do |row|
          [row[step["from"]].to_s, row[step["to"]]]
        end
        map[value.to_s] || value
      end
    end
  end
end
