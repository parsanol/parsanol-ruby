# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rdoc/task'
require 'rubygems/package_task'

begin
  require 'opal/rspec/rake_task'
rescue LoadError, NoMethodError
  # Opal not available or incompatible with current Ruby version
end

# Native extension compilation using rake-compiler
begin
  require 'rake/extensiontask'
  Rake::ExtensionTask.new('parsanol_native') do |ext|
    ext.lib_dir = 'lib/parsanol'
  end
rescue LoadError
  # rake-compiler not available
end

desc 'Run all tests'
RSpec::Core::RakeTask.new(:spec)

namespace :spec do
  desc 'Run unit tests only'
  RSpec::Core::RakeTask.new(:unit) do |task|
    task.pattern = 'spec/parsanol/**/*_spec.rb'
  end

  if defined?(Opal::RSpec::RakeTask)
    desc 'Run Opal (JavaScript) tests'
    Opal::RSpec::RakeTask.new(:opal) do |task|
      task.append_path 'lib'
    end
  end
end

RDoc::Task.new do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = 'Parsanol'
  rdoc.options << '--line-numbers'
  rdoc.rdoc_files.include('README.adoc')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

desc 'Print LOC statistics'
task :stat do
  %w[lib spec example].each do |dir|
    next unless Dir.exist?(dir)

    loc = `find #{dir} -name "*.rb" | xargs wc -l | grep 'total'`.split.first.to_i
    printf("%20s %d\n", dir, loc)
  end
end

# ===== Native Gem Building =====
# Platform definitions for precompiled gems
PLATFORMS = [
  %w[x64-mingw32 x86_64-w64-mingw32],
  %w[x64-mingw-ucrt x86_64-w64-mingw32],
  %w[arm64-mingw-ucrt aarch64-w64-mingw32],
  %w[x86_64-linux x86_64-linux-gnu],
  %w[x86_64-linux-gnu x86_64-linux-gnu],
  %w[x86_64-linux-musl x86_64-linux-musl],
  %w[aarch64-linux aarch64-linux-gnu],
  %w[aarch64-linux-gnu aarch64-linux-gnu],
  %w[aarch64-linux-musl aarch64-linux-musl],
  %w[x86_64-darwin x86_64-apple-darwin],
  %w[arm64-darwin arm64-apple-darwin]
].freeze

namespace :gem do
  desc 'Build install-compilation gem (platform: any)'
  task 'native:any' do
    sh 'rake gem:platform:any gem'
  end

  desc 'Define the gem task to build on any platform (compile on install)'
  task 'platform:any' do
    spec = Gem::Specification.load('parsanol-ruby.gemspec').dup
    task = Gem::PackageTask.new(spec)
    task.define
  end

  # Generate tasks for each platform
  PLATFORMS.each do |platform, _host| # rubocop:disable Style/HashEachMethods
    desc "Build pre-compiled gem for the #{platform} platform"
    task "native:#{platform}" do
      sh "rake compile gem:platform:#{platform} gem"
    end

    desc "Define the gem task to build on the #{platform} platform (binary gem)"
    task "platform:#{platform}" do
      spec = Gem::Specification.load('parsanol-ruby.gemspec').dup
      spec.platform = Gem::Platform.new(platform)

      # Include pre-compiled native extension
      spec.files += Dir.glob('lib/parsanol/*.{so,dylib,dll,bundle}')

      # Remove extension build for binary gems (already compiled)
      spec.extensions = []

      # Remove build-time dependencies
      spec.dependencies.reject! { |d| d.name == 'rb_sys' }
      spec.dependencies.reject! { |d| d.name == 'rake-compiler' }

      task = Gem::PackageTask.new(spec)
      task.define
    end
  end

  desc 'Build all platform gems (requires cross-compilation setup)'
  task :native do
    puts 'Building all platform gems...'
    puts 'Run individual tasks like: rake gem:native:x86_64-linux'
    puts 'Or use the CI workflow for cross-compilation.'
  end
end

namespace :benchmark do
  desc 'Run comprehensive benchmark suite'
  task :all do
    ruby 'benchmark/benchmark_suite.rb'
  end

  desc 'Run example-focused benchmarks'
  task :examples do
    ruby 'benchmark/example_benchmarks.rb'
  end

  desc 'Run benchmarks and export results to JSON/YAML'
  task :export do
    ruby 'benchmark/benchmark_runner.rb'
  end

  desc 'Run quick benchmark (examples only)'
  task quick: :examples
end

# Load comparative benchmark tasks
Dir.glob('benchmark/tasks/*.rake').each { |r| load r }

desc 'Run quick benchmarks'
task benchmark: 'benchmark:quick'

# ===== Parslet Compatibility Tests =====
namespace :compat do
  desc 'Run imported Parslet tests with original Parslet (baseline)'
  task :parslet do
    ENV['PARSANOL_BACKEND'] = 'parslet'
    sh 'bundle exec rspec spec/parslet_imported/ --format documentation'
  end

  desc 'Run imported Parslet tests with Parsanol compatibility layer'
  task :parsanol do
    ENV['PARSANOL_BACKEND'] = 'parsanol'
    sh 'bundle exec rspec spec/parslet_imported/ --format documentation'
  end

  desc 'Run both and save results for comparison'
  task :compare do
    require 'fileutils'

    results_dir = 'tmp/compat_results'
    FileUtils.mkdir_p(results_dir)

    puts '=== Running with original Parslet ==='
    ENV['PARSANOL_BACKEND'] = 'parslet'
    sh "bundle exec rspec spec/parslet_imported/ --format documentation > #{results_dir}/parslet.txt 2>&1"

    puts "\n=== Running with Parsanol::Parslet ==="
    ENV['PARSANOL_BACKEND'] = 'parsanol'
    sh "bundle exec rspec spec/parslet_imported/ --format documentation > #{results_dir}/parsanol.txt 2>&1"

    puts "\n=== Comparing results ==="
    puts 'Results saved to:'
    puts "  - #{results_dir}/parslet.txt"
    puts "  - #{results_dir}/parsanol.txt"
    puts "\nTo compare: diff #{results_dir}/parslet.txt #{results_dir}/parsanol.txt"
  end

  desc 'Run imported Parslet tests (default: with Parsanol)'
  task run: :parsanol
end

task default: :spec
