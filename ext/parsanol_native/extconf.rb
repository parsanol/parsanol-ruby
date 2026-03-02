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
