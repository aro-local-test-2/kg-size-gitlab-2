# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.project(fullPath).ciVariables', feature_category: :pipeline_composition do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:maintainer) { create(:user, maintainer_of: project) }
  let_it_be(:variable) { create(:ci_variable, project: project, key: 'PROJECT_TOKEN') }
  let_it_be(:hidden_variable) do
    create(:ci_variable, project: project, key: 'HIDDEN_PROJECT_TOKEN', masked: true, hidden: true)
  end

  it_behaves_like 'auditing CI/CD variable value access' do
    let(:audit_scope) { project }
    let(:auth_user) { maintainer }
    let(:variable_key) { variable.key }
    let(:hidden_variable_key) { hidden_variable.key }

    def variables_query(fields)
      <<~GQL
        query {
          project(fullPath: "#{project.full_path}") {
            ciVariables { nodes { #{fields.join(' ')} } }
          }
        }
      GQL
    end
  end

  describe 'when auditing raises' do
    let(:query) do
      <<~GQL
        query {
          project(fullPath: "#{project.full_path}") {
            ciVariables { nodes { key value } }
          }
        }
      GQL
    end

    before do
      stub_licensed_features(audit_events: true)
      allow(::Gitlab::Audit::Auditor).to receive(:audit)
        .with(hash_including(name: 'variable_viewed_graphql'))
        .and_raise(StandardError, 'auditing failed')
    end

    it 'tracks the exception and still returns the query result' do
      expect(::Gitlab::ErrorTracking).to receive(:track_exception)
        .with(instance_of(StandardError), scope_type: 'Project', scope_id: project.id)

      post_graphql(query, current_user: maintainer)

      expect(response).to have_gitlab_http_status(:ok)
      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:project, :ciVariables, :nodes)).to include(
        a_hash_including('key' => variable.key, 'value' => variable.value)
      )
    end
  end

  describe 'when query execution fails after a value was read' do
    let(:query) do
      <<~GQL
        query {
          project(fullPath: "#{project.full_path}") {
            ciVariables { nodes { key value } }
          }
        }
      GQL
    end

    before do
      stub_licensed_features(audit_events: true)
      allow(::Gitlab::Audit::Auditor).to receive(:audit).and_call_original

      # Fail once a value has already been read, so the query raises with the
      # collector holding a recorded access.
      allow_next_instance_of(::Gitlab::Ci::Variables::AccessCollector) do |collector|
        recorded = 0
        allow(collector).to receive(:record).and_wrap_original do |original, **kwargs|
          recorded += 1
          raise StandardError, 'execution failed' if recorded > 1

          original.call(**kwargs)
        end
      end
    end

    it 'audits the value that was read before the failure' do
      expect(::Gitlab::Audit::Auditor).to receive(:audit).with(hash_including(
        name: 'variable_viewed_graphql',
        scope: project
      ))

      post_graphql(query, current_user: maintainer)

      expect(response).to have_gitlab_http_status(:internal_server_error)
    end
  end

  describe 'when a single query reads variables from several owners' do
    let_it_be(:group) { create(:group) }
    let_it_be(:group_project) { create(:project, group: group) }
    let_it_be(:owner) { create(:user, owner_of: group) }
    let_it_be(:group_variable) { create(:ci_group_variable, group: group, key: 'GROUP_TOKEN') }
    let_it_be(:group_project_variable) do
      create(:ci_variable, project: group_project, key: 'GROUP_PROJECT_TOKEN')
    end

    let(:query) do
      <<~GQL
        query {
          project(fullPath: "#{group_project.full_path}") {
            ciVariables { nodes { key value } }
          }
          group(fullPath: "#{group.full_path}") {
            ciVariables { nodes { key value } }
          }
        }
      GQL
    end

    before do
      stub_licensed_features(audit_events: true)
      allow(::Gitlab::Audit::Auditor).to receive(:audit).and_call_original
    end

    it 'audits each owner separately' do
      expect(::Gitlab::Audit::Auditor).to receive(:audit).with(hash_including(
        name: 'variable_viewed_graphql',
        scope: group_project,
        additional_details: hash_including(accessed_keys: [group_project_variable.key])
      ))
      expect(::Gitlab::Audit::Auditor).to receive(:audit).with(hash_including(
        name: 'variable_viewed_graphql',
        scope: group,
        additional_details: hash_including(accessed_keys: [group_variable.key])
      ))

      post_graphql(query, current_user: owner)
    end

    it 'audits the remaining owner when one owner fails to audit' do
      allow(::Gitlab::Audit::Auditor).to receive(:audit)
        .with(hash_including(name: 'variable_viewed_graphql', scope: group_project))
        .and_raise(StandardError, 'auditing failed')

      expect(::Gitlab::ErrorTracking).to receive(:track_exception)
        .with(instance_of(StandardError), scope_type: 'Project', scope_id: group_project.id)
      expect(::Gitlab::Audit::Auditor).to receive(:audit)
        .with(hash_including(name: 'variable_viewed_graphql', scope: group))

      post_graphql(query, current_user: owner)
    end
  end

  describe 'when only hidden variable values were requested' do
    let_it_be(:hidden_only_project) { create(:project) }
    let_it_be(:hidden_only_maintainer) { create(:user, maintainer_of: hidden_only_project) }
    let_it_be(:hidden_only_variable) do
      create(:ci_variable, project: hidden_only_project, key: 'HIDDEN_ONLY_TOKEN', masked: true, hidden: true)
    end

    let(:query) do
      <<~GQL
        query {
          project(fullPath: "#{hidden_only_project.full_path}") {
            ciVariables { nodes { key value } }
          }
        }
      GQL
    end

    before do
      stub_licensed_features(audit_events: true)
      allow(::Gitlab::Audit::Auditor).to receive(:audit).and_call_original
    end

    it 'audits the withheld key and leaves target details to the auditor' do
      expect(::Gitlab::Audit::Auditor).to receive(:audit).with(hash_including(
        name: 'variable_viewed_graphql',
        scope: hidden_only_project,
        target_details: nil,
        additional_details: hash_including(
          accessed_keys: [],
          hidden_keys: [hidden_only_variable.key]
        )
      ))

      post_graphql(query, current_user: hidden_only_maintainer)
    end
  end

  describe 'recording variable value access' do
    let_it_be(:warmup_user) { create(:user, maintainer_of: project) }
    let_it_be(:control_user) { create(:user, maintainer_of: project) }
    let_it_be(:action_user) { create(:user, maintainer_of: project) }

    let(:value_query) do
      graphql_query_for('project', { 'fullPath' => project.full_path },
        query_graphql_field('ciVariables', {}, query_graphql_field('nodes', {}, %w[key value])))
    end

    before do
      stub_licensed_features(audit_events: true)
    end

    # A different user per request avoids false positives from authentication
    # queries that only run on a user's first request.
    it 'avoids N+1 queries when resolving the variable owner', :request_store, :use_sql_query_cache do
      create(:ci_variable, project: project)
      post_graphql(value_query, current_user: warmup_user)

      control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
        post_graphql(value_query, current_user: control_user)
      end

      create_list(:ci_variable, 3, project: project)

      expect do
        post_graphql(value_query, current_user: action_user)
      end.to issue_same_number_of_queries_as(control)
    end
  end
end
