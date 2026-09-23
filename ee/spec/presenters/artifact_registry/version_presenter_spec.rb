# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::VersionPresenter, feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  let(:organization) { build_stubbed(:organization) }
  let(:repository) { ArtifactRegistry::Repository.new('name' => 'maven-releases', 'format' => 'maven') }

  let(:attributes) do
    {
      'id' => 'v1000000-0000-0000-0000-000000000000',
      'version' => '1.10.0',
      'created_at' => '2026-07-03T09:15:00Z',
      'size' => 9_876_543_210,
      'package_id' => 'p1000000-0000-0000-0000-000000000000',
      'created_by' => '101',
      'project_id' => '202',
      'git_commit_sha' => 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef'
    }
  end

  let(:version) { ArtifactRegistry::Version.new(attributes) }

  subject(:presenter) { described_class.new(version, repository: repository, organization: organization) }

  it 'carries the repository and organization the version was read through' do
    aggregate_failures do
      expect(presenter.repository).to be(repository)
      expect(presenter.organization).to be(organization)
    end
  end

  # The initialize override exists to pin both keywords required; without it they silently become
  # optional and a child field fails only once it reaches the client, far from the resolver.
  describe 'required construction keywords' do
    it 'requires the repository keyword' do
      expect { described_class.new(version, organization: organization) }
        .to raise_error(ArgumentError, /repository/)
    end

    it 'requires the organization keyword' do
      expect { described_class.new(version, repository: repository) }
        .to raise_error(ArgumentError, /organization/)
    end
  end

  describe 'the presented version' do
    where(:reader, :expected) do
      :id             | 'v1000000-0000-0000-0000-000000000000'
      :version        | '1.10.0'
      :created_at     | DateTime.iso8601('2026-07-03T09:15:00Z')
      :size           | 9_876_543_210
      :package_id     | 'p1000000-0000-0000-0000-000000000000'
      :created_by     | '101'
      :project_id     | '202'
      :git_commit_sha | 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef'
    end

    with_them do
      it 'reads through to the value object' do
        expect(presenter.public_send(reader)).to eq(expected)
      end
    end
  end

  describe '#declarative_policy_subject' do
    it 'authorizes against the organization, not the version' do
      expect(presenter.declarative_policy_subject).to be(organization)
    end

    # Why the method exists. Today's fields skip the ability, so nothing reaches a policy; drop
    # that skip and the inherited delegate resolves to the bare value object, which has no
    # policy class, and `class_for` raises rather than denying -- a 500, not a 403.
    it 'resolves to a policy, where the bare value object has none', :aggregate_failures do
      expect { DeclarativePolicy.class_for(version) }
        .to raise_error(RuntimeError, /no policy for ArtifactRegistry::Version/)

      expect(DeclarativePolicy.class_for(presenter.declarative_policy_subject))
        .to eq(::Organizations::OrganizationPolicy)
    end
  end
end
