# frozen_string_literal: true

module Parsanol
  module Native
    # Rust engine for runtimes that cannot load C-API extensions
    # (JRuby, TruffleRuby, or an MRI whose platform gem is absent and
    # cannot build one). Binds the parsanol cdylib's C ABI through the
    # `ffi` gem: grammars register once into Rust-side handles keyed by
    # serialized structure; results cross the boundary as flat-u64 batch
    # arrays decoded by the same BatchDecoder used elsewhere.
    module Ffi
      class Error < StandardError
      end

      class << self
        @available = nil

        def available?
          return @available unless @available.nil?

          @available = begin
            require "ffi"
            lib = locate_library
            lib && bind_library(lib)
          rescue LoadError, StandardError
            false
          end
        end

        # Registers (once, cached) and parses. +grammar+ is a grammar
        # atom or a pre-serialized JSON string. Mirrors Native.parse's
        # contract, including the single reporter-pass fallback to the
        # pure-Ruby engine for parslet-compatible failure errors.
        def parse(grammar, input)
          unless available? && @binding
            raise Error, "parsanol FFI library not available"
          end

          if grammar.is_a?(String)
            json = grammar
            atom = nil
          else
            json = ::Parsanol::Native::Parser.serialize_grammar(grammar)
            atom = grammar
          end
          handle = ((@handles ||= {})[json] ||= @binding.c_register(json))
          raise Error, "grammar registration failed" if handle.zero?

          written = parse_into(handle, input)
          if written.positive?
            return ::Parsanol::Native::BatchDecoder.decode_and_flatten(
              @buffer.read_array_of_uint64(written), input, ::Parsanol::Slice
            )
          end

          message = @binding.c_last_error.to_s
          if atom
            return ::Parsanol::Native.raise_native_parse_error(
              RuntimeError.new(message), atom, input
            )
          end

          raise Error, "parse failed: #{message}"
        end

        private

        # Search order: explicit override, gem-vendored cdylib next to
        # this file, then the system linker path.
        def locate_library
          candidates = []
          env = ENV.fetch("PARSANOL_FFI_LIB", nil)
          candidates << env if env && !env.empty?
          here = File.dirname(__FILE__)
          %w[libparsanol.dylib libparsanol.so parsanol.dll].each do |name|
            path = File.expand_path(name, here)
            candidates << path if File.file?(path)
          end
          candidates << "parsanol"
          candidates.each do |cand|
            return cand if File.file?(cand)

            begin
              FFI::DynamicLibrary.open(cand, FFI::DynamicLibrary::RTLD_NOW)
              return cand
            rescue StandardError
              next
            end
          end
          nil
        end

        def bind_library(path) # rubocop:disable Naming/PredicateMethod -- binds and reports success
          binding_mod = Module.new do
            extend FFI::Library

            ffi_lib path
            attach_function :c_register, :parsanol_c_register,
                            %i[string], :uint64
            attach_function :c_parse, :parsanol_c_parse,
                            %i[uint64 string pointer size_t], :long_long
            attach_function :c_last_error, :parsanol_c_last_error,
                            [], :string
            attach_function :c_release, :parsanol_c_release,
                            %i[uint64], :void
          end
          # Probe the symbols now so a mismatched library fails loudly
          # at availability time, not at first parse.
          probe = binding_mod.c_last_error
          @binding = binding_mod
          @buffer = nil
          !probe.nil? || true
        end

        # Two-call buffer protocol: cap=0 asks for the needed size, then
        # one allocation carries the whole batch.
        def parse_into(handle, input)
          needed = @binding.c_parse(handle, input, nil, 0)
          return needed unless needed.negative?

          @buffer = FFI::MemoryPointer.new(:uint64, -needed)
          @binding.c_parse(handle, input, @buffer, -needed)
        end
      end
    end
  end
end
