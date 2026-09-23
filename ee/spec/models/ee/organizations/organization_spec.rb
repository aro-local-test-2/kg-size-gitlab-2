# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Organizations::Organization, feature_category: :organization do
  let_it_be_with_reload(:organization) { create(:organization) }
  let_it_be(:project) { create(:project, organization: organization) }

  describe 'associations' do
    it { is_expected.to have_many(:vulnerability_exports).class_name('Vulnerabilities::Export') }
    it { is_expected.to have_many(:sbom_sources).class_name('Sbom::Source') }
    it { is_expected.to have_many(:sbom_source_packages).class_name('Sbom::SourcePackage') }
    it { is_expected.to have_many(:sbom_components).class_name('Sbom::Component') }
    it { is_expected.to have_many(:sbom_component_versions).class_name('Sbom::ComponentVersion') }

    it 'has one artifact_registry_namespace_mapping' do
      is_expected.to have_one(:artifact_registry_namespace_mapping)
        .class_name('ArtifactRegistry::NamespaceMapping').inverse_of(:organization)
    end
  end

  describe '#artifact_registry_activated?' do
    subject { organization.artifact_registry_activated? }

    context 'when the organization has a namespace mapping' do
      before do
        create(:artifact_registry_namespace_mapping, organization: organization)
      end

      it { is_expected.to be(true) }
    end

    context 'when the organization has no namespace mapping' do
      it { is_expected.to be(false) }
    end
  end

  describe '#artifact_registry_resolved_slug' do
    subject(:slug) { organization.artifact_registry_resolved_slug }

    context 'when the organization has a namespace mapping' do
      let_it_be(:mapping) { create(:artifact_registry_namespace_mapping, organization: organization) }

      before do
        allow(organization).to receive(:artifact_registry_namespace_mapping).and_return(mapping)
        allow(mapping).to receive(:registry).and_return(resolved)
      end

      context 'when the handle resolves' do
        let(:resolved) do
          ArtifactRegistry::NamespaceMapping::Registry.new(slug: 'acme', status: 'active', created_at: nil)
        end

        it { is_expected.to eq('acme') }
      end

      context 'when the status is unknown' do
        let(:resolved) do
          ArtifactRegistry::NamespaceMapping::Registry.new(
            slug: nil, status: ArtifactRegistry::NamespaceMapping::UNKNOWN_STATUS, created_at: nil
          )
        end

        it { is_expected.to be_nil }
      end

      context 'when the resolution failed' do
        let(:resolved) { ArtifactRegistry::NamespaceMapping::ResolutionFailure.new(error_class: 'x') }

        it { is_expected.to be_nil }
      end
    end

    context 'when the organization has no namespace mapping' do
      it 'answers nil without resolving anything against Artifact Registry' do
        expect(organization).not_to receive(:artifact_registry_service_client)

        expect(slug).to be_nil
      end
    end
  end

  describe '#policy_store_experiment_active?' do
    subject { organization.policy_store_experiment_active? }

    before do
      stub_licensed_features(security_orchestration_policies: true)
      stub_application_setting(policy_store_experiment_enabled: true)
      ::Organizations::OrganizationSetting.for(organization.id)
        .update!(policy_store_experiment_enabled: true)
    end

    it { is_expected.to be(true) }

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(security_policies_v2: false)
      end

      it { is_expected.to be(false) }
    end

    context 'when the experiment is disabled for the instance' do
      before do
        stub_application_setting(policy_store_experiment_enabled: false)
      end

      it { is_expected.to be(false) }
    end

    context 'when the license is not available' do
      before do
        stub_licensed_features(security_orchestration_policies: false)
      end

      it { is_expected.to be(false) }
    end

    context 'when the organization has not opted in' do
      before do
        ::Organizations::OrganizationSetting.for(organization.id)
          .update!(policy_store_experiment_enabled: false)
      end

      it { is_expected.to be(false) }
    end
  end

  describe '#policy_store_experiment_enabled?' do
    subject { organization.policy_store_experiment_enabled? }

    it 'is false for an organization without a settings record' do
      expect(organization.settings).to be_nil

      is_expected.to be(false)
    end

    it 'is false for a settings record written before the key existed' do
      ::Organizations::OrganizationSetting.for(organization.id)
        .update!(policy_store_experiment_enabled: true)
      organization.settings.update_column(:settings, {})
      organization.reload

      is_expected.to be(false)
    end

    it 'reflects the organization setting' do
      ::Organizations::OrganizationSetting.for(organization.id)
        .update!(policy_store_experiment_enabled: true)
      organization.reload

      is_expected.to be(true)
    end
  end

  describe 'Foundational agents settings' do
    let_it_be_with_reload(:organization) { create(:organization) }

    it_behaves_like 'settings with foundational agents statuses' do
      let_it_be(:instance) { organization }
    end

    describe '.foundational_agents_default_enabled' do
      before do
        Ai::Setting.for_organization(organization).update!(foundational_agents_default_enabled: false)
      end

      it 'returns setting value' do
        expect(organization.foundational_agents_default_enabled).to be false
      end
    end
  end
end
