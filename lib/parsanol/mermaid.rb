# frozen_string_literal: true

# Generates Mermaid diagram visualizations of parser grammars.
# Mermaid is widely supported by GitHub, GitLab, Notion, and many other tools.
#
# @example Generate Mermaid diagram
#   parser = MyParser.new
#   puts parser.to_mermaid
#
# @example Generate diagram for specific rule
#   puts parser.mermaid_for_rule(:expression)
#
# Inspired by Parslet (MIT License).

module Parsanol
  # Generates Mermaid diagram syntax from parser atoms.
  class MermaidBuilder
    def initialize
      @lines = ['graph TD']
      @node_counter = 0
      @connections = []
      @seen_rules = Set.new
    end

    # Entry point for parser visualization
    def visit_parser(root_atom)
      add_node('Parser', 'root')
      traverse(root_atom, 'Parser')
      finalize
    end

    # Handles named rules
    def visit_entity(rule_name, rule_block)
      return if @seen_rules.include?(rule_name)

      @seen_rules << rule_name

      node_id = add_node(rule_name.to_s.upcase, 'rule')
      connect(current_parent, node_id)
      traverse(rule_block.call, node_id)
    end

    # Pass through named captures
    def visit_named(label, atom)
      traverse(atom, current_parent)
    end

    # Pass through repetition
    def visit_repetition(tag, min, max, atom)
      traverse(atom, current_parent)
    end

    # Process alternatives
    def visit_alternative(alternatives)
      alternatives.each { |alt| traverse(alt, current_parent) }
    end

    # Process sequence
    def visit_sequence(members)
      members.each { |member| traverse(member, current_parent) }
    end

    # Pass through lookahead
    def visit_lookahead(positive, atom)
      traverse(atom, current_parent)
    end

    # Leaf nodes
    def visit_re(regexp)
      add_node("match(#{regexp.inspect})", 'terminal', style: 'ellipse')
    end

    def visit_str(string)
      add_node("'#{string}'", 'terminal', style: 'ellipse')
    end

    private

    attr_reader :current_parent

    def add_node(label, shape_type = 'rect', style = nil)
      @node_counter += 1
      node_id = "node_#{@node_counter}"
      @lines << "    #{node_id}[\"#{escape_mermaid(label)}\"]"
      node_id
    end

    def connect(from_id, to_id)
      @connections << [from_id, to_id]
    end

    def escape_mermaid(text)
      text.gsub('"', "'").gsub('\n', '\\n')
    end

    def finalize
      @connections.each do |from, to|
        @lines << "    #{from} --> #{to}"
      end
      @lines << ''
      @lines.join("\n")
    end

    def traverse(atom, parent)
      @current_parent = parent
      atom.accept(self)
    end
  end

  # Mixin module that adds Mermaid diagram generation to parsers
  module MermaidDiagram
    # Generates a Mermaid diagram of the parser.
    #
    # @return [String] Mermaid diagram source
    def to_mermaid
      builder = MermaidBuilder.new
      new.accept(builder)
      builder.output
    end

    # Generates Mermaid diagram for a specific rule.
    #
    # @param rule_name [Symbol] name of the rule
    # @return [String] Mermaid diagram source
    def mermaid_for_rule(rule_name)
      builder = MermaidBuilder.new
      rule_method = method(rule_name)
      raise NotImplementedError, "Rule '#{rule_name}' not found" unless rule_method
      rule_method.call.accept(builder)
      builder.output
    end
  end

  # Extend Parser with Mermaid diagram generation
  class Parser
    extend MermaidDiagram
  end
end
