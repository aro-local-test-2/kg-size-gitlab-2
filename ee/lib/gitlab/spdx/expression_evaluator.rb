# frozen_string_literal: true

module Gitlab
  module SPDX
    # Walks a Gitlab::SPDX::ExpressionParser node tree: `AND` matches only if every
    # operand matches, `OR` if any operand does. Includers implement `evaluate_leaf(value,
    # context)` and may override `evaluate_id`/`evaluate_literal`/`evaluate_plus`/
    # `evaluate_with`/`evaluate_fallback` when a node type needs more than a plain leaf match.
    module ExpressionEvaluator
      COMPOUND_NODE_TYPES = %i[and or with plus].freeze

      private

      def evaluate(node, context = nil)
        case node.type
        when :and
          node.children.all? { |child| evaluate(child, context) }
        when :or
          node.children.any? { |child| evaluate(child, context) }
        when :with
          evaluate_with(node, context)
        when :id
          evaluate_id(node, context)
        when :literal
          evaluate_literal(node, context)
        when :plus
          evaluate_plus(node, context)
        else
          evaluate_fallback(node, context)
        end
      end

      # "base WITH exception" matches when the base license matches on its own,
      # or when the full expression is listed verbatim.
      def evaluate_with(node, context)
        base_node, exception_node = node.children
        full_expression = "#{base_node.value} #{node.value} #{exception_node.value}"

        evaluate(base_node, context) || evaluate_leaf(full_expression, context)
      end

      def evaluate_id(node, context)
        evaluate_leaf(node.value, context)
      end

      def evaluate_literal(node, context)
        evaluate_leaf(node.value, context)
      end

      def evaluate_plus(node, context)
        evaluate_leaf(node.value, context)
      end

      def evaluate_fallback(node, context)
        evaluate_leaf(node.value.to_s, context)
      end
    end
  end
end
