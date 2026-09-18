# frozen_string_literal: true

require "mkmf"

# The Rust extension only builds against MRI's C API. Other engines
# (TruffleRuby, JRuby) resolve the ruby-platform gem and must install
# cleanly on the pure-Ruby backend instead of failing the whole install
# (parsanol-ruby#23). An explicit opt-out works on MRI too.
if RUBY_ENGINE != "ruby" || ENV["PARSANOL_NATIVE"] == "0"
  File.write("Makefile", dummy_makefile("").to_s)
  warn "parsanol: skipping the Rust extension on #{RUBY_ENGINE} " \
       "(pure-Ruby backend will be used)"
  exit 0
end

require "rb_sys/mkmf"

create_rust_makefile("parsanol/parsanol_native") do |r|
  # Create debug builds in dev, release in production
  r.profile = ENV.fetch("RB_SYS_CARGO_PROFILE", :dev).to_sym

  # Enable stable API compiled fallback for ruby-head and older Ruby versions
  r.use_stable_api_compiled_fallback = true

  # Force install rust toolchain if needed (can also set RB_SYS_FORCE_INSTALL_RUST_TOOLCHAIN=true)
  r.force_install_rust_toolchain = false
end
