# frozen_string_literal: true

module Parsanol
  module PARG
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

      # A single closed mapping entry (a multi-entry source line emits
      # sequential steps); unmapped values pass through, mirroring
      # table_lookup.
      register :const_map do |step, value, _source|
        mapped = step["to"] if step["from"] == value.to_s
        mapped || value
      end

      # Fill absent data. Scalar nils never reach the pipeline (the
      # null-capture contract skips the binding upstream), so the
      # meaningful path is a hash-shaped capture value with nil
      # members: fill those in place (order kept).
      register :default_when_absent do |step, value, _source|
        if value.is_a?(Hash)
          if value.value?(nil)
            value.transform_values { |member| member.nil? ? step["to"] : member }
          else
            value
          end
        elsif value.nil?
          step["to"]
        else
          value
        end
      end

      # Capture-name alignment on a hash-shaped value; non-hash values
      # pass through unchanged. The renamed key keeps its position and
      # its convention (Symbol keys stay Symbol, String stay String —
      # the live tier builds Symbol-keyed capture hashes, the wire
      # String), matching the rs executor's in-place rebuild.
      register :rename do |step, value, _source|
        if value.is_a?(Hash)
          from = step["from"]
          matched = value.key?(from) || value.key?(from.to_sym)
          if matched
            value.transform_keys do |key|
              next key unless key.to_s == from

              key.is_a?(Symbol) ? step["to"].to_sym : step["to"]
            end
          else
            value
          end
        else
          value
        end
      end
    end
  end
end
