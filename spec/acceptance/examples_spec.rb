# frozen_string_literal: true

require "spec_helper"
require "open3"

# Strip positions from the output, so that we can compare it with the expected output.
# (Some other specs utilize the inspect of inner objects outside example/*.rb expections)
# The behavior of comparison of #inspect as done in parselet behaves differently
# in Opal and MRI.

describe "Regression on" do
  Dir["example/*.rb"].each do |example|
    context example do
      # Generates a product path for a given example file.
      def product_path(str, ext)
        str
          .gsub(".rb", ".#{ext}")
          .gsub("example/", "example/output/")
      end

      it "runs successfully" do
        # Skip if output files don't exist (new examples may not have expected outputs yet)
        skip "No output file found for #{example}" unless Dir["example/output/#{File.basename(
          example, '.rb'
        )}.*"].any?

        # Skip examples that have missing dependencies
        skip_missing_deps = %w[
          example/optimized_erb.rb
        ]
        skip "Missing dependencies" if skip_missing_deps.include?(example)

        if RUBY_ENGINE == "opal"

          skip_examples = %w[
            example/calc.rb
            example/empty.rb
            example/erb.rb
            example/ip_address.rb
            example/mathn.rb
            example/nested_errors.rb
            example/optimized_erb.rb
            example/prec_calc.rb
          ]
          skip "Opal does not support #{example} yet" if skip_examples.include?(example)

          begin
            system("opal -srubygems -ropal-parser -rnodejs -Ilib -I. #{example} >_stdout 2>_stderr")

            handle_map = {
              "_stdout" => :out,
              "_stderr" => :err,
            }
            expectation_found = handle_map.any? do |io, ext|
              name = product_path(example, ext)

              if File.exist?(name)
                actual_output = File.read(io).strip
                expected_output = File.read(name).strip.gsub(/:(\w+)(=>|,|\]|\})/, '"\1"\2').gsub("1.0e+23", "1e+23").gsub(
                  /@\d+/, ""
                ).strip
                expect(strip_positions(actual_output)).to eq(strip_positions(expected_output))
                true
              end
            end
          ensure
            File.unlink("_stdout")
            File.unlink("_stderr")
          end
        else
          _, stdout, stderr = Open3.popen3("ruby #{example}")

          handle_map = {
            stdout => :out,
            stderr => :err,
          }
          expectation_found = handle_map.any? do |io, ext|
            name = product_path(example, ext)

            if File.exist?(name)
              actual_output = io.read.strip
              expected_output = File.read(name).strip
              expect(actual_output).to eq(expected_output)
              true
            end
          end
        end

        unless expectation_found
          raise "Example doesn't have either an .err or an .out file. " \
                "Please create in examples/output!"
        end
      end
    end
  end
end
