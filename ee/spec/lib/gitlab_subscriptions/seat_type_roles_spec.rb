# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::SeatTypeRoles, feature_category: :seat_cost_management do
  using RSpec::Parameterized::TableSyntax

  describe '.permits_access_level?' do
    subject(:permits_access_level) do
      described_class.permits_access_level?(seat_type: seat_type, access_level: access_level, member_role: nil)
    end

    context 'with default roles' do
      where(:seat_type, :access_level, :expected_result) do
        :free   | ::Gitlab::Access::MINIMAL_ACCESS   | true
        :free   | ::Gitlab::Access::GUEST            | true
        :free   | ::Gitlab::Access::PLANNER          | false
        :free   | ::Gitlab::Access::REPORTER         | false
        :free   | ::Gitlab::Access::SECURITY_MANAGER | false
        :free   | ::Gitlab::Access::DEVELOPER        | false
        :free   | ::Gitlab::Access::MAINTAINER       | false
        :free   | ::Gitlab::Access::OWNER            | false

        :plan   | ::Gitlab::Access::MINIMAL_ACCESS   | true
        :plan   | ::Gitlab::Access::GUEST            | true
        :plan   | ::Gitlab::Access::PLANNER          | true
        :plan   | ::Gitlab::Access::REPORTER         | false
        :plan   | ::Gitlab::Access::SECURITY_MANAGER | false
        :plan   | ::Gitlab::Access::DEVELOPER        | false
        :plan   | ::Gitlab::Access::MAINTAINER       | false
        :plan   | ::Gitlab::Access::OWNER            | false

        :base   | ::Gitlab::Access::MINIMAL_ACCESS   | true
        :base   | ::Gitlab::Access::GUEST            | true
        :base   | ::Gitlab::Access::PLANNER          | true
        :base   | ::Gitlab::Access::REPORTER         | true
        :base   | ::Gitlab::Access::SECURITY_MANAGER | true
        :base   | ::Gitlab::Access::DEVELOPER        | true
        :base   | ::Gitlab::Access::MAINTAINER       | true
        :base   | ::Gitlab::Access::OWNER            | true

        :system | ::Gitlab::Access::MINIMAL_ACCESS   | true
        :system | ::Gitlab::Access::GUEST            | true
        :system | ::Gitlab::Access::PLANNER          | true
        :system | ::Gitlab::Access::REPORTER         | true
        :system | ::Gitlab::Access::SECURITY_MANAGER | true
        :system | ::Gitlab::Access::DEVELOPER        | true
        :system | ::Gitlab::Access::MAINTAINER       | true
        :system | ::Gitlab::Access::OWNER            | true
      end

      with_them do
        it { is_expected.to be(expected_result) }
      end
    end

    context 'when the seat type is nil' do
      let(:seat_type) { nil }

      where(:access_level) do
        [::Gitlab::Access::GUEST, ::Gitlab::Access::DEVELOPER, ::Gitlab::Access::OWNER]
      end

      with_them do
        it { is_expected.to be(false) }
      end
    end

    it 'accepts a seat type given as a string' do
      expect(
        described_class.permits_access_level?(
          seat_type: 'base', access_level: ::Gitlab::Access::DEVELOPER, member_role: nil
        )
      ).to be(true)
    end

    context 'when the seat type is not recognised' do
      let(:access_level) { ::Gitlab::Access::GUEST }

      where(:seat_type) { ['foo', :foo, '', 0] }

      with_them do
        it { is_expected.to be(false) }
      end
    end

    context 'with a custom role' do
      let_it_be(:group) { create(:group) }

      subject(:permits_access_level) do
        described_class.permits_access_level?(
          seat_type: seat_type,
          access_level: access_level,
          member_role: member_role
        )
      end

      before do
        stub_licensed_features(custom_roles: true)
      end

      context 'when the custom role occupies a seat' do
        let(:member_role) { create(:member_role, :billable, namespace: group) }
        let(:access_level) { member_role.base_access_level }

        where(:seat_type, :expected_result) do
          :free   | false
          :plan   | false
          :base   | true
          :system | true
        end

        with_them do
          it { is_expected.to be(expected_result) }
        end
      end

      context 'when the custom role does not occupy a seat' do
        let(:member_role) { create(:member_role, :non_billable, namespace: group) }
        let(:access_level) { member_role.base_access_level }
        let(:seat_type) { :free }

        it { is_expected.to be(true) }
      end
    end

    it 'defines a maximum access level for every seat type in the enum' do
      expect(described_class::MAX_ACCESS_LEVEL_BY_SEAT_TYPE.keys)
        .to match_array(::GitlabSubscriptions::SeatAssignment.seat_types.keys)
    end
  end
end
