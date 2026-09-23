# frozen_string_literal: true

module Ai
  module FoundationalFlowMessages
    module_function

    def usage_billing_forbidden_error
      s_(
        "DuoFoundationalFlows|Usage billing is not available for this account. " \
          "To continue using this feature, contact your administrator."
      )
    end

    def namespace_missing_error(user)
      docs_url = Rails.application.routes.url_helpers.help_page_url(
        'user/profile/preferences.md',
        anchor: 'set-a-default-gitlab-duo-namespace'
      )

      format(
        s_(
          "DuoFoundationalFlows|:warning: %{user_reference}, you need to set a default GitLab Duo namespace " \
            "to use this flow. Please set a default GitLab Duo namespace in your %{link_start}preferences%{link_end}."
        ),
        user_reference: user.to_reference,
        link_start: "[",
        link_end: "](#{docs_url})"
      )
    end

    def no_eligible_runner_error
      format(
        s_(
          "DuoFoundationalFlows|This flow could not start because the project has no runner available to " \
            "run it. It needs an instance runner or a top-level group runner with the '%{tag}' tag and a " \
            "Docker-compatible executor."
        ),
        tag: ::Ai::DuoWorkflows::Workflow::WORKLOAD_TAG
      )
    end

    def namespace_ci_minutes_used_up_error
      s_(
        "DuoFoundationalFlows|This flow could not start because the namespace has run out of compute minutes. " \
          "Ask someone with billing access to add compute minutes before trying again."
      )
    end
  end
end
