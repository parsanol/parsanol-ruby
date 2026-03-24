# frozen_string_literal: true

require "bundler/gem_tasks"

begin
  require "rspec/core/rake_task"
rescue LoadError
  # RSpec not available in this environment
end

require "rdoc/task"
require "rubygems/package_task"

begin
  require "opal/rspec/rake_task"
rescue LoadError, NoMethodError
  # Opal not available or incompatible with current Ruby version
end

GEMSPEC = Gem::Specification.load("parsanol.gemspec")

# Load rake tasks from rakelib/
Dir.glob("rakelib/*.rake").each { |r| load r }

desc "Run all tests"
RSpec::Core::RakeTask.new(:spec)

namespace :spec do
  desc "Run unit tests only"
  RSpec::Core::RakeTask.new(:unit) do |task|
    task.pattern = "spec/parsanol/**/*_spec.rb"
  end

  if defined?(Opal::RSpec::RakeTask)
    desc "Run Opal (JavaScript) tests"
    Opal::RSpec::RakeTask.new(:opal) do |task|
      task.append_path "lib"
    end
  end
end

RDoc::Task.new do |rdoc|
  rdoc.rdoc_dir = "rdoc"
  rdoc.title = "Parsanol"
  rdoc.options << "--line-numbers"
  rdoc.rdoc_files.include("README.adoc")
  rdoc.rdoc_files.include("lib/**/*.rb")
end

desc "Print LOC statistics"
task :stat do
  %w[lib spec example].each do |dir|
    next unless Dir.exist?(dir)

    loc = `find #{dir} -name "*.rb" | xargs wc -l | grep 'total'`.split.first.to_i
    printf("%20s %d\n", dir, loc)
  end
end

# ===== Native Gem Building =====
namespace :gem do
  desc "Build source gem (compile on install)"
  task "native:any" do
    sh "rake gem:platform:any gem"
  end

  desc "Define the gem task to build on any platform (compile on install)"
  task "platform:any" do
    spec = Gem::Specification.load("parsanol.gemspec").dup
    task = Gem::PackageTask.new(spec)
    task.define
  end
end

namespace :benchmark do
  desc "Run comprehensive benchmark suite"
  task :all do
    ruby "benchmark/benchmark_suite.rb"
  end

  desc "Run example-focused benchmarks"
  task :examples do
    ruby "benchmark/example_benchmarks.rb"
  end

  desc "Run benchmarks and export results to JSON/YAML"
  task :export do
    ruby "benchmark/benchmark_runner.rb"
  end

  desc "Run quick benchmark (examples only)"
  task quick: :examples
end

# Load comparative benchmark tasks
Dir.glob("benchmark/tasks/*.rake").each { |r| load r }

desc "Run quick benchmarks"
task benchmark: "benchmark:quick"

# ===== Parslet Compatibility Tests =====
namespace :compat do
  desc "Run imported Parslet tests with original Parslet (baseline)"
  task :parslet do
    ENV["PARSANOL_BACKEND"] = "parslet"
    sh "bundle exec rspec spec/parslet_imported/ --format documentation"
  end

  desc "Run imported Parslet tests with Parsanol compatibility layer"
  task :parsanol do
    ENV["PARSANOL_BACKEND"] = "parsanol"
    sh "bundle exec rspec spec/parslet_imported/ --format documentation"
  end

  desc "Run both and save results for comparison"
  task :compare do
    require "fileutils"

    results_dir = "tmp/compat_results"
    FileUtils.mkdir_p(results_dir)

    puts "=== Running with original Parslet ==="
    ENV["PARSANOL_BACKEND"] = "parslet"
    sh "bundle exec rspec spec/parslet_imported/ --format documentation > #{results_dir}/parslet.txt 2>&1"

    puts "\n=== Running with Parsanol::Parslet ==="
    ENV["PARSANOL_BACKEND"] = "parsanol"
    sh "bundle exec rspec spec/parslet_imported/ --format documentation > #{results_dir}/parsanol.txt 2>&1"

    puts "\n=== Comparing results ==="
    puts "Results saved to:"
    puts "  - #{results_dir}/parslet.txt"
    puts "  - #{results_dir}/parsanol.txt"
    puts "\nTo compare: diff #{results_dir}/parslet.txt #{results_dir}/parsanol.txt"
  end

  desc "Run imported Parslet tests (default: with Parsanol)"
  task run: :parsanol
end

task default: :spec
