# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuditEvents::Group::ExternalStreamingDestination, feature_category: :audit_events do
  subject(:destination) { build(:audit_events_group_external_streaming_destination) }

  describe 'Associations' do
    it 'belongs to a group' do
      expect(destination.group).not_to be_nil
    end

    it { is_expected.to have_many(:event_type_filters) }
    it { is_expected.to have_many(:namespace_filters).class_name('AuditEvents::Group::NamespaceFilter') }
  end

  describe 'Validations' do
    let_it_be(:group) { create(:group) }

    it 'validates uniqueness of name scoped to category, and group_id' do
      create(:audit_events_group_external_streaming_destination, name: 'Test Destination', group: group)
      destination = build(:audit_events_group_external_streaming_destination, name: 'Test Destination', group: group)

      expect(destination).not_to be_valid
      expect(destination.errors.full_messages).to include('Name has already been taken')

      group2 = create(:group)
      destination2 = build(:audit_events_group_external_streaming_destination, name: 'Test Destination', group: group2)

      expect(destination2).to be_valid
    end

    it 'allows duplicate name in different categories' do
      create(:audit_events_group_external_streaming_destination, name: 'Test Destination', group: group)
      aws_destination = create(:audit_events_group_external_streaming_destination, :aws,
        name: 'Test Destination', group: group)
      gcp_destination = create(:audit_events_group_external_streaming_destination, :gcp,
        name: 'Test Destination', group: group)

      expect(aws_destination).to be_valid
      expect(gcp_destination).to be_valid
    end

    context 'when the destination already has more namespace filters than the limit' do
      let_it_be(:over_limit_destination, refind: true) do
        create(:audit_events_group_external_streaming_destination, group: group)
      end

      before_all do
        5.times do
          create(:audit_events_streaming_group_namespace_filters,
            external_streaming_destination: over_limit_destination,
            namespace: create(:group, parent: group))
        end

        # Simulates a row persisted before the limit was enforced at filter create.
        build(:audit_events_streaming_group_namespace_filters,
          external_streaming_destination: over_limit_destination,
          namespace: create(:group, parent: group)).save!(validate: false)
      end

      it 'stays saveable so the destination is not bricked' do
        over_limit_destination.name = 'Renamed destination'

        expect(over_limit_destination).to be_valid
        expect(over_limit_destination.save).to be true
      end
    end

    context 'when group' do
      it 'is a subgroup' do
        destination.group = build(:group, :nested)

        expect(destination).to be_invalid
        expect(destination.errors.full_messages).to include('Group must not be a subgroup. Use a top-level group.')
      end
    end

    context 'for uniqueness of config url for http destinations' do
      let_it_be(:destination1) { create(:audit_events_group_external_streaming_destination, group: group) }

      it 'returns error if destination with same url exists' do
        destination2 = build(:audit_events_group_external_streaming_destination, group: destination1.group,
          config: destination1.config)

        expect(destination2).to be_invalid
        expect(destination2.errors.full_messages)
          .to include('Config url already taken.')
      end
    end
  end

  it_behaves_like 'includes Limitable concern' do
    subject { build(:audit_events_group_external_streaming_destination) }
  end

  it_behaves_like 'includes ExternallyStreamable concern', :audit_events_group_external_streaming_destination do
    subject { build(:audit_events_group_external_streaming_destination) }

    let(:model_factory_name) { :audit_events_group_external_streaming_destination }
  end

  it_behaves_like 'includes LegacyDestinationMappable concern',
    :audit_events_group_external_streaming_destination,
    described_class

  it_behaves_like 'includes Activatable concern' do
    let(:model_factory_name) { :audit_events_group_external_streaming_destination }
  end

  describe 'denylist event type filtering' do
    let_it_be(:group) { create(:group) }
    let_it_be(:destination) { create(:audit_events_group_external_streaming_destination, group: group) }
    let_it_be(:audit_event) { create(:audit_events_group_audit_event, target_group: group) }

    before_all do
      create(:audit_events_group_event_type_filters,
        external_streaming_destination: destination,
        audit_event_type: 'event_type_filters_deleted',
        kind: :deny)

      create(:audit_events_group_event_type_filters,
        external_streaming_destination: destination,
        audit_event_type: 'event_type_filters_created')
    end

    it 'blocks the denylisted event' do
      expect(destination.allowed_to_stream?('event_type_filters_deleted', audit_event)).to be false
    end

    it 'still streams events that are not denylisted' do
      expect(destination.allowed_to_stream?('event_type_filters_created', audit_event)).to be true
    end
  end

  describe ".configs_of_parent" do
    let!(:http_destinations) do
      create_list(:audit_events_group_external_streaming_destination, 3, group: destination.group)
    end

    let!(:other_group_destination) { create(:audit_events_group_external_streaming_destination) }
    let!(:non_http_destination) do
      create(:audit_events_group_external_streaming_destination, :aws, group: destination.group)
    end

    it 'returns configs of other destinations of same category for same group' do
      configs = destination.group.external_audit_event_streaming_destinations.configs_of_parent(destination.id, 'http')

      expect(configs.length).to eq(http_destinations.length)
      expect(configs).to match_array(http_destinations.pluck(:config))
      expect(configs).to exclude(other_group_destination.config)
      expect(configs).to exclude(non_http_destination.config)
    end
  end
end
