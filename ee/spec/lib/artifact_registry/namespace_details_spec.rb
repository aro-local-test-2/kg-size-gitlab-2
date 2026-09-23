# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ArtifactRegistry::NamespaceDetails, feature_category: :artifact_registry do
  let(:attributes) { { 'slug' => 'acme', 'created_at' => '2026-07-01T10:00:00Z' } }

  subject(:namespace_details) { described_class.new(attributes) }

  describe 'documented readers' do
    it 'exposes every documented field from the parsed response hash', :aggregate_failures do
      expect(namespace_details.slug).to eq('acme')
      expect(namespace_details.created_at).to eq(DateTime.iso8601('2026-07-01T10:00:00Z'))
      expect(namespace_details.permissions).to be_nil
    end
  end

  describe 'unknown-field tolerance' do
    let(:attributes) { super().merge('newly_added_ar_field' => 'ignored', 'nested_future' => { 'x' => 1 }) }

    it 'still exposes every documented field and defines no reader for undocumented keys', :aggregate_failures do
      expect(namespace_details.slug).to eq('acme')
      expect(namespace_details.created_at).to eq(DateTime.iso8601('2026-07-01T10:00:00Z'))
      expect(namespace_details).not_to respond_to(:newly_added_ar_field)
    end
  end

  describe '#created_at coercion' do
    context 'when absent' do
      let(:attributes) { super().except('created_at') }

      it 'returns nil' do
        expect(namespace_details.created_at).to be_nil
      end
    end

    context 'when not parseable' do
      let(:attributes) { super().merge('created_at' => 'not-a-timestamp') }

      it 'returns nil rather than raising' do
        expect(namespace_details.created_at).to be_nil
      end
    end

    context 'when not a string' do
      let(:attributes) { super().merge('created_at' => 12345) }

      it 'returns nil rather than raising' do
        expect(namespace_details.created_at).to be_nil
      end
    end
  end

  describe '#permissions' do
    it 'is nil when the client hands none in, even if the response carried a permissions object' do
      details = described_class.new(attributes.merge('permissions' => { 'create_repository' => true }))

      expect(details.permissions).to be_nil
    end

    it 'exposes the verdicts the client hands in' do
      verdicts = ArtifactRegistry::Permissions::Verdicts.absent(scope: :namespace, read: :namespace_details,
        slug: 'acme')

      expect(described_class.new(attributes, verdicts).permissions).to be(verdicts)
    end
  end

  describe 'when constructed with nil attributes' do
    subject(:namespace_details) { described_class.new(nil) }

    it 'treats it as an empty resource without raising', :aggregate_failures do
      expect(namespace_details.slug).to be_nil
      expect(namespace_details.created_at).to be_nil
      expect(namespace_details.permissions).to be_nil
    end
  end
end
