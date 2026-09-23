# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuditEventEntity do
  using RSpec::Parameterized::TableSyntax

  let(:event) { create(:audit_events_user_audit_event) }

  subject { described_class.new(event) }

  describe '.as_json' do
    it 'includes audit event attributes' do
      expect(subject.as_json.keys).to match_array(
        [:action, :author, :date, :details, :id, :ip_address, :object, :target]
      )
    end

    it 'includes the details hash' do
      expect(subject.as_json[:details]).to eq(event.details)
    end

    it 'marks the author as removed only when actually deleted, not merely lacking a profile url' do
      expect(subject.as_json[:author][:removed]).to be(false)
    end

    where(:author_id, :author_name, :expected) do
      lazy { non_existing_record_id } | 'deleted' | true
      Gitlab::Audit::NullAuthor::UNAUTHENTICATED_AUTHOR_ID | 'system' | false
    end

    with_them do
      let(:event) { create(:audit_events_user_audit_event, author_id: author_id, author_name: author_name) }

      it 'sets the removed flag as expected' do
        expect(subject.as_json[:author][:removed]).to eq(expected)
      end
    end
  end

  describe '@presenter' do
    it 'is only set once' do
      expect(AuditEventPresenter).to receive(:new)
                                         .with(event)
                                         .and_call_original
                                         .once
      subject.as_json
    end
  end
end
