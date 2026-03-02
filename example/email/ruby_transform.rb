# frozen_string_literal: true

# Email Parser Example - RubyTransform
#
# This example demonstrates parsing email addresses with validation.
# Shows character classes, repetition, and structured output.
#
# Run with: ruby -Ilib example/email_ruby_transform.rb

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

require 'parsanol'

# Step 1: Define the email grammar
class EmailParser < Parsanol::Parser
  root :email

  rule(:email) do
    local_part.as(:local) >>
      str('@') >>
      domain.as(:domain)
  end

  rule(:local_part) do
    (alphanumeric | match('[._%+-]')).repeat(1)
  end

  rule(:domain) do
    label >> (str('.') >> label).repeat
  end

  rule(:label) do
    alphanumeric.repeat(1)
  end

  rule(:alphanumeric) { match('[a-zA-Z0-9]') }
end

# Step 2: Email address class
class EmailAddress
  attr_reader :local, :domain

  def initialize(local, domain)
    @local = local.to_s
    @domain = domain.to_s
  end

  def to_s
    "#{@local}@#{@domain}"
  end

  def eql?(other)
    other.is_a?(EmailAddress) && to_s == other.to_s
  end

  alias == eql?

  def hash
    to_s.hash
  end
end

def parse_email(input)
  parser = EmailParser.new
  tree = parser.parse(input)

  puts "Parse tree: #{tree.inspect}"

  # Extract local and domain from tree
  local = tree[:local].to_s
  domain = tree[:domain].to_s

  EmailAddress.new(local, domain)
rescue Parsanol::ParseFailed => e
  puts "Parse failed: #{e.message}"
  nil
end

# Example usage
if __FILE__ == $PROGRAM_NAME
  puts '=' * 60
  puts 'Email Parser - RubyTransform'
  puts '=' * 60
  puts

  test_emails = [
    'user@example.com',
    'john.doe@example.org',
    'test123@subdomain.example.co.uk',
    'invalid-email',
    '@missing-local.com',
    'no-at-sign.com'
  ]

  test_emails.each do |email_str|
    puts '-' * 40
    puts "Input: #{email_str}"
    email = parse_email(email_str)
    if email
      puts "  Email: #{email}"
      puts "  Local: #{email.local}"
      puts "  Domain: #{email.domain}"
    end
    puts
  end
end
