# frozen_string_literal: true

require "rb_sys/extensiontask"
require "rb_sys/toolchain_info"

# Load gemspec directly if GEMSPEC constant is not defined
gemspec = defined?(GEMSPEC) ? GEMSPEC : Gem::Specification.load("parsanol.gemspec")

RbSys::ExtensionTask.new("parsanol_native", gemspec) do |ext|
  ext.lib_dir = "lib/parsanol"

  # Vendor the pure-portable cdylib into platform gems (TODO.perf/9).
  # Runs inside the rake process at platform-spec finalization: derive
  # the triple from rb_sys's own platform table, build, and declare the
  # file — rake-compiler stages callback-added files from the tree
  # (define_staging_file_tasks). No workflow env or shell splicing.
  ext.cross_compiling do |spec|
    next if spec.platform == Gem::Platform::RUBY

    plat = spec.platform.to_s
    triple = begin
      RbSys::ToolchainInfo::DATA.fetch(plat).fetch("rust-target")
    rescue KeyError
      { "arm-linux-musl" => "arm-unknown-linux-musleabihf" }.fetch(plat)
    end

    sh "cargo", "build", "--release", "-p", "parsanol_cdylib", "--target", triple
    art = Dir["target/#{triple}/release/libparsanol.{so,dylib,dll}",
              "target/#{triple}/release/parsanol.dll"].first
    raise "cdylib artifact not found for #{plat} (#{triple})" unless art

    # rake-compiler stages callback-added files FROM the project tree —
    # the source file must exist there when the staging task runs.
    cp art, "lib/parsanol/native/"
    spec.files << "lib/parsanol/native/#{File.basename(art)}"
  end
end
