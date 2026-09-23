# frozen_string_literal: true

module MergeRequests
  class SidebarBasicEntity < IssuableSidebarBasicEntity
    expose :multiple_approval_rules_available do |merge_request|
      merge_request.target_project.multiple_approval_rules_available?
    end

    expose :ai_suggested_reviewers_available do |merge_request|
      merge_request.target_project.recommend_reviewers_dap_available?
    end
  end
end
