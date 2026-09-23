# frozen_string_literal: true

module Graphql
  module Subscriptions
    module Cd
      module EnvironmentServiceUpdated
        module Helper
          def subscription_response
            subscription_channel = subscribe
            yield
            subscription_channel.mock_broadcasted_messages.first
          end

          def cd_environment_service_updated_subscription(environment, current_user)
            mock_channel = Graphql::Subscriptions::ActionCable::MockActionCable.get_mock_channel
            query = cd_environment_service_updated_subscription_query(environment)

            GitlabSchema.execute(query, context: { current_user: current_user, channel: mock_channel })

            mock_channel
          end

          private

          def cd_environment_service_updated_subscription_query(environment)
            <<~SUBSCRIPTION
              subscription {
                cdEnvironmentServiceUpdated(environmentId: "#{environment.to_global_id}") {
                  id
                  name
                }
              }
            SUBSCRIPTION
          end
        end
      end
    end
  end
end
