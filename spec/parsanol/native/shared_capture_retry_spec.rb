# frozen_string_literal: true

require "spec_helper"

class SharedCaptureRetryParser < Parsanol::Parser
  rule(:name) { match["a-z"].repeat(1) }
  rule(:opening) { str("<") >> name.capture(:tag) >> str(">") }

  def wrapped(content)
    scope do
      opening >> str(content) >> dynamic do |_source, context|
        str("</#{context.captures[:tag]}>")
      end
    end
  end

  rule(:document) { wrapped("q") | wrapped("x") }
  root :document
end

RSpec.describe "shared captures after a branch retry", :native do
  tags = %w[i div]

  %i[ruby native].each do |mode|
    context "in #{mode} mode" do
      before do
        skip "native backend unavailable" if mode == :native && !Parsanol::Native.available?
      end

      tags.each do |tag|
        it "reapplies the shared opening capture for #{tag}" do
          input = "<#{tag}>x</#{tag}>"

          expect(SharedCaptureRetryParser.new.parse(input, mode: mode).to_s).to eq(input)
        end
      end

      it "still rejects a different closing tag" do
        expect { SharedCaptureRetryParser.new.parse("<i>x</b>", mode: mode) }
          .to raise_error(Parsanol::ParseFailed)
      end
    end
  end
end
