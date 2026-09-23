# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::ServiceEnvironmentHealth, feature_category: :continuous_delivery do
  let_it_be(:application) { create(:cd_application) }
  let_it_be(:service) { create(:cd_service, application: application) }
  let_it_be(:environment) { create(:cd_environment) }

  describe 'factory' do
    it 'creates a valid service environment health using factory defaults' do
      expect(create(:cd_service_environment_health)).to be_valid
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:service).required }
    it { is_expected.to belong_to(:environment).required }
    it { is_expected.to belong_to(:organization).required }
  end

  describe 'enums' do
    it 'defines health enum' do
      is_expected.to define_enum_for(:health).with_values(
        unknown: 0,
        healthy: 1,
        degraded: 2,
        failed: 3
      )
    end
  end

  describe '.record_deployment!' do
    let_it_be(:rollout_environment) { create(:cd_rollout_environment, environment: environment) }

    let(:deployment) do
      create(:cd_deployment, service: service, rollout_environment: rollout_environment,
        state: :healthy, finished_at: 1.hour.ago)
    end

    it 'creates a row mirroring the deployment outcome' do
      expect { described_class.record_deployment!(deployment) }.to change { described_class.count }.by(1)

      health = described_class.find_by!(service: service, environment: environment)
      expect(health).to have_attributes(health: 'healthy', organization_id: service.organization_id)
      expect(health.observed_at).to be_like_time(deployment.finished_at)
    end

    it 'maps a degraded deployment to degraded health' do
      deployment.update_column(:state, ::Cd::Deployment.states['degraded'])

      described_class.record_deployment!(deployment)

      expect(described_class.find_by!(service: service, environment: environment)).to be_degraded
    end

    it 'overwrites the existing row for the same service and environment' do
      existing = create(:cd_service_environment_health, service: service, environment: environment,
        health: :failed, observed_at: 2.days.ago)
      original_created_at = existing.created_at

      expect { described_class.record_deployment!(deployment) }.not_to change { described_class.count }

      existing.reload
      expect(existing).to be_healthy
      expect(existing.observed_at).to be_like_time(deployment.finished_at)
      expect(existing.created_at).to be_like_time(original_created_at)
    end
  end

  describe 'validations' do
    subject { build(:cd_service_environment_health, service: service, environment: environment) }

    it { is_expected.to be_valid }
    it { is_expected.to validate_presence_of(:observed_at) }

    it 'rejects a second health row for the same service and environment' do
      create(:cd_service_environment_health, service: service, environment: environment)

      duplicate = build(:cd_service_environment_health, service: service, environment: environment)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:environment_id]).to be_present
    end
  end

  describe 'sharding key' do
    subject { build(:cd_service_environment_health, service: service, environment: environment) }

    it { is_expected.to populate_sharding_key(:organization_id).with(service.organization_id) }
  end

  describe 'HEALTH_SEVERITY_ORDER' do
    it 'assigns a severity rank to every known health value' do
      expect(described_class::HEALTH_SEVERITY_ORDER).to match_array(described_class.healths.keys)
    end
  end

  describe '.in_organization' do
    it 'returns health records belonging to the organization' do
      health = create(:cd_service_environment_health, service: service, environment: environment)
      create(:cd_service_environment_health)

      expect(described_class.in_organization(service.organization)).to contain_exactly(health)
    end
  end

  describe '.ordered_by_severity' do
    it 'orders failed, degraded, healthy, unknown from worst to best' do
      healthy_env = create(:cd_environment, organization: application.organization)
      degraded_env = create(:cd_environment, organization: application.organization)
      failed_env = create(:cd_environment, organization: application.organization)
      unknown_env = create(:cd_environment, organization: application.organization)

      healthy = create(:cd_service_environment_health, service: service, environment: healthy_env, health: :healthy)
      degraded = create(:cd_service_environment_health, service: service, environment: degraded_env,
        health: :degraded)
      failed = create(:cd_service_environment_health, service: service, environment: failed_env, health: :failed)
      unknown = create(:cd_service_environment_health, service: service, environment: unknown_env, health: :unknown)

      expect(described_class.where(service: service).ordered_by_severity)
        .to eq([failed, degraded, healthy, unknown])
    end

    context 'when a row has a health value not present in HEALTH_SEVERITY_ORDER' do
      it 'sorts it after all known values' do
        stub_const('Cd::ServiceEnvironmentHealth::HEALTH_SEVERITY_ORDER', %w[failed])

        failed_env = create(:cd_environment, organization: application.organization)
        healthy_env = create(:cd_environment, organization: application.organization)

        failed = create(:cd_service_environment_health, service: service, environment: failed_env, health: :failed)
        healthy = create(:cd_service_environment_health, service: service, environment: healthy_env,
          health: :healthy)

        expect(described_class.where(service: service).ordered_by_severity).to eq([failed, healthy])
      end
    end
  end

  describe '.for_application' do
    it 'returns health records for services of the given applications' do
      health = create(:cd_service_environment_health, service: service, environment: environment)
      create(:cd_service_environment_health)

      expect(described_class.for_application(application)).to contain_exactly(health)
    end
  end

  describe '.worst_per_application' do
    let_it_be(:other_application) { create(:cd_application) }

    def report_health(target_service, health)
      create(:cd_service_environment_health,
        service: target_service,
        environment: create(:cd_environment, organization: target_service.organization),
        health: health)
    end

    it 'returns the worst health record for each application' do
      report_health(service, :healthy)
      worst = report_health(create(:cd_service, application: application), :degraded)
      other_worst = report_health(create(:cd_service, application: other_application), :failed)

      result = described_class.for_application([application.id, other_application.id]).worst_per_application

      expect(result).to contain_exactly(worst, other_worst)
      expect(result.map(&:application_id)).to contain_exactly(application.id, other_application.id)
    end

    it 'omits applications with no reported health' do
      expect(described_class.for_application([application.id]).worst_per_application).to be_empty
    end

    context 'with unknown health' do
      it 'does not let unknown override a known health signal' do
        healthy = report_health(service, :healthy)
        report_health(create(:cd_service, application: application), :unknown)

        expect(described_class.for_application([application.id]).worst_per_application)
          .to contain_exactly(healthy)
      end

      it 'rolls up to unknown only when every service is unknown' do
        report_health(service, :unknown)
        report_health(create(:cd_service, application: application), :unknown)

        expect(described_class.for_application([application.id]).worst_per_application.map(&:health))
          .to eq(['unknown'])
      end
    end
  end

  describe '.application_ids_with_worst_health' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:other_organization) { create(:organization) }
    let_it_be(:healthy_application) { create(:cd_application, organization: organization) }
    let_it_be(:mixed_application) { create(:cd_application, organization: organization) }
    let_it_be(:other_org_application) { create(:cd_application, organization: other_organization) }

    before_all do
      org_environment = create(:cd_environment, organization: organization)
      create(:cd_service_environment_health, environment: org_environment, health: :healthy,
        service: create(:cd_service, application: healthy_application))
      create(:cd_service_environment_health, environment: org_environment, health: :degraded,
        service: create(:cd_service, application: mixed_application))
      create(:cd_service_environment_health, environment: org_environment, health: :failed,
        service: create(:cd_service, application: mixed_application))
      create(:cd_service_environment_health, health: :healthy,
        environment: create(:cd_environment, organization: other_organization),
        service: create(:cd_service, application: other_org_application))
    end

    it 'returns ids of applications whose worst health matches' do
      result = described_class.application_ids_with_worst_health('failed', organization: organization)

      expect(result.map(&:application_id)).to contain_exactly(mixed_application.id)
    end

    it 'does not match a health that is not the worst for the application' do
      result = described_class.application_ids_with_worst_health('degraded', organization: organization)

      expect(result.map(&:application_id)).to be_empty
    end

    it 'accepts a list of healths' do
      result = described_class.application_ids_with_worst_health(%w[degraded failed], organization: organization)

      expect(result.map(&:application_id)).to contain_exactly(mixed_application.id)
    end

    it 'excludes applications from other organizations' do
      result = described_class.application_ids_with_worst_health('healthy', organization: other_organization)

      expect(result.map(&:application_id)).to contain_exactly(other_org_application.id)
    end
  end

  describe '.environment_ids_with_worst_health' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:other_organization) { create(:organization) }
    let_it_be(:healthy_environment) { create(:cd_environment, organization: organization) }
    let_it_be(:mixed_environment) { create(:cd_environment, organization: organization) }
    let_it_be(:other_org_environment) { create(:cd_environment, organization: other_organization) }

    before_all do
      create(:cd_service_environment_health, environment: healthy_environment, health: :healthy,
        service: create(:cd_service, application: create(:cd_application, organization: organization)))
      create(:cd_service_environment_health, environment: mixed_environment, health: :degraded,
        service: create(:cd_service, application: create(:cd_application, organization: organization)))
      create(:cd_service_environment_health, environment: mixed_environment, health: :failed,
        service: create(:cd_service, application: create(:cd_application, organization: organization)))
      create(:cd_service_environment_health, environment: other_org_environment, health: :healthy,
        service: create(:cd_service, application: create(:cd_application, organization: other_organization)))
    end

    it 'returns ids of environments whose worst health matches' do
      result = described_class.environment_ids_with_worst_health('failed', organization: organization)

      expect(result.map(&:environment_id)).to contain_exactly(mixed_environment.id)
    end

    it 'does not match a health that is not the worst for the environment' do
      result = described_class.environment_ids_with_worst_health('degraded', organization: organization)

      expect(result.map(&:environment_id)).to be_empty
    end

    it 'accepts a list of healths' do
      result = described_class.environment_ids_with_worst_health(%w[degraded failed], organization: organization)

      expect(result.map(&:environment_id)).to contain_exactly(mixed_environment.id)
    end

    it 'excludes environments from other organizations' do
      result = described_class.environment_ids_with_worst_health('healthy', organization: other_organization)

      expect(result.map(&:environment_id)).to contain_exactly(other_org_environment.id)
    end
  end

  describe '.for_environment' do
    it 'returns health records for the given environments' do
      health = create(:cd_service_environment_health, service: service, environment: environment)
      create(:cd_service_environment_health)

      expect(described_class.for_environment(environment)).to contain_exactly(health)
    end
  end

  describe '.worst_per_environment' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:environment_a) { create(:cd_environment, organization: organization) }
    let_it_be(:environment_b) { create(:cd_environment, organization: organization) }
    let_it_be(:empty_environment) { create(:cd_environment, organization: organization) }

    def report_health(target_environment, health)
      create(:cd_service_environment_health,
        environment: target_environment,
        health: health,
        service: create(:cd_service, application: create(:cd_application, organization: organization)))
    end

    it 'returns the worst health record for each environment' do
      report_health(environment_a, :healthy)
      worst_a = report_health(environment_a, :degraded)
      worst_b = report_health(environment_b, :failed)

      expect(described_class.for_environment([environment_a.id, environment_b.id]).worst_per_environment)
        .to contain_exactly(worst_a, worst_b)
    end

    it 'omits environments with no reported health' do
      expect(described_class.for_environment([empty_environment.id]).worst_per_environment).to be_empty
    end

    context 'with unknown health' do
      it 'does not let unknown override a known health signal' do
        healthy = report_health(environment_a, :healthy)
        report_health(environment_a, :unknown)

        expect(described_class.for_environment([environment_a.id]).worst_per_environment).to contain_exactly(healthy)
      end

      it 'rolls up to unknown only when every service is unknown' do
        report_health(environment_a, :unknown)
        report_health(environment_a, :unknown)

        expect(described_class.for_environment([environment_a.id]).worst_per_environment.map(&:health))
          .to eq(['unknown'])
      end
    end
  end

  describe '.applications_count_by_environment' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:environment_a) { create(:cd_environment, organization: organization) }
    let_it_be(:environment_b) { create(:cd_environment, organization: organization) }
    let_it_be(:empty_environment) { create(:cd_environment, organization: organization) }
    let_it_be(:app1) { create(:cd_application, organization: organization) }
    let_it_be(:app2) { create(:cd_application, organization: organization) }

    before_all do
      create(:cd_service_environment_health, service: create(:cd_service, application: app1),
        environment: environment_a)
      create(:cd_service_environment_health, service: create(:cd_service, application: app1),
        environment: environment_a)
      create(:cd_service_environment_health, service: create(:cd_service, application: app2),
        environment: environment_a)

      create(:cd_service_environment_health, service: create(:cd_service, application: app1),
        environment: environment_b)
    end

    it 'returns the distinct application count per environment, keyed by environment id' do
      result = described_class.applications_count_by_environment(
        [environment_a.id, environment_b.id, empty_environment.id]
      )

      expect(result).to eq(environment_a.id => 2, environment_b.id => 1)
    end

    it 'omits environments with no services' do
      expect(described_class.applications_count_by_environment([empty_environment.id])).to eq({})
    end
  end

  describe '.environment_ids_for_application' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:application) { create(:cd_application, organization: organization) }
    let_it_be(:other_application) { create(:cd_application, organization: organization) }
    let_it_be(:environment_a) { create(:cd_environment, organization: organization) }
    let_it_be(:environment_b) { create(:cd_environment, organization: organization) }
    let_it_be(:other_app_environment) { create(:cd_environment, organization: organization) }

    before_all do
      create(:cd_service_environment_health, service: create(:cd_service, application: application),
        environment: environment_a)
      create(:cd_service_environment_health, service: create(:cd_service, application: application),
        environment: environment_b)

      create(:cd_service_environment_health, service: create(:cd_service, application: other_application),
        environment: other_app_environment)
    end

    it 'returns environment ids where any of the application services has reported health' do
      result = described_class.environment_ids_for_application(application.id)

      expect(result.map(&:environment_id)).to contain_exactly(environment_a.id, environment_b.id)
    end

    it 'returns nothing for an application with no reported health' do
      idle_application = create(:cd_application, organization: organization)

      expect(described_class.environment_ids_for_application(idle_application.id)).to be_empty
    end

    it 'returns nothing for a nonexistent application' do
      expect(described_class.environment_ids_for_application(non_existing_record_id)).to be_empty
    end
  end

  describe '.service_environment_healths_by_application' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:environment) { create(:cd_environment, organization: organization) }
    let_it_be(:other_environment) { create(:cd_environment, organization: organization) }
    let_it_be(:empty_environment) { create(:cd_environment, organization: organization) }
    let_it_be(:zebra_app) { create(:cd_application, organization: organization, name: 'zebra') }
    let_it_be(:alpha_app) { create(:cd_application, organization: organization, name: 'alpha') }
    let_it_be(:alpha_api) { create(:cd_service, application: alpha_app, name: 'api') }
    let_it_be(:alpha_worker) { create(:cd_service, application: alpha_app, name: 'worker') }
    let_it_be(:zebra_web) { create(:cd_service, application: zebra_app, name: 'web') }

    before_all do
      create(:cd_service_environment_health, service: alpha_worker, environment: environment)
      create(:cd_service_environment_health, service: alpha_api, environment: environment)
      create(:cd_service_environment_health, service: zebra_web, environment: environment)

      # A service of alpha_app in a different environment must not appear here.
      create(:cd_service_environment_health, service: create(:cd_service, application: alpha_app),
        environment: other_environment)
    end

    it 'returns health rows grouped by application, ordered by application then service name' do
      result = described_class.service_environment_healths_by_application(environment)

      expect(result.keys).to eq([alpha_app.id, zebra_app.id])
      expect(result[alpha_app.id].map(&:service)).to eq([alpha_api, alpha_worker])
      expect(result[zebra_app.id].map(&:service)).to eq([zebra_web])
    end

    it 'returns an empty hash for an environment with no services' do
      expect(described_class.service_environment_healths_by_application(empty_environment)).to eq({})
    end
  end

  describe '.services_count_by_environment' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:environment_a) { create(:cd_environment, organization: organization) }
    let_it_be(:environment_b) { create(:cd_environment, organization: organization) }
    let_it_be(:empty_environment) { create(:cd_environment, organization: organization) }
    let_it_be(:app1) { create(:cd_application, organization: organization) }
    let_it_be(:app2) { create(:cd_application, organization: organization) }

    before_all do
      create(:cd_service_environment_health, service: create(:cd_service, application: app1),
        environment: environment_a)
      create(:cd_service_environment_health, service: create(:cd_service, application: app1),
        environment: environment_a)
      create(:cd_service_environment_health, service: create(:cd_service, application: app2),
        environment: environment_a)

      create(:cd_service_environment_health, service: create(:cd_service, application: app1),
        environment: environment_b)
    end

    it 'returns the service count per environment, keyed by environment id' do
      result = described_class.services_count_by_environment(
        [environment_a.id, environment_b.id, empty_environment.id]
      )

      expect(result).to eq(environment_a.id => 3, environment_b.id => 1)
    end

    it 'omits environments with no services' do
      expect(described_class.services_count_by_environment([empty_environment.id])).to eq({})
    end
  end
end
