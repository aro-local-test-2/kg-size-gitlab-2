# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ArtifactRegistry::Repository, feature_category: :artifact_registry do
  let(:attributes) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => 'my-repo',
      'format' => 'maven',
      'kind' => 'hosted',
      'visibility' => 'private',
      'description' => 'A hosted Maven repository',
      'artifacts_count' => 12,
      'downloads_count' => 340,
      'size_bytes' => 987_654,
      'created_at' => '2026-07-01T10:00:00Z',
      'last_updated_at' => '2026-07-02T11:30:00Z',
      'created_by' => '101',
      'updated_by' => '202',
      'settings' => { 'immutable_tags' => true }
    }
  end

  subject(:repository) { described_class.new(attributes) }

  describe 'documented readers' do
    it 'exposes every documented field from the parsed response hash', :aggregate_failures do
      expect(repository.id).to eq('a1b2c3d4-0000-0000-0000-000000000000')
      expect(repository.name).to eq('my-repo')
      expect(repository.format).to eq('maven')
      expect(repository.kind).to eq('hosted')
      expect(repository.visibility).to eq('private')
      expect(repository.description).to eq('A hosted Maven repository')
      expect(repository.artifacts_count).to eq(12)
      expect(repository.downloads_count).to eq(340)
      expect(repository.size_bytes).to eq(987_654)
      expect(repository.created_at).to eq(DateTime.iso8601('2026-07-01T10:00:00Z'))
      expect(repository.last_updated_at).to eq(DateTime.iso8601('2026-07-02T11:30:00Z'))
      expect(repository.created_by).to eq('101')
      expect(repository.updated_by).to eq('202')
      expect(repository.settings).to eq({ 'immutable_tags' => true })
    end
  end

  describe 'unknown-field tolerance' do
    let(:attributes) { super().merge('newly_added_ar_field' => 'ignored', 'nested_future' => { 'x' => 1 }) }

    it 'still exposes every documented field and defines no reader for undocumented keys', :aggregate_failures do
      expect(repository.name).to eq('my-repo')
      expect(repository.format).to eq('maven')
      expect(repository).not_to respond_to(:newly_added_ar_field)
    end
  end

  describe 'absent optional fields' do
    let(:attributes) { { 'name' => 'bare-repo' } }

    it 'returns nil for absent documented fields without raising', :aggregate_failures do
      expect(repository.name).to eq('bare-repo')
      expect(repository.description).to be_nil
      expect(repository.last_updated_at).to be_nil
      expect(repository.created_by).to be_nil
      expect(repository.updated_by).to be_nil
    end

    it 'exposes settings as an empty Hash when the response omits it' do
      expect(repository.settings).to eq({})
    end

    it 'exposes settings as an empty Hash when the response sends something other than an object' do
      expect(described_class.new('settings' => 'not-an-object').settings).to eq({})
    end
  end

  describe 'timestamp coercion' do
    it 'coerces valid ISO8601 timestamps to DateTime for both readers', :aggregate_failures do
      expect(repository.created_at).to eq(DateTime.iso8601('2026-07-01T10:00:00Z'))
      expect(repository.last_updated_at).to eq(DateTime.iso8601('2026-07-02T11:30:00Z'))
    end

    context 'when the timestamps are nil' do
      let(:attributes) { super().merge('created_at' => nil, 'last_updated_at' => nil) }

      it 'returns nil for both readers', :aggregate_failures do
        expect(repository.created_at).to be_nil
        expect(repository.last_updated_at).to be_nil
      end
    end

    context 'when the timestamps are not parseable' do
      let(:attributes) { super().merge('created_at' => 'not-a-timestamp', 'last_updated_at' => 'also-not-one') }

      it 'returns nil for both readers rather than raising', :aggregate_failures do
        expect(repository.created_at).to be_nil
        expect(repository.last_updated_at).to be_nil
      end
    end

    context 'when the timestamps are not strings' do
      let(:attributes) { super().merge('created_at' => 12345, 'last_updated_at' => 67890) }

      it 'returns nil for both readers rather than raising', :aggregate_failures do
        expect(repository.created_at).to be_nil
        expect(repository.last_updated_at).to be_nil
      end
    end
  end

  describe 'when constructed with nil attributes' do
    subject(:repository) { described_class.new(nil) }

    it 'treats it as an empty resource without raising', :aggregate_failures do
      expect(repository.name).to be_nil
      expect(repository.settings).to eq({})
    end
  end

  describe '#permissions' do
    it 'is nil when the client hands none in, even if the response carried a permissions object' do
      expect(described_class.new(attributes.merge('permissions' => { 'update_repository' => true })).permissions)
        .to be_nil
    end

    it 'exposes the verdicts the client hands in' do
      verdicts = ArtifactRegistry::Permissions::Verdicts.absent(scope: :repository, read: :repository, slug: 'grp')

      expect(described_class.new(attributes, verdicts).permissions).to be(verdicts)
    end
  end

  describe 'format predicates' do
    using RSpec::Parameterized::TableSyntax

    where(:format, :packages, :images, :npm) do
      'maven'   | true  | false | false
      'npm'     | true  | false | true
      'docker'  | false | true  | false
      'oci'     | false | true  | false
      'unknown' | false | false | false
      nil       | false | false | false
    end

    with_them do
      subject(:repository) { described_class.new('format' => format) }

      it 'reports the artifact family the format backs', :aggregate_failures do
        expect(repository.packages?).to be(packages)
        expect(repository.images?).to be(images)
        expect(repository.npm?).to be(npm)
      end
    end
  end

  describe 'kind predicates' do
    using RSpec::Parameterized::TableSyntax

    where(:kind, :hosted, :remote, :virtual) do
      'hosted'  | true  | false | false
      'remote'  | false | true  | false
      'virtual' | false | false | true
      'unknown' | false | false | false
      nil       | false | false | false
    end

    with_them do
      subject(:repository) { described_class.new('kind' => kind) }

      it 'reports true for exactly its own kind', :aggregate_failures do
        expect(repository.hosted?).to be(hosted)
        expect(repository.remote?).to be(remote)
        expect(repository.virtual?).to be(virtual)
      end
    end
  end
end
