# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Compliance::Anthropic::UserResolver, feature_category: :audit_events do
  let_it_be_with_refind(:group) { create(:group) }
  let_it_be(:member) { create(:user, developer_of: group) }

  let(:logged_payloads) { [] }
  let(:session_id) { 'session_01ABCDEF' }
  let(:anthropic_user_id) { 'user_01ZYXWVU' }
  let(:email) { member.email }
  let(:session) do
    {
      'id' => session_id,
      'user' => { 'id' => anthropic_user_id, 'email_address' => email }
    }
  end

  subject(:resolver) { described_class.new(group: group) }

  before do
    allow(::Gitlab::AppJsonLogger).to receive(:info) { |payload| logged_payloads << payload }
  end

  shared_examples 'a dropped session' do |reason|
    it 'returns nil' do
      expect(resolver.resolve(session)).to be_nil
    end

    it 'logs the reason and the Anthropic identifiers, never the email', :aggregate_failures do
      resolver.resolve(session)

      expect(logged_payloads.size).to eq(1)
      expect(logged_payloads.first).to include(
        ::Labkit::Fields::CLASS_NAME => described_class.name,
        ::Labkit::Fields::LOG_MESSAGE => 'Dropped Anthropic session',
        :drop_reason => reason,
        ::Labkit::Fields::GL_NAMESPACE_ID => group.id,
        :anthropic_session_id => session_id,
        :anthropic_user_id => anthropic_user_id
      )
      expect(logged_payloads.first.to_s).not_to include(email)
    end
  end

  describe '#resolve' do
    context 'when exactly one confirmed user matches and is a member' do
      it 'returns that user' do
        expect(resolver.resolve(session)).to eq(member)
      end

      it 'requires the email to be confirmed' do
        expect(::User).to receive(:by_any_email).with(email, confirmed: true).and_call_original

        resolver.resolve(session)
      end

      it 'does not log a drop' do
        resolver.resolve(session)

        expect(logged_payloads).to be_empty
      end
    end

    context 'when the matching user is only a member of a descendant group' do
      let_it_be(:subgroup) { create(:group, parent: group) }
      let_it_be(:subgroup_member) { create(:user, developer_of: subgroup) }

      let(:email) { subgroup_member.email }

      it 'returns that user' do
        expect(resolver.resolve(session)).to eq(subgroup_member)
      end
    end

    context 'when no GitLab user has the email' do
      let(:email) { 'nobody@example.com' }

      it_behaves_like 'a dropped session', :no_gitlab_user
    end

    context 'when the matching user has an unconfirmed email' do
      let_it_be(:unconfirmed_user) { create(:user, :unconfirmed, developer_of: group) }

      let(:email) { unconfirmed_user.email }

      it_behaves_like 'a dropped session', :no_gitlab_user
    end

    context 'when the session carries no email' do
      let(:email) { nil }

      it 'drops the session without looking up a user', :aggregate_failures do
        expect(::User).not_to receive(:by_any_email)

        expect(resolver.resolve(session)).to be_nil
        expect(logged_payloads.first).to include(drop_reason: :no_gitlab_user)
      end
    end

    context 'when the email matches more than one confirmed user' do
      let_it_be(:collided_user) { create(:user, developer_of: group) }

      # Two users cannot really share a confirmed address: emails.email is
      # uniquely indexed and every user gets a primary Email row. The resolver
      # branch guards legacy data, so the collision has to be stubbed.
      before do
        allow(::User).to receive(:by_any_email).and_return([member, collided_user])
      end

      it_behaves_like 'a dropped session', :ambiguous_match

      it 'logs the colliding GitLab user ids' do
        resolver.resolve(session)

        expect(logged_payloads.first[:gitlab_user_ids]).to match_array([member.id, collided_user.id])
      end

      it 'does not check namespace membership' do
        expect(group).not_to receive(:member_of_self_or_descendant?)

        resolver.resolve(session)
      end
    end

    context 'when the matching user is not a member of the group or its descendants' do
      let_it_be(:outsider) { create(:user) }

      let(:email) { outsider.email }

      it_behaves_like 'a dropped session', :not_namespace_member
    end
  end

  describe 'membership memoization' do
    it 'checks membership once per user for the lifetime of one resolver' do
      expect(group).to receive(:member_of_self_or_descendant?).with(member).once.and_return(true)

      2.times { resolver.resolve(session) }
    end

    it 'checks membership again for a new resolver' do
      expect(group).to receive(:member_of_self_or_descendant?).with(member).twice.and_return(true)

      2.times { described_class.new(group: group).resolve(session) }
    end
  end
end
