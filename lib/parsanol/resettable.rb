# frozen_string_literal: true

module Parsanol
  # Module for objects that can be reset for object pool reuse.
  #
  # Including this module signals that an object supports the reset!
  # method for pooling purposes. This provides an explicit contract
  # instead of duck-typing with respond_to?.
  #
  # @example
  #   class MyPooledObject
  #     include Parsanol::Resettable
  #
  #     def reset!
  #       @state = nil
  #       self
  #     end
  #   end
  #
  module Resettable
    # Reset object state for reuse in object pool.
    #
    # @return [self] for method chaining
    # @raise [NotImplementedError] if not implemented by including class
    def reset!
      raise NotImplementedError, "#{self.class} must implement #reset!"
    end
  end
end
