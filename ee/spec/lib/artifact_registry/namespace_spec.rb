# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ArtifactRegistry::Namespace, feature_category: :artifact_registry do
  let(:attributes) do
    {
      'id' => 'f81d4fae-7dec-11d0-a765-00a0c91e6bf6',
      'slug' => 'acme',
      'platform' => 'gitlab',
      'entity_type' => 'organization',
      'entity_id' => '42',
      'status' => 'active',
      'created_at' => '2026-07-01T10:00:00Z'
    }
  end

  subject(:namespace) { described_class.new(attributes) }

  describe 'documented readers' do
    it 'exposes every documented field from the parsed response hash', :aggregate_failures do
      expect(namespace.id).to eq('f81d4fae-7dec-11d0-a765-00a0c91e6bf6')
      expect(namespace.slug).to eq('acme')
      expect(namespace.platform).to eq('gitlab')
      expect(namespace.entity_type).to eq('organization')
      expect(namespace.entity_id).to eq('42')
      expect(namespace.status).to eq('active')
      expect(namespace.created_at).to eq(DateTime.iso8601('2026-07-01T10:00:00Z'))
    end
  end

  describe '#status' do
    context 'when the value is not a recognized status' do
      let(:attributes) { super().merge('status' => 'future_unknown_state') }

      it 'passes it through raw and unvalidated' do
        expect(namespace.status).to eq('future_unknown_state')
      end
    end
  end

  describe 'unknown-field tolerance' do
    let(:attributes) { super().merge('newly_added_ar_field' => 'ignored', 'nested_future' => { 'x' => 1 }) }

    it 'still exposes every documented field and defines no reader for undocumented keys', :aggregate_failures do
      expect(namespace.id).to eq('f81d4fae-7dec-11d0-a765-00a0c91e6bf6')
      expect(namespace.slug).to eq('acme')
      expect(namespace.platform).to eq('gitlab')
      expect(namespace.entity_type).to eq('organization')
      expect(namespace.entity_id).to eq('42')
      expect(namespace.status).to eq('active')
      expect(namespace.created_at).to eq(DateTime.iso8601('2026-07-01T10:00:00Z'))
      expect(namespace).not_to respond_to(:newly_added_ar_field)
    end
  end

  describe '#created_at coercion' do
    context 'with a valid ISO8601 timestamp' do
      it 'coerces to a DateTime' do
        expect(namespace.created_at).to be_a(DateTime)
      end
    end

    context 'when absent' do
      let(:attributes) { super().except('created_at') }

      it 'returns nil' do
        expect(namespace.created_at).to be_nil
      end
    end

    context 'when not parseable' do
      let(:attributes) { super().merge('created_at' => 'not-a-timestamp') }

      it 'returns nil rather than raising' do
        expect(namespace.created_at).to be_nil
      end
    end

    context 'when not a string' do
      let(:attributes) { super().merge('created_at' => 12345) }

      it 'returns nil rather than raising' do
        expect(namespace.created_at).to be_nil
      end
    end
  end

  describe 'when constructed with nil attributes' do
    subject(:namespace) { described_class.new(nil) }

    it 'treats it as an empty resource without raising', :aggregate_failures do
      expect(namespace.id).to be_nil
      expect(namespace.status).to be_nil
      expect(namespace.created_at).to be_nil
    end
  end
end
