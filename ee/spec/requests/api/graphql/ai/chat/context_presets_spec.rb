# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Getting Duo Chat context presets', feature_category: :duo_chat do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:user) { project.owner }
  let_it_be(:issue) { create(:issue, project: project) }

  let(:variables) { { question_count: 2 } }

  let(:query) do
    <<~GQL
      query($resourceId: AiModelID, $projectId: ProjectID, $questionCount: Int) {
        aiChatContextPresets(resourceId: $resourceId, projectId: $projectId, questionCount: $questionCount) {
          questions
          questionCategories {
            key
            title
            contextual
            questions
          }
        }
      }
    GQL
  end

  let(:presets_data) { graphql_data['aiChatContextPresets'] }

  it 'returns sampled questions and full question categories' do
    post_graphql(query, current_user: user, variables: variables)

    expect(response).to have_gitlab_http_status(:success)
    expect(presets_data['questions'].size).to eq(2)
    expect(presets_data['questionCategories'].map { |category| category['key'] })
      .to eq(%w[get_started development work_items merge_requests pipelines security])
    expect(presets_data['questionCategories'])
      .to all(match(a_hash_including('title' => be_present, 'contextual' => false, 'questions' => be_present)))
  end

  context 'with a resource from the current page' do
    let(:variables) do
      {
        resource_id: issue.to_global_id.to_s,
        project_id: project.to_global_id.to_s,
        question_count: 2
      }
    end

    before do
      # rubocop:disable RSpec/AnyInstanceOf -- the resolver operates on the user re-loaded from the request
      allow_any_instance_of(User).to receive(:allowed_to_use?).and_return(true)
      # rubocop:enable RSpec/AnyInstanceOf
    end

    it 'returns the contextual category first with the resource reference' do
      post_graphql(query, current_user: user, variables: variables)

      expect(response).to have_gitlab_http_status(:success)

      contextual = presets_data['questionCategories'].first
      expect(contextual['key']).to eq('issue')
      expect(contextual['title']).to eq(issue.to_reference)
      expect(contextual['contextual']).to be(true)
      expect(contextual['questions']).to be_present
    end
  end
end
