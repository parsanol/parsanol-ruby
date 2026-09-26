# frozen_string_literal: true

module Parsanol
  module PG
    # F6 v1: derive specs — named field-composition templates
    # ("urn:{publisher}:{number}") evaluated against a bound attribute
    # map. {field} interpolates the bound value; missing fields render
    # empty. Byte-identical across engines by construction.
    module Derive
      module_function

      def apply(derive, name, bound)
        template = derive.fetch(name) do
          raise ArtifactError, "derive spec #{name.inspect} not declared"
        end
        evaluate(template, bound)
      end

      def evaluate(template, bound)
        template.gsub(/\{(\w+)\}/) do
          field = Regexp.last_match(1)
          value = bound[field.to_s] || bound[field.to_sym]
          value.nil? ? "" : value.to_s
        end
      end
    end
  end
end
