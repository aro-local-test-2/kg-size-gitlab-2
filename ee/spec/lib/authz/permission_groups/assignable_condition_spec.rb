# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authz::PermissionGroups::AssignableCondition, feature_category: :permissions do
  describe '.satisfied?' do
    describe 'gitlab_team_member condition' do
      let(:user) { build(:user) }

      context 'when the user is a GitLab team member' do
        before do
          allow(user).to receive(:gitlab_team_member?).and_return(true)
        end

        it 'is satisfied' do
          expect(described_class.satisfied?([:gitlab_team_member], user)).to be(true)
        end
      end

      context 'when the user is not a GitLab team member' do
        before do
          allow(user).to receive(:gitlab_team_member?).and_return(false)
        end

        it 'is not satisfied' do
          expect(described_class.satisfied?([:gitlab_team_member], user)).to be(false)
        end
      end
    end
  end
end
