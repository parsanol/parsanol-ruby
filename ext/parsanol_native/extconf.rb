# frozen_string_literal: true

# The Rust extension targets the CRuby C API through rb_sys/magnus. On
# engines whose C-extension story cannot build it (TruffleRuby compiles C
# extensions through Sulong and cannot load magnus-produced cdylibs; JRuby
# has no C-extension support), or when the pure-Ruby backend is requested
# explicitly, emit a no-op Makefile so the ruby-platform gem installs
# cleanly. Parsanol::Native already falls back to the pure-Ruby parser at
# runtime (lib/parsanol/native.rb rescues LoadError), so skipping the
# build here is sufficient — see
# https://github.com/parsanol/parsanol-ruby/issues/23
if ENV["PARSANOL_PURE_RUBY"] == "1" ||
    %w[truffleruby jruby].include?(RUBY_ENGINE)
  File.write("Makefile", <<~MAKEFILE)
    all:
    install:
    clean:
  MAKEFILE
  return
end

require "mkmf"
require "rb_sys/mkmf"

create_rust_makefile("parsanol/parsanol_native") do |r|
  # Create debug builds in dev, release in production
  r.profile = ENV.fetch("RB_SYS_CARGO_PROFILE", :dev).to_sym

  # Enable stable API compiled fallback for ruby-head and older Ruby versions
  r.use_stable_api_compiled_fallback = true

  # Force install rust toolchain if needed (can also set RB_SYS_FORCE_INSTALL_RUST_TOOLCHAIN=true)
  r.force_install_rust_toolchain = false
end
