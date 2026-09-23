# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::WorkItems::Notes, feature_category: :portfolio_management do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, :private, reporters: user) }
  let_it_be(:epic) { create(:work_item, :epic, namespace: group) }

  let_it_be(:comment) do
    create(:note, namespace: group, project: nil, noteable: epic, author: user, note: 'A user comment on the epic')
  end

  before do
    stub_feature_flags(work_item_rest_api: true)
    stub_licensed_features(epics: true)
  end

  describe 'GET /groups/:id/-/work_items/:work_item_iid/notes' do
    let(:api_request_path) { "/groups/#{group.id}/-/work_items/#{epic.iid}/notes" }

    it 'returns notes on the group-level work item', :aggregate_failures do
      get api(api_request_path, user)

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response.pluck('id')).to contain_exactly(comment.id)
    end

    it_behaves_like 'authorizing granular token permissions', :read_work_item do
      let(:boundary_object) { group }
      let(:request) do
        get api(api_request_path, personal_access_token: pat)
      end
    end

    context 'without the epics license' do
      before do
        stub_licensed_features(epics: false)
      end

      it 'returns 404 when the parent is not readable' do
        get api(api_request_path, user)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end

  describe 'GET /groups/:id/-/work_items/:work_item_iid/notes/:note_id' do
    # Built explicitly rather than by substituting into api_request_path: note ids are small in a
    # fresh database and a substring replace can hit the group id or the iid instead.
    let(:note_path) { ->(note_id) { "/groups/#{group.id}/-/work_items/#{epic.iid}/notes/#{note_id}" } }
    let(:api_request_path) { note_path.call(comment.id) }

    it 'returns the note on the group-level work item', :aggregate_failures do
      get api(api_request_path, user)

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response).to include('id' => comment.id, 'body' => 'A user comment on the epic')
    end

    it 'returns 404 when the note does not exist' do
      get api(note_path.call(non_existing_record_id), user)

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'returns 404 when the note belongs to a different epic' do
      other_epic = create(:work_item, :epic, namespace: group)
      other_note = create(:note, namespace: group, project: nil, noteable: other_epic, author: user,
        note: 'A comment on another epic')

      get api(note_path.call(other_note.id), user)

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'returns not_found when the feature flag is disabled' do
      stub_feature_flags(work_item_rest_api: false)

      get api(api_request_path, user)

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'returns unauthorized when no token is provided' do
      get api(api_request_path)

      expect(response).to have_gitlab_http_status(:unauthorized)
    end

    context 'with a note the user cannot read' do
      let_it_be(:guest) { create(:user, guest_of: group) }
      let_it_be(:internal_note) do
        create(:note, :confidential, namespace: group, project: nil, noteable: epic, author: user,
          note: 'Internal-only note on the epic')
      end

      it 'returns 404 for a user who cannot read the note', :aggregate_failures do
        # Fetching a readable note first proves the 404 below is about note visibility
        # rather than the guest being unable to reach the epic at all.
        get api(api_request_path, guest)
        expect(response).to have_gitlab_http_status(:ok)

        get api(note_path.call(internal_note.id), guest)
        expect(response).to have_gitlab_http_status(:not_found)
      end

      it 'returns the note for a user who can read it', :aggregate_failures do
        get api(note_path.call(internal_note.id), user)

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['id']).to eq(internal_note.id)
      end
    end

    it_behaves_like 'authorizing granular token permissions', :read_work_item do
      let(:boundary_object) { group }
      let(:request) do
        get api(api_request_path, personal_access_token: pat)
      end
    end

    context 'without the epics license' do
      before do
        stub_licensed_features(epics: false)
      end

      it 'returns 404 when the parent is not readable' do
        get api(api_request_path, user)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end

  describe 'POST /groups/:id/-/work_items/:work_item_iid/notes' do
    let_it_be(:non_member) { create(:user) }
    let_it_be(:owner) { create(:user, owner_of: group) }
    let_it_be(:public_group) { create(:group, :public) }
    let_it_be(:locked_work_item) { create(:work_item, :epic, namespace: public_group, discussion_locked: true) }
    let_it_be(:quick_action_label) { create(:group_label, group: group, title: 'bug') }

    let(:work_item) { epic }
    let(:path_for) { ->(item) { "/groups/#{item.namespace.id}/-/work_items/#{item.iid}/notes" } }
    let(:api_request_path) { path_for.call(epic) }
    let(:params) { { body: 'hi!' } }

    it_behaves_like 'a work item endpoint creating a note'

    it 'stores the note against the group', :aggregate_failures do
      post api(api_request_path, user), params: params

      expect(response).to have_gitlab_http_status(:created)
      expect(json_response['project_id']).to be_nil
      expect(Note.find(json_response['id']).namespace_id).to eq(group.id)
    end

    context 'when an ai_workflows token uses a quick action that is not allowed for AI workflows' do
      let_it_be(:oauth_token) { create(:oauth_access_token, user: user, scopes: [:api, :ai_workflows]) }

      it 'returns forbidden with the reason', :aggregate_failures do
        expect { post api(api_request_path, oauth_access_token: oauth_token), params: { body: '/close' } }
          .not_to change { epic.reload.state }

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to include('Quick actions close cannot be used with AI workflows')
      end
    end

    it_behaves_like 'authorizing granular token permissions', :create_note, expected_success_status: :created do
      let(:boundary_object) { group }
      let(:request) do
        post api(api_request_path, personal_access_token: pat), params: params
      end
    end

    context 'without the epics license' do
      before do
        stub_licensed_features(epics: false)
      end

      it 'returns 404 when the parent is not readable' do
        post api(api_request_path, user), params: params

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end
end
