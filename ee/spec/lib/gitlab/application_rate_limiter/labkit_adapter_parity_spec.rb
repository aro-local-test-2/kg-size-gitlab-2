# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'ApplicationRateLimiter characteristic hash parity', feature_category: :system_access do
  it_behaves_like 'application rate limiter characteristic hash parity' do
    let_it_be(:duo_workflow) { build_stubbed(:duo_workflows_workflow) }
    let_it_be(:merge_request) { build_stubbed(:merge_request, source_project: project) }

    let(:rows) do
      [
        [:duo_workflow_unauthorized_access, [user, duo_workflow], { user: user, duo_workflow: duo_workflow }],
        [:hard_phone_verification_transactions_limit, :global, { scope: :global }],
        [:soft_phone_verification_transactions_limit, :global, { scope: :global }],
        [:search_index_integrity, [project], { project: project }],
        [:search_index_integrity, [group], { group: group }],
        [:unique_project_downloads_for_namespace, [user, group], { user: user, namespace: group }],
        [:update_namespace_name, group, { namespace: group }],
        [:merge_request_resync_security_policies, merge_request, { merge_request: merge_request }]
      ]
    end
  end
end
