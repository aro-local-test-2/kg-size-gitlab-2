# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeRequests::AiSuggestedReviewerPolicy, feature_category: :code_review_workflow do
  let_it_be(:current_user) { create(:user) }
  let_it_be(:blocked_user) { create(:user, :blocked) }
  let_it_be(:active_suggestion) { create(:ai_suggested_reviewer) }
  let_it_be(:blocked_suggestion) { create(:ai_suggested_reviewer, user: blocked_user) }

  context 'when the suggested user is active' do
    subject { described_class.new(current_user, active_suggestion) }

    it 'delegates to the policy of the suggested user' do
      expect_allowed(:read_user, :read_user_profile)
    end
  end

  context 'when the suggested user is blocked' do
    subject { described_class.new(current_user, blocked_suggestion) }

    it 'hides the profile of the suggested user' do
      expect_disallowed(:read_user_profile)
    end
  end
end
