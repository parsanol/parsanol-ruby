# frozen_string_literal: true

require "json"

module Parsanol
  module PARG
    # Applies an entry's artifact bindings to a parsanol-shape parse tree,
    # producing the attribute hash that fills a lutaml-model class:
    # capture collection -> preprocessing -> type cast -> path assignment.
    module Bindings
      module_function

      def apply(artifact, entry, shape)
        bindings = entry["bindings"] || []
        captures = collect_captures(shape)
        # Snapshot before the assignment pass: reading a missing key off
        # `captures` inserts it (default-proc hash), which would make the
        # #413 lost-check below see phantom presence.
        present = captures.keys
        out = {}
        scalar, arrays = bindings.partition { |binding| !binding["path"].to_s.include?("[]") }
        scalar.each do |binding|
          validate_path!(binding)
          assign_scalar(out, artifact, binding, captures)
        end
        arrays.group_by { |binding| binding["path"].split("[]").first }.each do |prefix, group|
          assign_array(out, artifact, prefix, group, captures, shape)
        end
        # Every declared capture that the tree carries must reach the
        # bound map (parsanol-ruby#413): a capture present in the parse
        # but bound nowhere is silent data loss, the one case the
        # binding layer's other checks miss. Absence in the TREE is
        # legitimate optionality and never raises.
        lost = bindings.select do |binding|
          capture = binding["capture"].to_sym
          present.include?(capture) && !bound?(out, binding)
        end
        unless lost.empty?
          raise BindError,
                "entry #{entry['name'].inspect}: capture #{lost.map { |b| b['capture'].inspect }.join(', ')} " \
                "is present in the parse tree but bound nowhere"
        end
        out
      end

      # Did this binding contribute anything to the bound map? Scalars
      # bind under their leaf key; array groups bind under their prefix.
      def bound?(out, binding)
        path = binding["path"].to_s
        if path.include?("[]")
          prefix = path.split("[]").first.to_sym
          rows = out[prefix]
          rows.is_a?(Array) && rows.any? do |row|
            row.is_a?(Hash) && row.key?(leaf_key(binding))
          end
        else
          out.key?(leaf_key(binding))
        end
      end

      # Canonical test-value form: one equality surface for capture and
      # example expectations on both sides of the comparison (Slice vs
      # source literal was comparing heterogeneous types). Terminals
      # reduce to their text; structure recurses; keys stringify.
      def canonical(value)
        case value
        when Hash then value.to_h { |key, item| [key.to_s, canonical(item)] }
        when Array then value.map { |item| canonical(item) }
        when nil, true, false, Integer then value
        when Float then JSON.generate(value) # B6: the JSON number text
        else String(value)
        end
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

      def assign_array(out, artifact, prefix, group, captures, shape = nil)
        # Position-aware pairing (parsanol-ruby#381): when the shape
        # nests the group's instances under the PREFIX KEY, each
        # instance's subtree owns its captures — pairing by OCCURRENCE
        # index landed a sparse capture (one that fires in only some
        # instances) on the wrong instance. Per-instance collection
        # fixes the pairing and is identical to the old flat pairing
        # when every instance fires every capture.
        #
        # Identification is strictly keyed: the bare top array of a
        # repetition-root entry is NOT claimed as instances
        # (parsanol-ruby#408/#412 — that fallback claimed per-token rule
        # siblings as group instances, splitting paired captures into
        # single-field rows and sprouting phantom rows for unrelated
        # siblings). A capture outside a keyed instance array keeps the
        # legacy occurrence pairing. Phantom rows materialize as {}
        # (the #408 contract: the engines agree by always emitting the
        # row; the contracted phantom representation is {} , never nil).
        instances = shape && group_instances(shape, prefix)
        if instances
          # parsanol-rs#370: a repetition that fired zero iterations
          # binds no key — the recorded native expectations and the
          # pubid builders rely on the absent reading.
          return if instances.empty?

          list = []
          instances.each do |instance|
            found = collect_captures(instance)
            element = {}
            group.each do |binding|
              value = found[binding["capture"].to_sym].first
              next if value.nil?

              element[leaf_key(binding)] = finalize(artifact, binding, value)
            end
            list << element
          end
          out[prefix.to_sym] = list
          return
        end

        count = group.map { |binding| captures[binding["capture"].to_sym].length }.max || 0
        return if count.zero?

        # Field names are symbols everywhere else (scalar bindings, element
        # fields); the array prefix must match or `example` lookups miss it.
        list = (out[prefix.to_sym] ||= [])
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

      # The `prefix[]` group's instance subtrees: the array under a key
      # naming the prefix, walked in collect_captures' BFS order. There
      # is deliberately NO fallback for a repetition-root entry — a bare
      # top array cannot be told apart from per-token rule siblings
      # (#408/#412), so claiming it is magic; those shapes pair by
      # occurrence instead.
      def group_instances(shape, prefix)
        queue = [shape]
        until queue.empty?
          node = queue.shift
          case node
          when Hash
            node.each do |key, value|
              return value if key.to_s == prefix && value.is_a?(Array)

              queue << value if value.is_a?(Hash) || value.is_a?(Array)
            end
          when Array then queue.concat(node)
          end
        end
        nil
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
        when "string"
          # Parsanol::Slice (Ruby atom runtime) and native leaf objects are
          # the shape contract's capture leaves; their to_s is the text.
          scalar = value.nil? || value.is_a?(String) || value.is_a?(Numeric) ||
            value == true || value == false || value.is_a?(Parsanol::Slice)
          unless scalar
            raise ArtifactError,
                  "cannot bind a #{value.class} capture to (string); " \
                  "captures must be scalar"
          end

          value.to_s
        when "boolean" then value == true || value.to_s.casecmp("true").zero?
        when "any"
          # The ONE plain shape on every engine (ruby#383): scalars and
          # capture leaves render as their text, named groups as plain
          # string-keyed hashes, repeats as arrays — so (any)-bound keys
          # survive a cross-engine gate without consumer shims.
          plain(value)
        when "text"
          # The matched span as text (ruby#382): a capture whose body
          # carries inner captures binds a hash of them; (text) returns
          # the span those captures jointly matched while the inner
          # captures still fire as their own bindings.
          span_text(value)
        else value
        end
      end

      # The matched span of a capture value: the byte range from the
      # first to the last slice in the subtree, cut from the input the
      # slices carry. A plain Slice or String is already its span.
      def span_text(value)
        return value.to_s if value.is_a?(Parsanol::Slice) || value.is_a?(String)

        slices = []
        walk = lambda do |node|
          case node
          when Parsanol::Slice then slices << node
          when Hash then node.each_value { |item| Array(item).each(&walk) }
          when Array then node.each(&walk)
          end
        end
        walk.call(value)
        return plain(value) if slices.empty?

        start = slices.map(&:offset).min
        stop = slices.map { |slice| slice.offset + slice.content.bytesize }.max
        input = slices.first.input
        return plain(value) unless input

        span = input.byteslice(start, stop - start)
        span&.force_encoding(Encoding::UTF_8)
      end

      # The engine-neutral reduction behind (any): capture leaves
      # (Parsanol::Slice, native wire objects) and scalars render as
      # their text, hashes as string-keyed plain hashes, arrays
      # recurse. Nil passes through (absent captures stay absent —
      # assign_scalar/assign_array skip them upstream).
      def plain(value)
        case value
        when nil then nil
        when String then value
        when Hash
          value.to_h { |key, item| [key.to_s, plain(item)] }
        when Array then value.map { |item| plain(item) }
        else value.to_s
        end
      end
    end
  end
end
