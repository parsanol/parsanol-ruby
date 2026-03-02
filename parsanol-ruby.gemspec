# frozen_string_literal: true

require_relative 'lib/parsanol/version'

Gem::Specification.new do |spec|
  spec.name = 'parsanol'
  spec.version = Parsanol::VERSION
  spec.platform = Gem::Platform::RUBY

  spec.authors = ['Ribose Inc.']
  spec.email = ['open.source@ribose.com']

  spec.summary = 'Parser construction library with great error reporting in Ruby.'
  spec.description = 'A small Ruby library for constructing parsers in the PEG (Parsing Expression Grammar) fashion. ' \
                     'Parsanol provides Parslet-compatible API with additional features including ' \
                     'static frozen parsers and dynamic parsers, with optional Rust native extension for improved performance.'
  spec.homepage = 'https://github.com/parsanol/parsanol-ruby'
  spec.license = 'MIT'

  spec.metadata = {
    'bug_tracker_uri' => 'https://github.com/parsanol/parsanol-ruby/issues',
    'changelog_uri' => 'https://github.com/parsanol/parsanol-ruby/blob/main/HISTORY.txt',
    'documentation_uri' => 'https://parsanol.github.io/parsanol-ruby/',
    'homepage_uri' => 'https://github.com/parsanol/parsanol-ruby',
    'source_code_uri' => 'https://github.com/parsanol/parsanol-ruby',
    'rubygems_mfa_required' => 'true'
  }

  # Rust extension
  spec.extensions = ['ext/parsanol_native/extconf.rb']

  spec.files = Dir.glob('{lib,spec,example}/**/*') + %w[
    HISTORY.txt
    LICENSE
    Rakefile
    README.adoc
    parsanol-ruby.gemspec
  ]
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 3.2.0'

  # Required for Rust extension
  spec.add_dependency 'rb_sys', '~> 0.9.39'

  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rake-compiler', '~> 1.2.0'
  spec.add_development_dependency 'rdoc', '~> 6.0'
  spec.add_development_dependency 'rspec', '~> 3.0'

  # For code style checking
  spec.add_development_dependency 'rubocop', '~> 1.0'

  # For Parslet compatibility verification
  spec.add_development_dependency 'parslet', '~> 2.0.0'

  # For benchmarking
  spec.add_development_dependency 'benchmark-ips', '~> 2.0'

  # For type checking
  spec.add_development_dependency 'rbs', '~> 3.0'
  spec.add_development_dependency 'steep', '~> 1.0'
end
