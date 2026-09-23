# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::WorkItems::Discussions, feature_category: :portfolio_management do
  let_it_be(:user) { create(:user) }
  let_it_be(:non_member) { create(:user) }
  let_it_be(:group) { create(:group, :private, reporters: user) }
  let_it_be(:epic) { create(:work_item, :epic, namespace: group) }

  let_it_be(:comment) do
    create(:note, namespace: group, project: nil, noteable: epic, author: user, note: 'A user comment on the epic')
  end

  let_it_be(:system_note) do
    create(:note, :system, namespace: group, project: nil, noteable: epic, author: user, note: 'changed the title')
  end

  let(:work_item) { epic }
  let(:container) { group }
  let(:note_params) { { namespace: group, project: nil } }

  before do
    stub_feature_flags(work_item_rest_api: true)
    stub_licensed_features(epics: true)
  end

  describe 'GET /groups/:id/-/work_items/:work_item_iid/discussions' do
    let(:api_request_path) { "/groups/#{group.id}/-/work_items/#{epic.iid}/discussions" }

    it_behaves_like 'a work item discussions endpoint'

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

    it 'returns not_found when the user cannot read the work item' do
      get api(api_request_path, non_member)

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  describe 'GET /groups/:id/-/work_items/:work_item_iid/discussions/:discussion_id' do
    let(:api_request_path) { "/groups/#{group.id}/-/work_items/#{epic.iid}/discussions/#{comment.discussion_id}" }

    it_behaves_like 'a work item single discussion endpoint'

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

    it 'returns not_found when the user cannot read the work item' do
      get api(api_request_path, non_member)

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end
end
