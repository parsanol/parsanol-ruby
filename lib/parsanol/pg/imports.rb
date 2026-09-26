# frozen_string_literal: true

module Parsanol
  module PG
    # Cross-file imports (PN 1): `use <name>` at the top of a .pg file
    # loads <name>.pg from an import directory, prefixes every rule with
    # "<name>." (capture names are preserved — embedded grammars keep
    # their capture contract), and merges entries, bindings, preprocess
    # steps, tests, and docs. Cycles and missing files are compile
    # errors. The artifact bakes the expansion: consumers never see
    # imports.
    module Imports
      module_function

      def merge!(document, import_dirs, merging = [])
        return document if document.uses.empty?

        document.uses.each do |name|
          raise CompileError, "import cycle: #{(merging + [name]).join(' -> ')}" if merging.include?(name)

          source = find_file(name, import_dirs)
          used = Parser.new(File.read(source)).parse
          merge!(used, import_dirs, merging + [name])
          merge_used(document, used, "#{name}.")
        end
        document.uses = []
        document
      end

      def find_file(name, import_dirs)
        dirs = Array(import_dirs)
        raise CompileError, "no import directories configured for `use #{name}`" if dirs.empty?

        path = dirs.flat_map { |dir| %w[.yaml .pg .json].map { |ext| File.join(dir, "#{name}#{ext}") } }
          .select { |candidate| candidate.end_with?(".pg") }
          .find { |candidate| File.file?(candidate) }
        path || raise(CompileError, "import `use #{name}` not found in #{dirs.inspect}")
      end

      def merge_used(document, used, prefix)
        used.rules.each do |name, node|
          qualified = "#{prefix}#{name}"
          raise CompileError, "imported rule #{qualified.inspect} collides" if document.rules.key?(qualified)

          document.rules[qualified] = copy(node, prefix)
        end
        used.entries.each do |entry, rule|
          document.entries["#{prefix}#{entry}"] = "#{prefix}#{rule}"
        end
        used.bindings.each do |rule, list|
          document.bindings["#{prefix}#{rule}"] = list
        end
        used.preprocess.each do |name, steps|
          document.preprocess["#{prefix}#{name}"] = steps
        end
        used.docs.each do |rule, text|
          document.docs["#{prefix}#{rule}"] = text
        end
        default_used_entry = used.entries.size == 1 ? used.entries.keys.first : nil
        used.tests.each do |test|
          entry = test.entry || default_used_entry
          document.tests << Document::Test.new(
            entry ? "#{prefix}#{entry}" : test.entry,
            test.kind, test.input, test.expect
          )
        end
      end

      def copy(node, prefix)
        return node unless node.is_a?(Node)

        case node.kind
        when :seq then Node.new(:seq, node.a.map { |child| copy(child, prefix) })
        when :alt then Node.new(:alt, node.a.map { |child| copy(child, prefix) })
        when :rep then Node.new(:rep, copy(node.a, prefix), node.b, node.c)
        when :opt then Node.new(:opt, copy(node.a, prefix))
        when :pred then Node.new(:pred, node.a, copy(node.b, prefix))
        when :cap then Node.new(:cap, node.a, copy(node.b, prefix))
        when :ref then Node.new(:ref, "#{prefix}#{node.a}")
        else node
        end
      end
    end
  end
end
