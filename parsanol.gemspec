# frozen_string_literal: true

require_relative "lib/parsanol/version"

Gem::Specification.new do |spec|
  spec.name = "parsanol"
  spec.version = Parsanol::VERSION
  spec.platform = Gem::Platform::RUBY

  spec.authors = ["Ribose Inc."]
  spec.email = ["open.source@ribose.com"]

  spec.summary = "Parser construction library with great error reporting in Ruby."
  spec.description = "A small Ruby library for constructing parsers in the PEG (Parsing Expression Grammar) fashion. " \
                     "Parsanol provides Parslet-compatible API with additional features including " \
                     "static frozen parsers and dynamic parsers, with optional Rust native extension for improved performance."
  spec.homepage = "https://github.com/parsanol/parsanol-ruby"
  spec.license = "MIT"

  spec.metadata = {
    "bug_tracker_uri" => "https://github.com/parsanol/parsanol-ruby/issues",
    "changelog_uri" => "https://github.com/parsanol/parsanol-ruby/blob/main/HISTORY.txt",
    "documentation_uri" => "https://parsanol.github.io/parsanol-ruby/",
    "homepage_uri" => "https://github.com/parsanol/parsanol-ruby",
    "source_code_uri" => "https://github.com/parsanol/parsanol-ruby",
    "rubygems_mfa_required" => "true",
  }

  # Rust extension
  spec.extensions = ["ext/parsanol_native/extconf.rb"]

  spec.files = Dir.glob("{lib,ext}/**/*") + %w[
    HISTORY.txt
    LICENSE
    Rakefile
    README.adoc
    parsanol.gemspec
    Cargo.toml
    Cargo.lock
  ]
  spec.files.reject! { |f| File.directory?(f) }
  # Cargo build trees are never gem content (a dirty local
  # ext/parsanol_native/target once inflated a build to 218 MB).
  spec.files.reject! { |f| f.include?("/target/") || f.start_with?("target/") }
  # Binaries are never tracked in git, and the ruby (source) gem stays
  # slim: the pure-portable cdylib is vendored ONLY into platform gems
  # by the cross-gem build (rake gem:vendor_cdylib), never by a plain
  # `gem build`.
  spec.files.reject! do |f|
    f =~ /\.(dll|so|dylib|lib|bundle)\Z/ &&
      !(ENV["PARSANOL_VENDOR_CDYLIB"] == "1" && f.start_with?("lib/parsanol/native/"))
  end
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 3.2.0"

  # Required for Rust extension
  spec.add_dependency "rb_sys", "~> 0.9.39"
end
