# frozen_string_literal: true

module Parsanol
  module PG
    # Applies an entry's artifact bindings to a parsanol-shape parse tree,
    # producing the attribute hash that fills a lutaml-model class:
    # capture collection -> preprocessing -> type cast -> path assignment.
    module Bindings
      module_function

      def apply(artifact, entry, shape)
        bindings = entry["bindings"] || []
        captures = collect_captures(shape)
        out = {}
        scalar, arrays = bindings.partition { |binding| !binding["path"].to_s.include?("[]") }
        scalar.each do |binding|
          validate_path!(binding)
          assign_scalar(out, artifact, binding, captures)
        end
        arrays.group_by { |binding| binding["path"].split("[]").first }.each do |prefix, group|
          assign_array(out, artifact, prefix, group, captures)
        end
        out
      end

      def collect_captures(shape)
        found = Hash.new { |hash, key| hash[key] = [] }
        queue = [shape]
        until queue.empty?
          node = queue.shift
          case node
          when Hash
            node.each do |key, value|
              found[key.to_sym] << value
              queue << value
            end
          when Array then queue.concat(node)
          end
        end
        found
      end

      def assign_scalar(out, artifact, binding, captures)
        value = captures[binding["capture"].to_sym].first
        return if value.nil?

        out[leaf_key(binding)] = finalize(artifact, binding, value)
      end

      def assign_array(out, artifact, prefix, group, captures)
        count = group.map { |binding| captures[binding["capture"].to_sym].length }.max || 0
        return if count.zero?

        list = (out[prefix] ||= [])
        count.times do |index|
          element = {}
          group.each do |binding|
            value = captures[binding["capture"].to_sym][index]
            next if value.nil?

            element[leaf_key(binding)] = finalize(artifact, binding, value)
          end
          list << element
        end
      end

      def validate_path!(binding)
        path = binding["path"].to_s
        return unless path.include?(".") || path.include?("[")

        raise ArtifactError,
              "binding #{binding['capture'].inspect}: nested path " \
              "#{path.inspect} is not supported; bind the components instead"
      end

      def leaf_key(binding)
        path = binding["path"].to_s
        leaf = path.include?("[]") ? path.split("].").last : path
        leaf.to_sym
      end

      def finalize(artifact, binding, value)
        cast(preprocess(artifact, binding, value), binding["type"])
      end

      def preprocess(artifact, binding, value)
        return value if binding["preprocess"].nil?

        steps = artifact.envelope["preprocess"].fetch(binding["preprocess"]) do
          raise ArtifactError,
                "preprocess step #{binding['preprocess'].inspect} not declared"
        end
        steps.each do |step|
          case step["op"]
          when "table_lookup"
            map = artifact.table_rows(step["table"]).to_h do |row|
              [row[step["from"]].to_s, row[step["to"]]]
            end
            value = map[value.to_s] || value
          else
            raise ArtifactError, "unknown preprocess op #{step['op'].inspect}"
          end
        end
        value
      end

      def cast(value, type)
        case type
        when "integer" then Integer(value)
        when "float" then Float(value)
        when "string" then value.to_s
        when "boolean" then value == true || value.to_s.casecmp("true").zero?
        else value
        end
      end
    end
  end
end
