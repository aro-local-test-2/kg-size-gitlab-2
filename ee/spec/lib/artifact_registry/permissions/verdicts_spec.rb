# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ArtifactRegistry::Permissions::Verdicts, feature_category: :artifact_registry do
  let(:slug) { 'my-group' }

  describe 'the transcribed action sets' do
    it 'names the NamespacePermissions required actions of api/openapi/v1.yaml' do
      expect(described_class::NAMESPACE_ACTIONS).to eq(%w[
        read_repository
        create_repository
        update_repository
        delete_repository
        create_repository_upstream
        update_repository_upstream
        delete_repository_upstream
      ])
    end

    it 'names the RepositoryPermissions required actions of api/openapi/v1.yaml' do
      expect(described_class::REPOSITORY_ACTIONS).to eq(%w[
        read_repository
        update_repository
        delete_repository
        create_repository_upstream
        update_repository_upstream
        delete_repository_upstream
        read_artifact
        create_artifact
        delete_artifact
      ])
    end
  end

  describe '.new' do
    let(:attributes) { described_class::REPOSITORY_ACTIONS.index_with(true).merge('delete_repository' => false) }

    subject(:verdicts) { described_class.new(attributes, scope: :repository, read: :repository, slug: slug) }

    it 'answers each action from the served object and carries its provenance', :aggregate_failures do
      expect(verdicts.allowed?('update_repository')).to be(true)
      expect(verdicts.allowed?('delete_repository')).to be(false)
      expect(verdicts.allowed?(:read_artifact)).to be(true)
      expect(verdicts).to be_complete
      expect(verdicts).not_to be_absent
      expect(verdicts.missing_actions).to eq([])
      expect(verdicts.scope).to eq(:repository)
      expect(verdicts.read).to eq(:repository)
      expect(verdicts.slug).to eq(slug)
    end

    it 'raises for a scope without a declared action set' do
      expect { described_class.new(attributes, scope: :image, read: :repository, slug: slug) }
        .to raise_error(KeyError)
    end

    context 'when the object carries an action the set does not name' do
      let(:attributes) { super().merge('publish_repository' => true) }

      it 'drops the extra without raising and stays complete', :aggregate_failures do
        expect(verdicts.allowed?('publish_repository')).to be(false)
        expect(verdicts).to be_complete
      end
    end

    context 'when the object lacks an action of the set' do
      let(:attributes) { super().except('delete_artifact', 'read_artifact') }

      it 'is incomplete, names the missing actions, and still answers the present ones', :aggregate_failures do
        expect(verdicts).not_to be_complete
        expect(verdicts.missing_actions).to eq(%w[read_artifact delete_artifact])
        expect(verdicts.allowed?('delete_artifact')).to be(false)
        expect(verdicts.allowed?('update_repository')).to be(true)
      end
    end

    context 'when a verdict is not the boolean true' do
      let(:attributes) { super().merge('update_repository' => 'true', 'read_artifact' => 1, 'create_artifact' => nil) }

      it 'allows only an explicit true', :aggregate_failures do
        expect(verdicts.allowed?('update_repository')).to be(false)
        expect(verdicts.allowed?('read_artifact')).to be(false)
        expect(verdicts.allowed?('create_artifact')).to be(false)
      end
    end

    context 'when the object is empty' do
      let(:attributes) { {} }

      it 'is incomplete and denies every action, but is not absent', :aggregate_failures do
        expect(verdicts).not_to be_complete
        expect(verdicts).not_to be_absent
        expect(verdicts.missing_actions).to eq(described_class::REPOSITORY_ACTIONS)
      end
    end

    describe 'the set each scope completes against' do
      let(:namespace_object) { described_class::NAMESPACE_ACTIONS.index_with(true) }

      it 'completes a namespace object against the namespace set only', :aggregate_failures do
        as_namespace = described_class.new(namespace_object, scope: :namespace, read: :repositories, slug: slug)
        as_repository = described_class.new(namespace_object, scope: :repository, read: :repositories, slug: slug)

        expect(as_namespace).to be_complete
        expect(as_namespace.allowed?('create_repository')).to be(true)
        expect(as_repository).not_to be_complete
        expect(as_repository.missing_actions).to eq(%w[read_artifact create_artifact delete_artifact])
        expect(as_repository.allowed?('create_repository')).to be(false)
      end
    end
  end

  describe '.absent' do
    subject(:verdicts) { described_class.absent(scope: :namespace, read: :repositories, slug: slug) }

    it 'marks a requested but unserved object that denies everything', :aggregate_failures do
      expect(verdicts).to be_absent
      expect(verdicts).not_to be_complete
      expect(verdicts.missing_actions).to eq(described_class::NAMESPACE_ACTIONS)
      expect(described_class::NAMESPACE_ACTIONS.map { |action| verdicts.allowed?(action) }).to all(be(false))
      expect(verdicts.scope).to eq(:namespace)
      expect(verdicts.read).to eq(:repositories)
      expect(verdicts.slug).to eq(slug)
    end
  end
end
