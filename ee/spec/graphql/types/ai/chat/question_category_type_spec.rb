# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::Chat::QuestionCategoryType, feature_category: :duo_chat do
  it 'has the correct name' do
    expect(described_class.graphql_name).to eq('AiChatQuestionCategory')
  end

  it 'has the expected fields' do
    expected_fields = %w[
      contextual
      key
      questions
      title
    ]

    expect(described_class.own_fields.size).to eq(expected_fields.size)
    expect(described_class).to include_graphql_fields(*expected_fields)
  end
end
