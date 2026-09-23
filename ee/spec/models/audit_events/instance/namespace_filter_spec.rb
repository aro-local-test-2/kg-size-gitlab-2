# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuditEvents::Instance::NamespaceFilter, feature_category: :audit_events do
  subject(:namespace_filter) { build(:audit_events_streaming_instance_namespace_filters) }

  let_it_be(:destination) { create(:audit_events_instance_external_streaming_destination) }

  describe 'Associations' do
    it { is_expected.to belong_to(:external_streaming_destination).class_name('ExternalStreamingDestination') }
    it { is_expected.to belong_to(:namespace).inverse_of(:audit_events_streaming_instance_namespace_filters) }
  end

  describe 'Validations' do
    it { is_expected.to validate_presence_of(:namespace) }
    it { is_expected.to validate_presence_of(:external_streaming_destination) }
    it { is_expected.to validate_uniqueness_of(:namespace).scoped_to(:external_streaming_destination_id) }

    describe 'namespace filters limit' do
      let(:filter) do
        build(:audit_events_streaming_instance_namespace_filters, external_streaming_destination: destination)
      end

      before do
        create_list(:audit_events_streaming_instance_namespace_filters, 4,
          external_streaming_destination: destination)
      end

      it 'allows the fifth filter for a destination' do
        expect(filter).to be_valid
      end

      context 'when the destination already has 5 filters' do
        before do
          create(:audit_events_streaming_instance_namespace_filters, external_streaming_destination: destination)
        end

        it 'returns error' do
          expect(filter).to be_invalid
          expect(filter.errors.full_messages)
            .to contain_exactly(_('Namespace filters are limited to 5 per destination'))
        end

        it 'does not run on update' do
          existing_filter = destination.namespace_filters.order(:id).first

          expect(existing_filter.update(namespace: create(:group))).to be true
        end
      end
    end

    describe 'validates external destination with namespace' do
      shared_examples 'validate namespace with external destination' do |namespace_type|
        let_it_be(:namespace) { build(namespace_type.to_sym) }

        subject do
          build(:audit_events_streaming_instance_namespace_filters, namespace: namespace,
            external_streaming_destination: destination)
        end

        it { is_expected.to be_valid }
      end

      context 'when namespace is group' do
        it_behaves_like 'validate namespace with external destination', 'group'
      end

      context 'when namespace is project' do
        it_behaves_like 'validate namespace with external destination', 'project_namespace'
      end

      context 'when namespace is neither project nor group' do
        it 'returns error' do
          namespace_filter = build(:audit_events_streaming_instance_namespace_filters,
            namespace: create(:user_namespace),
            external_streaming_destination: destination)

          expect(namespace_filter).to be_invalid
          expect(namespace_filter.errors.full_messages)
            .to include("Namespace is not supported. Only project and group are supported.")
        end
      end
    end
  end
end
