# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['GitlabSubscriptionUsageUserEvent'], feature_category: :consumables_cost_management do
  include GraphqlHelpers

  it { expect(described_class.graphql_name).to eq('GitlabSubscriptionUsageUserEvent') }
  it { expect(described_class).to require_graphql_authorizations(:read_user) }

  it 'has expected fields' do
    expect(described_class).to have_graphql_fields([:timestamp, :event_type, :flow_type, :location, :location_id,
      :credits_used, :session_link])
  end

  describe '#location_id' do
    let(:event_type) { described_class.send(:new, event, instance_double(GraphQL::Query::Context)) }
    let(:project_id) { nil }
    let(:namespace_id) { nil }

    let(:event) do
      Types::GitlabSubscriptions::SubscriptionUsage::UserType::UserEvent.new(
        '2025-10-01T16:30:12Z', 'workflow_execution', 'Flow', project_id, namespace_id, 25.32,
        nil, false, nil
      )
    end

    context 'when the event has both a project and a namespace ID' do
      let(:project_id) { non_existing_record_id }
      let(:namespace_id) { non_existing_record_id + 1 }

      it 'returns the project global ID, matching how #location resolves the event' do
        expect(event_type.location_id).to eq(::Gitlab::GlobalId.build(model_name: 'Project', id: project_id))
      end
    end

    context 'when the event only has a namespace ID' do
      let(:namespace_id) { non_existing_record_id }

      it 'returns the group global ID' do
        expect(event_type.location_id).to eq(::Gitlab::GlobalId.build(model_name: 'Group', id: namespace_id))
      end
    end

    context 'when the event has neither a project nor a namespace ID' do
      it 'returns nil' do
        expect(event_type.location_id).to be_nil
      end
    end
  end

  describe '#session_link' do
    let(:event_type) { described_class.send(:new, event, context) }
    let(:context) { instance_double(GraphQL::Query::Context) }
    let_it_be(:project) { create(:project) }
    let(:project_id) { project.id }
    let(:session_id) { 100 }
    let(:show_session_link) { true }

    let(:event) do
      Types::GitlabSubscriptions::SubscriptionUsage::UserType::UserEvent.new(
        '2025-10-01T16:30:12Z', 'workflow_execution', 'Flow', project_id, nil, 25.32,
        session_id, show_session_link, nil
      )
    end

    context 'when show_session_link is false' do
      let(:show_session_link) { false }

      it 'returns nil' do
        expect(event_type.session_link).to be_nil
      end
    end

    context 'when project_id is nil' do
      let(:project_id) { nil }

      it 'returns nil' do
        expect(event_type.session_link).to be_nil
      end
    end

    context 'when session_id is nil' do
      let(:session_id) { nil }

      it 'returns nil' do
        expect(event_type.session_link).to be_nil
      end
    end

    context 'when project is not found' do
      let(:project_id) { non_existing_record_id }

      it 'returns nil' do
        result = batch_sync { event_type.session_link }

        expect(result).to be_nil
      end
    end

    context 'when all conditions are met' do
      it 'returns the session URL' do
        result = batch_sync { event_type.session_link }

        expected_url = "#{Gitlab::Routing.url_helpers.project_automate_agent_sessions_url(project)}/#{session_id}"
        expect(result).to eq(expected_url)
      end
    end
  end
end
