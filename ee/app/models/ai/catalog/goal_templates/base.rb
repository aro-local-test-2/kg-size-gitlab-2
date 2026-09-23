# frozen_string_literal: true

module Ai
  module Catalog
    module GoalTemplates
      class Base
        DEFAULT_MENTION_TEMPLATE = <<~GOAL.strip
          Input: %{user_input}
          Context: {%{resource_type} %{id_type}: %{id_value}}
        GOAL

        def self.resolve(event_type:, resource:, user_input:, params: {})
          raise NotImplementedError, "#{name} must implement .resolve"
        end

        def self.default_mention_goal(resource:, user_input:)
          resource_type = resource.class.name.demodulize
          id_type, id_value = resource.respond_to?(:iid) ? ['IID', resource.iid] : ['ID', resource.id]

          interpolate(DEFAULT_MENTION_TEMPLATE,
            vars: {
              resource_type: resource_type,
              id_type: id_type,
              id_value: id_value
            },
            user_input: user_input
          )
        end

        # gsub (not format) so user %{...} cannot KeyError; user_input last so
        # it is never re-interpreted; block-form so \& and \1 in user text are
        # not expanded (which would also break exact goal-length accounting).
        def self.interpolate(template, vars:, user_input: nil)
          goal = vars.reduce(template) { |result, (key, value)| result.gsub("%{#{key}}") { value.to_s } }
          user_input ? goal.gsub('%{user_input}') { user_input.to_s } : goal
        end
      end
    end
  end
end
