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
module Parsanol
  class Parser < Parsanol::Atoms::Base
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
    # All parse modes return results with Slice objects that contain
    # position information (offset, length, line, column). This enables
    # source code extraction, error reporting, and remark attachment.
    #
    # @param input [String] the string to parse
    # @param mode_or_opts [Symbol, Hash] parsing mode or options hash
    # @param kwargs [Hash] additional keyword options
    #
    # Modes:
    # - :ruby - Pure Ruby parsing (always available, returns Slices with position)
    # - :native - Use Rust extension if available, fallback to Ruby
    # - :json - Return JSON string with position info for each value
    #
    # Options:
    # - :reporter - Custom error reporter instance
    # - :prefix - Allow partial matching (default: false)
    #
    # @return [Hash, Array, Parsanol::Slice] parsed result with position info
    # @raise [Parsanol::ParseFailed] when parsing fails
    #
    # @example Parse and access position info
    #   result = parser.parse("hello")
    #   result[:name].offset         # => 0
    #   result[:name].line_and_column # => [1, 1]
    #   result[:name].to_s           # => "hello"
    #
    def parse(input, mode_or_opts = {}, **kwargs)
      if mode_or_opts.is_a?(Hash) && !kwargs.key?(:mode)
        # Legacy API: parse(input, options={})
        merged = mode_or_opts.merge(kwargs)
        super(input, merged)
      else
        # New API: parse(input, mode:, **options)
        mode = kwargs.delete(:mode) || :ruby
        case mode
        when :ruby
          super(input, kwargs)
        when :native
          parse_native(input, kwargs)
        when :json
          parse_json(input, kwargs)
        else
          raise ArgumentError,
                "Unknown mode: #{mode}. Valid modes: :ruby, :native, :json"
        end
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

    # Clear the Rust grammar cache to free memory.
    #
    # @return [nil]
    # @raise [LoadError] if native parser is not available
    def clear_grammar_cache
      Parsanol::Native.clear_grammar_cache
    end

    # Get the current number of cached grammars in Rust.
    #
    # @return [Integer] number of cached grammars
    # @raise [LoadError] if native parser is not available
    def grammar_cache_size
      Parsanol::Native.grammar_cache_size
    end

    # Get the grammar cache capacity.
    #
    # @return [Integer] maximum cache capacity
    # @raise [LoadError] if native parser is not available
    def grammar_cache_capacity
      Parsanol::Native.grammar_cache_capacity
    end

    # Get cache statistics for both Ruby and Rust caches.
    #
    # @return [Hash] cache statistics including Ruby GRAMMAR_CACHE and Rust grammar cache
    # @raise [LoadError] if native parser is not available for Rust stats
    def cache_stats
      Parsanol::Native.cache_stats
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
        # Call base class parse directly (send needed since parse is defined in parent)
        Parsanol::Atoms::Base.instance_method(:parse).bind_call(self, input,
                                                                opts)
      when :native
        parse_native(input, opts)
      when :json
        parse_json(input, opts)
      else
        raise ArgumentError,
              "Unknown mode: #{mode}. Valid modes: :ruby, :native, :json"
      end
    end

    # Native extension parsing with Ruby fallback.
    # Returns results with Slice objects containing position info.
    #
    # @param input [String] input to parse
    # @param opts [Hash] parsing options
    # @return [Object] parse result with Slice objects for position info
    #
    def parse_native(input, opts)
      if Parsanol::Native.available?
        Parsanol::Native.parse(root, input)
      else
        super
      end
    end

    # JSON output mode - returns JSON with position info.
    # All Slice values are serialized with their position information.
    #
    # @param input [String] input to parse
    # @param opts [Hash] parsing options
    # @return [String] JSON representation with position info
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
end
