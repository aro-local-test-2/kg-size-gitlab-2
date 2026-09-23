# frozen_string_literal: true

FactoryBot.define do
  factory :ai_suggested_reviewer, class: 'MergeRequests::AiSuggestedReviewer' do
    merge_request
    user
    project { merge_request.project }
    reason { 'Authored most of the changed files.' }
  end
end
