# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['PolicyStoreTrigger'], feature_category: :security_policy_management do
  specify { expect(described_class).to have_graphql_fields(:id, :name, :available_roles) }

  describe '#available_roles' do
    let(:type_instance) { described_class.send(:new, object, context) }
    let(:context) { instance_double(GraphQL::Query::Context) }

    context 'with a deployment trigger' do
      let(:object) { { id: 'deployment_requested', name: 'Deployment Requested' } }

      it 'returns only CD roles' do
        roles = type_instance.available_roles

        role_ids = roles.map { |r| r[:id] }
        expect(role_ids).to contain_exactly('release_manager', 'deployment_observer')
        expect(role_ids).not_to include('developer', 'maintainer', 'owner')
      end
    end

    context 'with a non-deployment trigger' do
      let(:object) { { id: 'some_other_trigger', name: 'Other Trigger' } }

      it 'returns only GitLab roles' do
        roles = type_instance.available_roles

        role_ids = roles.map { |r| r[:id] }
        expect(role_ids).to contain_exactly('developer', 'maintainer', 'owner')
        expect(role_ids).not_to include('release_manager', 'deployment_observer')
      end
    end
  end
end
