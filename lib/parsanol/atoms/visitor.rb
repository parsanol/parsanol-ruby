# frozen_string_literal: true

# Visitor pattern for traversing parser atom trees.
# Each atom type dispatches to a corresponding visitor method.
module Parsanol
  module Atoms
    class Base
      # Accepts visitor and dispatches to type-specific method.
      # Override in subclasses.
      #
      # @param visitor [Object] implements visit_* methods
      # @raise [NotImplementedError] if not overridden
      def accept(visitor)
        raise NotImplementedError,
              "Missing #accept in #{self.class.name}"
      end
    end

    class Str
      # Dispatches to visitor's visit_str.
      #
      # @param visitor [Object] visitor object
      def accept(visitor)
        visitor.visit_str(str)
      end
    end

    class Entity
      # Dispatches to visitor's visit_entity.
      #
      # @param visitor [Object] visitor object
      def accept(visitor)
        visitor.visit_entity(rule_name, @body)
      end
    end

    class Named
      # Dispatches to visitor's visit_named.
      #
      # @param visitor [Object] visitor object
      def accept(visitor)
        visitor.visit_named(name, parslet)
      end
    end

    class Sequence
      # Dispatches to visitor's visit_sequence.
      #
      # @param visitor [Object] visitor object
      def accept(visitor)
        visitor.visit_sequence(parslets)
      end
    end

    class Repetition
      # Dispatches to visitor's visit_repetition.
      #
      # @param visitor [Object] visitor object
      def accept(visitor)
        visitor.visit_repetition(result_tag, min, max, parslet)
      end
    end

    class Alternative
      # Dispatches to visitor's visit_alternative.
      #
      # @param visitor [Object] visitor object
      def accept(visitor)
        visitor.visit_alternative(alternatives)
      end
    end

    class Lookahead
      # Dispatches to visitor's visit_lookahead.
      #
      # @param visitor [Object] visitor object
      def accept(visitor)
        visitor.visit_lookahead(positive, bound_parslet)
      end
    end

    class Re
      # Dispatches to visitor's visit_re.
      #
      # @param visitor [Object] visitor object
      def accept(visitor)
        visitor.visit_re(match)
      end
    end
  end
end
