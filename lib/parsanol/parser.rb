# frozen_string_literal: true

# Base class for constructing PEG parsers. Provides a declarative DSL for
# defining grammar rules and designating the root (entry point) rule.
#
# @example Define a simple parser
#   class NumberParser < Parsanol::Parser
#     rule(:digit) { match('[0-9]') }
#     rule(:number) { digit.repeat(1) }
#     root(:number)
#   end
#
#   NumberParser.new.parse("123")  # => "123"
#
# Parser classes can be embedded within other parsers, enabling grammar
# composition and reuse.
#
# @example Composing parsers
#   class InnerParser < Parsanol::Parser
#     root :inner
#     rule(:inner) { str('x').repeat(3) }
#   end
#
#   class OuterParser < Parsanol::Parser
#     root :outer
#     rule(:outer) { str('a') >> InnerParser.new >> str('a') }
#   end
#
#   OuterParser.new.parse("axxxa")  # => "axxxa"
#
# Inspired by parser combinator and parsing expression grammar patterns.
#
class Parsanol::Parser < Parsanol::Atoms::Base
  include Parsanol

  class << self
    # Declares the root (entry point) rule for this parser.
    # The root is where parsing begins when #parse is called.
    #
    # @param rule_name [Symbol] name of the rule to use as root
    #
    # @example
    #   class MyParser < Parsanol::Parser
    #     rule(:document) { ... }
    #     root(:document)  # parsing starts here
    #   end
    #
    def root(rule_name)
      # Remove any existing root method before redefining
      undef_method :root if method_defined?(:root)
      define_method(:root) { __send__(rule_name) }
    end
  end

  # Delegates matching to the root rule.
  #
  # @param src [Parsanol::Source] input source
  # @param ctx [Parsanol::Atoms::Context] parsing context
  # @param should_consume_all [Boolean] require complete consumption
  # @return [Array(Boolean, Object)] parse result
  #
  def try(src, ctx, should_consume_all)
    root.try(src, ctx, should_consume_all)
  end

  # Formats this parser for display (delegates to root rule).
  #
  # @param prec [Integer] precedence level
  # @return [String] formatted representation
  #
  def to_s_inner(prec)
    root.to_s(prec)
  end

  # Entry point for visitor traversal from parser root.
  #
  # @param visitor [Object] visitor object
  def accept(visitor)
    visitor.visit_parser(root)
  end

  # Unified parsing interface with mode selection support.
  #
  # @param input [String] the string to parse
  # @param mode_or_opts [Symbol, Hash] parsing mode or options hash
  # @param kwargs [Hash] additional keyword options
  #
  # Modes:
  # - :ruby - Pure Ruby parsing (default, always available)
  # - :native - Use Rust extension if available, fallback to Ruby
  # - :json - Return JSON string representation of parse tree
  #
  # Options:
  # - :reporter - Custom error reporter instance
  # - :prefix - Allow partial matching (default: false)
  #
  # @return [Hash, Array, String, Parsanol::Slice] parsed result
  # @raise [Parsanol::ParseFailed] when parsing fails
  #
  def parse(input, mode_or_opts = {}, **kwargs)
    if mode_or_opts.is_a?(Hash)
      # Legacy API: parse(input, options={})
      merged = mode_or_opts.merge(kwargs)
      super(input, merged)
    else
      # New API: parse(input, mode:, **options)
      dispatch_parse(mode_or_opts, input, kwargs)
    end
  end

  # Parses multiple inputs in batch mode.
  #
  # @param inputs [Array<String>] strings to parse
  # @param mode [Symbol] parsing mode (:ruby, :native, or :json)
  # @param opts [Hash] additional options
  # @return [Array] array of parse results
  #
  def parse_batch(inputs, mode: :ruby, **opts)
    inputs.map { |str| parse(str, mode: mode, **opts) }
  end

  private

  # Dispatches to the appropriate parsing backend based on mode.
  #
  # @param mode [Symbol] the parsing mode
  # @param input [String] input to parse
  # @param opts [Hash] parsing options
  # @return [Object] parse result
  #
  def dispatch_parse(mode, input, opts)
    case mode
    when :ruby
      parse_ruby(input, opts)
    when :native
      parse_native(input, opts)
    when :json
      parse_json(input, opts)
    else
      raise ArgumentError, "Unknown mode: #{mode}. Valid modes: :ruby, :native, :json"
    end
  end

  # Pure Ruby parsing (delegates to Base implementation).
  #
  # @param input [String] input to parse
  # @param opts [Hash] parsing options
  # @return [Object] parse result
  #
  def parse_ruby(input, opts)
    super(input, opts)
  end

  # Native extension parsing with Ruby fallback.
  #
  # @param input [String] input to parse
  # @param opts [Hash] parsing options
  # @return [Object] parse result
  #
  def parse_native(input, opts)
    if Parsanol::Native.available?
      Parsanol::Native.parse_parslet_compatible(root, input)
    else
      parse_ruby(input, opts)
    end
  end

  # JSON output mode - returns JSON string representation.
  #
  # @param input [String] input to parse
  # @param opts [Hash] parsing options
  # @return [String] JSON representation of parse tree
  #
  def parse_json(input, opts)
    if Parsanol::Native.available?
      grammar_def = Parsanol::Native.serialize_grammar(root)
      outcome = Parsanol::Native.parse(grammar_def, input)
      outcome.to_json
    else
      parse_ruby(input, opts).to_json
    end
  end
end
