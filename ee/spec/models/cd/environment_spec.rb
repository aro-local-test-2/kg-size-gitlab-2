# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::Environment, feature_category: :continuous_delivery do
  describe 'associations' do
    it { is_expected.to belong_to(:organization).required }
    it { is_expected.to have_many(:environment_driver_bindings) }
    it { is_expected.to have_many(:rollout_environments) }
    it { is_expected.to have_many(:service_environment_healths) }
  end

  describe 'validations' do
    subject { create(:cd_environment) }

    it { is_expected.to be_valid }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:organization_id) }
    it { is_expected.to validate_presence_of(:tier) }
    it { is_expected.to define_enum_for(:tier).with_values(development: 0, qa: 1, staging: 2, production: 3) }

    describe 'name format' do
      it { is_expected.to allow_value('my-env').for(:name) }
      it { is_expected.to allow_value('my_env').for(:name) }
      it { is_expected.to allow_value('MyEnv').for(:name) }
      it { is_expected.to allow_value('env1').for(:name) }
      it { is_expected.to allow_value('1env').for(:name) }
      it { is_expected.not_to allow_value('-env').for(:name) }
      it { is_expected.not_to allow_value('env-').for(:name) }
      it { is_expected.not_to allow_value('my env').for(:name) }
      it { is_expected.not_to allow_value('env/name').for(:name) }
      it { is_expected.not_to allow_value('env.name').for(:name) }
      it { is_expected.not_to allow_value('env!').for(:name) }
    end

    it { is_expected.to validate_length_of(:description).is_at_most(1024) }

    describe 'sharding key' do
      it 'is invalid without an organization' do
        env = build(:cd_environment, organization: nil)

        expect(env).not_to be_valid
      end
    end
  end

  describe 'scopes' do
    describe '.for_organization' do
      it 'returns environments belonging to the given organization' do
        env = create(:cd_environment)
        create(:cd_environment)

        expect(described_class.for_organization(env.organization_id)).to contain_exactly(env)
      end
    end

    describe '.in_organization' do
      let_it_be(:organization) { create(:organization) }
      let_it_be(:other_organization) { create(:organization) }
      let_it_be(:org_environment) { create(:cd_environment, organization: organization) }
      let_it_be(:other_org_environment) { create(:cd_environment, organization: other_organization) }

      it 'returns environments belonging to the organization' do
        expect(described_class.in_organization(organization)).to contain_exactly(org_environment)
      end
    end

    describe '.order_by_name_asc' do
      it 'returns environments ordered by name ascending' do
        env_b = create(:cd_environment, name: 'beta')
        env_a = create(:cd_environment, name: 'alpha')

        expect(described_class.order_by_name_asc).to eq([env_a, env_b])
      end
    end

    describe '.with_tier' do
      let_it_be(:production_env) { create(:cd_environment, :production) }
      let_it_be(:staging_env) { create(:cd_environment, :staging) }

      it 'returns environments matching the given tier' do
        expect(described_class.with_tier(:production)).to contain_exactly(production_env)
      end
    end

    describe '.with_worst_health' do
      let_it_be(:organization) { create(:organization) }

      def environment_with_service_healths(*healths)
        environment = create(:cd_environment, organization: organization)
        healths.each do |health|
          create(:cd_service_environment_health,
            service: create(:cd_service, application: create(:cd_application, organization: organization)),
            environment: environment, health: health)
        end
        environment
      end

      it 'matches environments whose worst service health equals the value' do
        healthy = environment_with_service_healths(:healthy, :unknown)
        degraded = environment_with_service_healths(:healthy, :degraded)
        failed = environment_with_service_healths(:degraded, :failed)

        expect(described_class.with_worst_health('healthy', organization: organization)).to contain_exactly(healthy)
        expect(described_class.with_worst_health('degraded', organization: organization)).to contain_exactly(degraded)
        expect(described_class.with_worst_health('failed', organization: organization)).to contain_exactly(failed)
      end

      it 'accepts a list of healths' do
        degraded = environment_with_service_healths(:degraded)
        failed = environment_with_service_healths(:degraded, :failed)

        expect(described_class.with_worst_health(%w[degraded failed], organization: organization))
          .to contain_exactly(degraded, failed)
      end

      it 'ignores environments with no reported health' do
        environment_with_service_healths

        expect(described_class.with_worst_health('healthy', organization: organization)).to be_empty
      end

      it 'ignores health reported in another organization' do
        other_organization = create(:organization)
        other_environment = create(:cd_environment, organization: other_organization)
        create(:cd_service_environment_health,
          service: create(:cd_service, application: create(:cd_application, organization: other_organization)),
          environment: other_environment, health: :healthy)

        expect(described_class.with_worst_health('healthy', organization: organization)).to be_empty
      end
    end

    describe '.deploying' do
      let_it_be(:organization) { create(:organization) }

      def rollout_environment_for(environment, state:)
        rollout = create(:cd_rollout, version_set: create(:cd_version_set,
          application: create(:cd_application, organization: environment.organization)))
        create(:cd_rollout_environment, rollout: rollout, environment: environment, state: state)
      end

      it 'matches only environments with a rollout environment in progress' do
        deploying_environment = create(:cd_environment, organization: organization)
        pending_environment = create(:cd_environment, organization: organization)
        completed_environment = create(:cd_environment, organization: organization)

        rollout_environment_for(deploying_environment, state: :in_progress)
        rollout_environment_for(pending_environment, state: :pending)
        rollout_environment_for(completed_environment, state: :completed)

        expect(described_class.deploying(organization: organization)).to contain_exactly(deploying_environment)
      end

      it 'ignores in-progress rollout environments in another organization' do
        other_organization = create(:organization)
        other_environment = create(:cd_environment, organization: other_organization)
        rollout_environment_for(other_environment, state: :in_progress)

        expect(described_class.deploying(organization: organization)).to be_empty
      end
    end

    describe '.with_status' do
      let_it_be(:organization) { create(:organization) }
      let_it_be(:healthy_environment) { environment_with_health(:healthy) }
      let_it_be(:degraded_environment) { environment_with_health(:degraded) }
      let_it_be(:failed_environment) { environment_with_health(:failed) }

      let_it_be(:deploying_environment) do
        environment = create(:cd_environment, organization: organization)
        rollout = create(:cd_rollout, version_set: create(:cd_version_set,
          application: create(:cd_application, organization: organization)))
        create(:cd_rollout_environment, rollout: rollout, environment: environment, state: :in_progress)
        environment
      end

      def environment_with_health(health)
        environment = create(:cd_environment, organization: organization)
        create(:cd_service_environment_health,
          service: create(:cd_service, application: create(:cd_application, organization: organization)),
          environment: environment, health: health)
        environment
      end

      it 'returns environments matching the status' do
        expect(described_class.with_status('healthy', organization: organization))
          .to contain_exactly(healthy_environment)
        expect(described_class.with_status('deploying', organization: organization))
          .to contain_exactly(deploying_environment)
      end

      it 'matches environments whose worst health is failed under degraded' do
        expect(described_class.with_status('degraded', organization: organization))
          .to contain_exactly(degraded_environment, failed_environment)
      end

      # Guards against future enum values that have no scope backing yet
      # (like the applications' awaiting_approval).
      it 'returns none for an unbacked status' do
        expect(described_class.with_status('unbacked', organization: organization)).to be_empty
      end

      it 'ignores matches belonging to another organization' do
        other_organization = create(:organization)

        expect(described_class.with_status('degraded', organization: other_organization)).to be_empty
      end
    end

    describe '.search' do
      let_it_be(:organization) { create(:organization) }
      let_it_be(:prod) do
        create(:cd_environment, organization: organization, name: 'prod-eu-west-1',
          description: 'EU production cluster')
      end

      let_it_be(:staging) do
        create(:cd_environment, organization: organization, name: 'staging-us-east-1', description: 'US staging')
      end

      it 'matches on name' do
        expect(described_class.in_organization(organization).search('prod')).to contain_exactly(prod)
      end

      it 'matches on description' do
        expect(described_class.in_organization(organization).search('cluster')).to contain_exactly(prod)
      end
    end

    describe '.for_application' do
      let_it_be(:organization) { create(:organization) }
      let_it_be(:application) { create(:cd_application, organization: organization) }
      let_it_be(:other_application) { create(:cd_application, organization: organization) }
      let_it_be(:app_environment) { create(:cd_environment, organization: organization) }
      let_it_be(:other_app_environment) { create(:cd_environment, organization: organization) }
      let_it_be(:empty_environment) { create(:cd_environment, organization: organization) }

      before_all do
        # Two services of the same application in the same environment: the
        # scope must still return that environment only once.
        create(:cd_service_environment_health, service: create(:cd_service, application: application),
          environment: app_environment)
        create(:cd_service_environment_health, service: create(:cd_service, application: application),
          environment: app_environment)

        create(:cd_service_environment_health, service: create(:cd_service, application: other_application),
          environment: other_app_environment)
      end

      it 'returns each environment where the application has services deployed exactly once' do
        expect(described_class.for_application(application.id)).to contain_exactly(app_environment)
      end

      it 'returns nothing for a nonexistent application' do
        expect(described_class.for_application(non_existing_record_id)).to be_empty
      end
    end
  end
end
