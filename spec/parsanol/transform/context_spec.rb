# frozen_string_literal: true

require 'spec_helper'

describe Parsanol::Context do
  def context(*args)
    described_class.new(*args)
  end

  it 'binds hash keys as variable like things' do
    context(a: 'value').instance_eval { a }
                       .should == 'value'
  end
  it "one contexts variables aren't the next ones" do
    ca = context(a: 'b')
    cb = context(b: 'c')

    ca.methods.should_not include(:b)
    cb.methods.should_not include(:a)
  end

  describe 'works as a Ruby object should' do
    let(:obj) { context(a: 1) }

    it 'responds_to? :a' do
      expect(obj.respond_to?(:a)).to be_truthy
    end
    it 'includes :a in #methods' do
      expect(obj.methods).to include(:a)
    end
    it 'allows inspection' do
      expect(obj.inspect).to match(/@a=1/)
    end
    it 'allows conversion to string' do
      expect(obj.to_s).to match(/Parsanol::Context:0x/)
    end

    context 'when the context is enhanced' do
      before(:each) do
        class << obj
          def foo
            'foo'
          end
        end
      end

      it 'responds_to correctly' do
        expect(obj.respond_to?(:foo)).to be_truthy
      end
      it 'includes :foo also in methods' do
        expect(obj.methods).to include(:foo)
      end
      it 'allows calling #foo' do
        expect(obj.foo).to eq('foo')
      end
    end
  end
end
