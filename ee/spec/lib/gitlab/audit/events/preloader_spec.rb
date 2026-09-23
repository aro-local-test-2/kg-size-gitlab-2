# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Audit::Events::Preloader, feature_category: :audit_events do
  let_it_be(:audit_events) do
    [
      create(:audit_events_group_audit_event, created_at: 2.days.ago),
      create(:audit_events_group_audit_event, created_at: 1.day.ago)
    ]
  end

  let(:audit_events_relation) { AuditEvents::GroupAuditEvent.id_in(audit_events.map(&:id)) }

  describe '.preload!' do
    subject { described_class.preload!(audit_events_relation) }

    it 'returns an ActiveRecord::Relation' do
      expect(subject).to be_an(ActiveRecord::Relation)
    end

    it 'preloads associated records' do
      # Expected queries when requesting audit events with associated records
      #
      # 1. On the group_audit_events table
      # 2. On the users table for author_name
      # 3. On the namespaces table for the entity name
      #
      expect do
        subject.map do |event|
          [event.author_name, event.entity.name]
        end
      end.not_to exceed_query_limit(3)
    end

    it 'accepts an array of events' do
      expect(described_class.preload!(audit_events)).to eq(audit_events)
    end
  end
end
