# frozen_string_literal: true

module Parsanol
  module PG
    # F6 v1: generic renderer over the artifact's render spec — ordered
    # segments (field / literal / cond-presence) evaluated against a bound
    # attribute map. The spec lives under the artifact checksum, so every
    # engine renders byte-identical strings by construction.
    module Render
      module_function

      def apply(render, variant, bound)
        segments = render.fetch(variant) do
          raise ArtifactError, "render variant #{variant.inspect} not declared"
        end
        render_segments(segments, bound)
      end

      def render_segments(segments, bound)
        segments.filter_map { |segment| render_segment(segment, bound) }.join
      end

      # Bindings produces symbol keys in-process; the JSON contract (and
      # the other engines) use strings — accept both.
      def lookup(bound, field)
        bound[field.to_s] || bound[field.to_sym]
      end

      def render_segment(segment, bound)
        case segment["type"]
        when "field" then lookup(bound, segment["field"]).to_s
        when "literal" then segment["text"].to_s
        when "cond"
          value = lookup(bound, segment["field"])
          return "" if value.nil?

          render_segments(segment["then"], bound)
        else
          raise ArtifactError, "unknown render segment #{segment['type'].inspect}"
        end
      end
    end
  end
end
