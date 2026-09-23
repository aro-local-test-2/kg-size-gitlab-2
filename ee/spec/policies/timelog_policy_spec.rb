# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TimelogPolicy, feature_category: :team_planning do
  let_it_be_with_refind(:group) { create(:group, :private) }
  let_it_be_with_refind(:author) { create(:user) }
  # `with_reload` (freeze: false) because `Timelog belongs_to :issue, touch: true`:
  # creating the timelog below touches the work item, which raises FrozenError
  # on a default (frozen) `let_it_be` record.
  let_it_be_with_reload(:epic) { create(:work_item, :epic, namespace: group) }
  let_it_be_with_reload(:timelog) { create(:timelog, user: author, issue: epic, time_spent: 1800) }

  let(:user) { nil }

  subject { described_class.new(user, timelog) }

  before do
    stub_licensed_features(epics: true)
  end

  # A timelog on a group-level epic has no project, so its abilities resolve
  # through GroupPolicy rather than ProjectPolicy. These abilities were granted
  # at project scope only until now, which left group-level timelogs
  # undeletable by everyone. See https://gitlab.com/gitlab-org/gitlab/-/issues/619383
  describe '#rules' do
    context 'when user is anonymous' do
      it { expect_disallowed(:delete_timelog) }
    end

    context 'when user is the author of the timelog' do
      let(:user) { author }

      context 'when user is a guest of the group' do
        before_all do
          group.add_guest(author)
        end

        it { expect_allowed(:delete_timelog) }
      end

      context 'when user has no role in the private group' do
        it { expect_disallowed(:delete_timelog) }
      end

      context 'when user has no role but the group is public' do
        let_it_be(:public_group) { create(:group, :public) }
        let_it_be_with_reload(:public_epic) { create(:work_item, :epic, namespace: public_group) }
        let_it_be_with_reload(:public_timelog) do
          create(:timelog, user: author, issue: public_epic, time_spent: 1800)
        end

        subject { described_class.new(user, public_timelog) }

        it { expect_allowed(:delete_timelog) }
      end
    end

    context 'when user is not the author of the timelog' do
      let_it_be(:user) { create(:user) }

      context 'when user is an owner of the group' do
        before_all do
          group.add_owner(user)
        end

        it { expect_allowed(:delete_timelog) }

        # The GraphQL TimelogPermissions type still exposes adminTimelog, and
        # the customer report in issue 619383 was an owner seeing it as false.
        it { expect_allowed(:admin_timelog) }
      end

      context 'when user is a maintainer of the group' do
        before_all do
          group.add_maintainer(user)
        end

        it { expect_allowed(:delete_timelog) }
      end

      context 'when user is a reporter of the group' do
        before_all do
          group.add_reporter(user)
        end

        it { expect_disallowed(:delete_timelog) }
      end

      context 'when user is an administrator', :enable_admin_mode do
        let_it_be(:user) { create(:user, :admin) }

        it { expect_allowed(:delete_timelog) }
      end

      context 'when user has no role in the group' do
        it { expect_disallowed(:delete_timelog) }
      end
    end

    context 'when the group is archived' do
      before do
        group.namespace_settings.update!(archived: true)
      end

      context 'when user is the author and a guest of the group' do
        let(:user) { author }

        before_all do
          group.add_guest(author)
        end

        it { expect_disallowed(:delete_timelog) }
      end

      context 'when user is an owner of the group' do
        let_it_be(:user) { create(:user) }

        before_all do
          group.add_owner(user)
        end

        it { expect_disallowed(:delete_timelog) }
      end
    end
  end
end
