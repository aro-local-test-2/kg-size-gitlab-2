# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::RepositoryPresenter, feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  let(:organization) { build_stubbed(:organization) }

  let(:attributes) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => 'maven-releases',
      'format' => 'maven',
      'kind' => 'hosted',
      'visibility' => 'private',
      'description' => 'A hosted Maven repository',
      'artifacts_count' => 12,
      'downloads_count' => 340,
      'size_bytes' => 9_876_543_210,
      'created_at' => '2026-07-01T10:00:00Z',
      'last_updated_at' => '2026-07-02T11:30:00Z',
      'created_by' => '101',
      'updated_by' => '202',
      'settings' => { 'upstream' => 'https://example.test' }
    }
  end

  let(:repository) { ArtifactRegistry::Repository.new(attributes) }

  subject(:presenter) { described_class.new(repository, organization: organization) }

  it 'carries the organization the repository was read through, which its child fields resolve against' do
    expect(presenter.organization).to be(organization)
  end

  describe 'the presented repository' do
    where(:reader, :expected) do
      :id              | 'a1b2c3d4-0000-0000-0000-000000000000'
      :name            | 'maven-releases'
      :format          | 'maven'
      :kind            | 'hosted'
      :visibility      | 'private'
      :description     | 'A hosted Maven repository'
      :artifacts_count | 12
      :downloads_count | 340
      :size_bytes      | 9_876_543_210
      :created_at      | DateTime.iso8601('2026-07-01T10:00:00Z')
      :last_updated_at | DateTime.iso8601('2026-07-02T11:30:00Z')
      :created_by      | '101'
      :updated_by      | '202'
      :settings        | { 'upstream' => 'https://example.test' }
    end

    with_them do
      it 'reads through to the value object' do
        expect(presenter.public_send(reader)).to eq(expected)
      end
    end
  end

  describe '#declarative_policy_subject' do
    it 'authorizes against the organization, not the repository' do
      expect(presenter.declarative_policy_subject).to be(organization)
    end

    # Why the method exists. Today's fields skip the ability, so nothing reaches a policy; drop
    # that skip and the inherited delegate resolves to the bare value object, which has no
    # policy class, and `class_for` raises rather than denying -- a 500, not a 403.
    it 'resolves to a policy, where the bare value object has none', :aggregate_failures do
      expect { DeclarativePolicy.class_for(repository) }
        .to raise_error(RuntimeError, /no policy for ArtifactRegistry::Repository/)

      expect(DeclarativePolicy.class_for(presenter.declarative_policy_subject))
        .to eq(::Organizations::OrganizationPolicy)
    end
  end
end
