# frozen_string_literal: true

# `Gitlab::PolicyStore.configuration` is a process-wide singleton, so the `ensure`
# is what keeps a swap from outliving the example that made it.
RSpec.shared_context 'with a swapped policy store repository' do
  def with_policy_store_repository(repository)
    original_repository = ::Gitlab::PolicyStore.configuration.repository

    ::Gitlab::PolicyStore.configure { |config| config.repository = repository }

    yield
  ensure
    ::Gitlab::PolicyStore.configure { |config| config.repository = original_repository }
  end

  def create_policy(**attributes)
    ::Gitlab::PolicyStore.create(attributes) # rubocop:disable Rails/SaveBang -- not ActiveRecord; the store has no create!
  end
end

RSpec.shared_context 'with an empty policy store' do
  include_context 'with a swapped policy store repository'

  around do |example|
    with_policy_store_repository(::Gitlab::PolicyStore::Adapters::InMemoryPolicyRepository.new) { example.run }
  end
end

# For the examples that have to run against the backend production will configure,
# whether to prove a service behaves the same or to reach behaviour only it has.
RSpec.shared_context 'with a persistent policy store' do
  include_context 'with a swapped policy store repository'

  around do |example|
    with_policy_store_repository(::Govern::PolicyStore::ActiveRecordPolicyRepository.new) { example.run }
  end
end

RSpec.shared_context 'with the policy store experiment active' do
  before do
    stub_licensed_features(security_orchestration_policies: true)
    stub_application_setting(policy_store_experiment_enabled: true)
  end

  # The instance-wide gates above make the experiment available; the
  # organization additionally has to opt in, the way a group does.
  def opt_organization_into_policy_store!(organization)
    ::Organizations::OrganizationSetting.for(organization.id).update!(
      policy_store_experiment_enabled: true
    )
  end
end

# Sets up an organization with an owner (authorized to manage policies), a
# non-owner member (not authorized), and an owner of an unrelated organization
# (not authorized either; ownership does not cross organizations).
# `current_user` defaults to the owner. `container` defaults to the organization;
# override with `let(:container) { group }` for group-scoped tests.
RSpec.shared_context 'with policy store service authorization' do
  include_context 'with the policy store experiment active'

  let_it_be_with_reload(:organization) { create(:organization) }

  # Default container is the organization. Override in group-scoped tests.
  let(:container) { organization }
  let_it_be(:owner) { create(:user) }
  let_it_be(:non_owner) { create(:user) }
  let_it_be(:foreign_organization) { create(:organization) }
  let_it_be(:foreign_org_owner) { create(:user) }

  let(:current_user) { owner }

  before_all do
    create(:organization_user, :owner, organization: organization, user: owner)
    create(:organization_user, organization: organization, user: non_owner)
    create(:organization_user, :owner, organization: foreign_organization, user: foreign_org_owner)
  end

  before do
    opt_organization_into_policy_store!(organization)
  end
end

RSpec.configure do |config|
  config.include_context 'with an empty policy store', :policy_store
end

# A root group inside the organization, opted into the experiment, with its own
# Owner, who holds the group-level *_govern_policy abilities without owning the
# organization. `other_group` exists so cross-namespace isolation can be
# asserted. Include after 'with policy store service authorization'.
RSpec.shared_context 'with policy store group containers' do
  let_it_be(:group_owner) { create(:user) }

  # Opting in and adding the owner happen inside the blocks: let_it_be freezes
  # the records afterwards.
  let_it_be(:group) do
    create(:group, organization: organization).tap do |g|
      g.namespace_settings.update!(policy_store_experiment_enabled: true)
      g.add_owner(group_owner)
    end
  end

  let_it_be(:other_group) do
    create(:group, organization: organization).tap do |g|
      g.namespace_settings.update!(policy_store_experiment_enabled: true)
    end
  end
end
