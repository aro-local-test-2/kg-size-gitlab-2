# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Todos, feature_category: :notifications do
  let_it_be_with_reload(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }

  let_it_be(:user) { create(:user) }

  describe 'GET /todos' do
    let_it_be(:author_1) { create(:user) }
    let_it_be(:pat) { create(:personal_access_token, user: user) }

    before_all do
      group.add_developer(user)
      group.add_developer(author_1)
    end

    def create_todo_for_new_epic
      new_group = create(:group, organization: group.organization, developers: [author_1, user])
      label = create(:label, project: project)
      new_epic = create(:labeled_epic, group: new_group, labels: [label], author: author_1)
      create(:todo, project: nil, group: new_group, author: author_1, user: user, target: new_epic)
    end

    context 'when there is an Epic Todo' do
      let_it_be(:epic_todo) { create_todo_for_new_epic }

      before do
        stub_licensed_features(epics: true)

        get api('/todos', personal_access_token: pat)
      end

      it 'includes the Epic Todo in the response', :aggregate_failures do
        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to include(
          a_hash_including('id' => epic_todo.id)
        )
      end

      it 'avoids N+1 queries', :request_store, quarantine: 'https://gitlab.com/gitlab-org/gitlab/-/issues/448371' do
        create_todo_for_new_epic

        control = ActiveRecord::QueryRecorder.new { get api('/todos', personal_access_token: pat) }

        create_todo_for_new_epic

        expect { get api('/todos', personal_access_token: pat) }.not_to exceed_query_limit(control)
      end
    end

    context 'when there is a duo todo' do
      let_it_be(:todo) { create(:todo, :pending, :duo_enterprise_access, user: user) }

      it 'includes the todo message in the body', :aggregate_failures do
        get api('/todos', personal_access_token: pat)

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to include(a_hash_including('body' => ::GitlabSubscriptions::Duo.todo_message))
      end
    end
  end

  describe 'POST :id/epics/:epic_iid/todo' do
    let_it_be(:epic) { create(:epic, group: group, author: user) }

    def create_todo
      post api("/groups/#{group.id}/epics/#{epic.iid}/todo", user)
    end

    subject { create_todo }

    context 'when epics feature is disabled' do
      it 'returns 403 forbidden error' do
        subject

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'when epics feature is enabled' do
      before do
        stub_licensed_features(epics: true)
      end

      it_behaves_like 'authorizing granular token permissions', :create_todo do
        let(:boundary_object) { group }

        before_all do
          group.add_developer(user)
        end

        let(:request) { post api("/groups/#{group.id}/epics/#{epic.iid}/todo", personal_access_token: pat) }
      end

      it 'creates a todo on an epic' do
        expect { subject }.to change { Todo.count }.by(1)

        expect(response).to have_gitlab_http_status(:created)
        expect(json_response['project']).to be_nil
        expect(json_response['group']).to be_a(Hash)
        expect(json_response['author']).to be_a(Hash)
        expect(json_response['target_type']).to eq('Epic')
        expect(json_response['target']).to be_a(Hash)
        expect(json_response['target_url']).to be_present
        expect(json_response['body']).to be_present
        expect(json_response['state']).to eq('pending')
        expect(json_response['action_name']).to eq('marked')
        expect(json_response['created_at']).to be_present
      end

      it 'returns 304 there already exist a todo on that epic' do
        create_todo

        expect { subject }.not_to change { Todo.count }

        expect(response).to have_gitlab_http_status(:not_modified)
      end

      it 'returns 404 if the epic is not found' do
        group.add_developer(user)

        post api("/groups/#{group.id}/epics/#{non_existing_record_iid}/todo", user)

        expect(response).to have_gitlab_http_status(:not_found)
      end

      it 'returns an error if the epic is not accessible' do
        group.update!(visibility_level: Gitlab::VisibilityLevel::PRIVATE)

        subject

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end
end
