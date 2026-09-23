# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'ProjectMemberBulkUpdate', feature_category: :groups_and_projects do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be(:mutation_name) { :project_member_bulk_update }

  context 'with promotion management feature' do
    let_it_be_with_refind(:source) { create(:project) }
    let(:source_id_key) { 'project_id' }
    let(:response_member_field) { "projectMembers" }

    it_behaves_like 'promotion management for members bulk update'
  end

  context 'with the seat assignment model', :saas, :aggregate_failures do
    let_it_be(:root_group) { create(:group, :seat_assignment_model_enabled) }
    let_it_be_with_refind(:source) { create(:project, group: root_group) }

    let(:source_id_key) { 'project_id' }
    let(:response_member_field) { 'projectMembers' }

    # The shared example was added in 9c97ad46 without a query-limit
    # allowance. Bulk-updating two project members triggers ~106 SQL
    # queries (per-member seat-assignment checks, namespace/member
    # lookups, authorization recalculation, audit events, and
    # notification-settings reads), exceeding the default limit of 100.
    # See https://gitlab.com/gitlab-org/quality/analytics/ci-health-incidents/-/work_items/1287
    before do
      allow_high_graphql_transaction_threshold
    end

    it_behaves_like 'seat type enforcement for members bulk update'
  end
end
