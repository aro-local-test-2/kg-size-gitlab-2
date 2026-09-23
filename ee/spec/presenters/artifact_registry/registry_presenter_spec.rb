# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::RegistryPresenter, feature_category: :artifact_registry do
  let(:organization) { build_stubbed(:organization) }
  let(:created_at) { Time.zone.parse('2026-07-01T10:00:00Z') }

  let(:registry) do
    ArtifactRegistry::NamespaceMapping::Registry.new(slug: 'acme', status: 'active', created_at: created_at)
  end

  subject(:presenter) { described_class.new(registry, organization: organization) }

  it 'carries the organization the registry was resolved for, which the permissions block reads through' do
    expect(presenter.organization).to be(organization)
  end

  it 'requires the organization, so the permissions block cannot resolve without its context' do
    expect { described_class.new(registry) }.to raise_error(ArgumentError, /organization/)
  end

  it 'reads through to the registry struct', :aggregate_failures do
    expect(presenter.slug).to eq('acme')
    expect(presenter.status).to eq('active')
    expect(presenter.created_at).to eq(created_at)
    expect(presenter).to be_resolved
    expect(presenter.__subject__).to be(registry)
  end

  describe '#declarative_policy_subject' do
    it 'authorizes against the organization, not the registry' do
      expect(presenter.declarative_policy_subject).to be(organization)
    end

    it 'resolves to a policy, where the bare struct has none', :aggregate_failures do
      expect { DeclarativePolicy.class_for(registry) }
        .to raise_error(RuntimeError, /no policy for ArtifactRegistry::NamespaceMapping::Registry/)

      expect(DeclarativePolicy.class_for(presenter.declarative_policy_subject))
        .to eq(::Organizations::OrganizationPolicy)
    end
  end
end
