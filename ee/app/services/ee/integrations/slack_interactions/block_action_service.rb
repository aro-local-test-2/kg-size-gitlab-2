# frozen_string_literal: true

module EE
  module Integrations
    module SlackInteractions
      module BlockActionService
        extend ::Gitlab::Utils::Override

        EE_HANDLERS = {
          ::Ai::Messaging::Adapters::Slack::FEEDBACK_ACTION_ID =>
            ::Integrations::SlackInteractions::SlackBlockActions::DuoFeedbackHandler,
          ::Ai::Messaging::Adapters::Slack::APPROVAL_REVIEW_ACTION_ID =>
            ::Integrations::SlackInteractions::SlackBlockActions::DuoApprovalReviewHandler
        }.freeze

        private

        override :handlers
        def handlers
          super.merge(EE_HANDLERS)
        end
      end
    end
  end
end
