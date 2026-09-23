# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecurityOrchestrationPolicies::PolicyStore::ListService, :policy_store,
  feature_category: :security_policy_management do
  include_context 'with policy store service authorization'
  include_context 'with the policy store experiment active'

  subject(:service) { described_class.new(container: container, current_user: current_user) }

  describe '#execute' do
    let_it_be(:other_organization) { create(:organization) }

    let!(:policy) do
      create_policy(
        organization_id: organization.id,
        name: 'Test policy',
        trigger_type: 'deployment_requested'
      )
    end

    let!(:other_organization_policy) do
      create_policy(
        organization_id: other_organization.id,
        name: 'Other organization policy',
        trigger_type: 'deployment_requested'
      )
    end

    it 'returns only the policies of the given organization', :aggregate_failures do
      result = service.execute

      expect(result).to be_success
      expect(result.payload[:policies]).to contain_exactly(policy)
      expect(result.payload[:policies]).to all(be_a(Gitlab::PolicyStore::Policy))
    end

    it 'defaults page and per_page, returning the pagination metadata', :aggregate_failures do
      result = service.execute

      expect(result.payload[:page]).to eq(1)
      expect(result.payload[:per_page]).to eq(Gitlab::PolicyStore::Ports::PolicyRepository::DEFAULT_PER_PAGE)
      expect(result.payload[:has_next_page]).to be(false)
    end

    context 'with pagination' do
      let!(:other_policy) do
        create_policy(organization_id: organization.id, name: 'Other policy', trigger_type: 'deployment_requested')
      end

      subject(:service) do
        described_class.new(container: container, current_user: current_user, page: 2, per_page: 1)
      end

      it 'returns the requested page and reports whether another one follows', :aggregate_failures do
        result = service.execute

        expect(result.payload[:policies]).to contain_exactly(other_policy)
        expect(result.payload[:page]).to eq(2)
        expect(result.payload[:per_page]).to eq(1)
        expect(result.payload[:has_next_page]).to be(false)
      end
    end

    context 'when the organization has no policies' do
      let_it_be(:empty_organization) { create(:organization) }
      let_it_be(:empty_org_owner) { create(:user) }

      subject(:service) { described_class.new(container: empty_organization, current_user: empty_org_owner) }

      before_all do
        create(:organization_user, :owner, organization: empty_organization, user: empty_org_owner)
      end

      before do
        opt_organization_into_policy_store!(empty_organization)
      end

      it 'returns an empty collection', :aggregate_failures do
        result = service.execute

        expect(result).to be_success
        expect(result.payload[:policies]).to be_empty
      end
    end

    context 'with a trigger_type' do
      let!(:promoted_deployment_policy) do
        create_policy(
          organization_id: organization.id,
          name: 'Promoted deployment policy',
          trigger_type: 'deployment_promoted'
        )
      end

      subject(:service) do
        described_class.new(container: container, current_user: current_user,
          trigger_type: 'deployment_promoted')
      end

      it 'returns only the policies for that trigger', :aggregate_failures do
        result = service.execute

        expect(result).to be_success
        expect(result.payload[:policies]).to contain_exactly(promoted_deployment_policy)
      end

      context 'when no policy targets it' do
        subject(:service) do
          described_class.new(container: container, current_user: current_user,
            trigger_type: 'environment_advanced')
        end

        it 'returns an empty collection' do
          expect(service.execute.payload[:policies]).to be_empty
        end
      end
    end

    context 'with lifecycle_state' do
      let!(:disabled_policy) do
        create_policy(
          organization_id: organization.id,
          name: 'Disabled policy',
          trigger_type: 'deployment_requested',
          lifecycle_state: 'disabled'
        )
      end

      it 'defaults to only the active policies' do
        expect(service.execute.payload[:policies]).to contain_exactly(policy)
      end

      context 'when lifecycle_state is disabled' do
        subject(:service) do
          described_class.new(container: organization, current_user: current_user, lifecycle_state: 'disabled')
        end

        it 'returns only the disabled policies' do
          expect(service.execute.payload[:policies]).to contain_exactly(disabled_policy)
        end
      end

      context 'when lifecycle_state is active' do
        subject(:service) do
          described_class.new(container: organization, current_user: current_user, lifecycle_state: 'active')
        end

        it 'matches the default and returns only the active policies' do
          expect(service.execute.payload[:policies]).to contain_exactly(policy)
        end
      end

      context 'when lifecycle_state is all' do
        subject(:service) do
          described_class.new(container: organization, current_user: current_user, lifecycle_state: 'all')
        end

        it 'returns every policy regardless of lifecycle state' do
          expect(service.execute.payload[:policies]).to contain_exactly(policy, disabled_policy)
        end
      end

      context 'when combined with a trigger_type' do
        subject(:service) do
          described_class.new(container: organization, current_user: current_user,
            trigger_type: 'deployment_requested', lifecycle_state: 'disabled')
        end

        it 'returns only the policies matching both filters' do
          expect(service.execute.payload[:policies]).to contain_exactly(disabled_policy)
        end
      end
    end

    context 'with ids' do
      let!(:promoted_deployment_policy) do
        create_policy(
          organization_id: organization.id,
          name: 'Promoted deployment policy',
          trigger_type: 'deployment_promoted'
        )
      end

      subject(:service) do
        described_class.new(container: container, current_user: current_user, ids: [policy.id])
      end

      it 'returns only the policies with those ids', :aggregate_failures do
        result = service.execute

        expect(result).to be_success
        expect(result.payload[:policies]).to contain_exactly(policy)
      end

      context 'when combined with a trigger_type' do
        subject(:service) do
          described_class.new(container: container, current_user: current_user,
            ids: [policy.id, promoted_deployment_policy.id], trigger_type: 'deployment_promoted')
        end

        it 'returns only the policies matching both filters' do
          expect(service.execute.payload[:policies]).to contain_exactly(promoted_deployment_policy)
        end
      end

      context 'when no policy has the ids' do
        subject(:service) do
          described_class.new(container: container, current_user: current_user,
            ids: [non_existing_record_id])
        end

        it 'returns an empty collection', :aggregate_failures do
          result = service.execute

          expect(result).to be_success
          expect(result.payload[:policies]).to be_empty
        end
      end

      context 'with the id of a policy in another organization' do
        subject(:service) do
          described_class.new(container: container, current_user: current_user,
            ids: [other_organization_policy.id])
        end

        it 'does not leak the other organization policy' do
          expect(service.execute.payload[:policies]).to be_empty
        end
      end

      context 'when ids is empty' do
        subject(:service) do
          described_class.new(container: container, current_user: current_user, ids: [])
        end

        it 'returns no policies rather than the unfiltered list' do
          expect(service.execute.payload[:policies]).to be_empty
        end
      end

      context 'when ids is nil' do
        subject(:service) do
          described_class.new(container: container, current_user: current_user, ids: nil)
        end

        it 'returns the unfiltered list' do
          expect(service.execute.payload[:policies]).to contain_exactly(policy, promoted_deployment_policy)
        end
      end

      context 'when an id falls outside the default page size' do
        let!(:padding_policies) do
          Array.new(Gitlab::PolicyStore::Ports::PolicyRepository::DEFAULT_PER_PAGE) do |index|
            create_policy(
              organization_id: organization.id, name: "Padding policy #{index}",
              trigger_type: 'deployment_requested'
            )
          end
        end

        subject(:service) do
          described_class.new(container: container, current_user: current_user,
            ids: [padding_policies.last.id])
        end

        it 'still finds the policy, since ids bypass the page bounds' do
          expect(service.execute.payload[:policies]).to contain_exactly(padding_policies.last)
        end
      end

      context 'when ids exceeds MAX_PER_PAGE' do
        subject(:service) do
          described_class.new(container: container, current_user: current_user,
            ids: Array.new(Gitlab::PolicyStore::Ports::PolicyRepository::MAX_PER_PAGE + 1) { |index| index })
        end

        it 'returns an invalid error rather than running an unbounded query', :aggregate_failures do
          result = service.execute

          expect(result).to be_error
          expect(result.reason).to eq(:invalid)
          expect(result.message).to match(/ids exceeds maximum/)
        end
      end
    end

    it_behaves_like 'a service that requires policy authorization', :read_govern_policy

    context 'with the persistent repository' do
      include_context 'with a persistent policy store'

      it 'reads only the rows of the given organization', :aggregate_failures do
        result = service.execute

        expect(result).to be_success
        expect(result.payload[:policies].map(&:id)).to contain_exactly(policy.id)
      end

      context 'with ids' do
        subject(:service) do
          described_class.new(container: container, current_user: current_user,
            ids: [other_organization_policy.id])
        end

        it 'filters the persistent rows by id within the organization' do
          expect(service.execute.payload[:policies]).to be_empty
        end
      end
    end

    it_behaves_like 'a service gated by the policy store experiment', :list
  end

  context 'with a group container' do
    include_context 'with policy store group containers'

    let(:container) { group }
    let(:current_user) { group_owner }

    # Organization-wide policy - must NOT appear in group-scoped results.
    let!(:org_wide_policy) do
      create_policy(
        organization_id: organization.id,
        name: 'Organization-wide policy',
        trigger_type: 'deployment_requested'
      )
    end

    let!(:group_policy) do
      create_policy(
        organization_id: organization.id,
        namespace_id: group.id,
        name: 'Group policy',
        trigger_type: 'deployment_requested'
      )
    end

    let!(:other_group_policy) do
      create_policy(
        organization_id: organization.id,
        namespace_id: other_group.id,
        name: 'Other group policy',
        trigger_type: 'deployment_requested'
      )
    end

    it "returns only the group's own policies, excluding organization-wide policies", :aggregate_failures do
      result = service.execute

      expect(result).to be_success
      expect(result.payload[:policies]).to contain_exactly(group_policy)
      expect(result.payload[:policies]).not_to include(org_wide_policy)
    end

    it 'is forbidden for an organization member who holds no group ability' do
      result = described_class.new(container: group, current_user: non_owner).execute

      expect(result).to be_error
      expect(result.reason).to eq(:forbidden)
    end

    it 'is allowed for the organization owner, who supervises every group of the organization' do
      result = described_class.new(container: group, current_user: owner).execute

      expect(result).to be_success
    end

    context 'when the group is not a root group' do
      # Opted in like its parent, so root-ness is the only condition that fails.
      let_it_be(:subgroup) do
        create(:group, parent: group, organization: organization).tap do |g|
          g.namespace_settings.update!(policy_store_experiment_enabled: true)
          g.add_owner(group_owner)
        end
      end

      let(:container) { subgroup }

      it 'reports as forbidden since the experiment gate prevents the ability' do
        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:forbidden)
      end
    end

    context 'when the group has not opted into the experiment' do
      let_it_be(:non_opted_group) do
        create(:group, organization: organization).tap do |g|
          g.add_owner(group_owner)
        end
      end

      let(:container) { non_opted_group }

      it 'reports as forbidden since the experiment gate prevents the ability' do
        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:forbidden)
      end
    end
  end
end
