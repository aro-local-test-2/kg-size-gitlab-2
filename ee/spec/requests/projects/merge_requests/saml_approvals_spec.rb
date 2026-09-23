# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'merge request SAML approvals', feature_category: :code_review_workflow do
  describe 'GET /:namespace/:project/-/merge_requests/:iid/saml_approval' do
    let_it_be(:user) { create(:user) }
    let_it_be(:group) { create(:group, developers: user) }
    let_it_be(:project) { create(:project, :small_repo, group: group) }
    let_it_be(:merge_request) { create(:merge_request, source_project: project) }

    let(:requires_saml_auth) { true }
    let(:service_response) { ServiceResponse.success(payload: { approval: build(:approval) }) }

    subject(:send_request) do
      get saml_approval_namespace_project_merge_request_path(group, project, merge_request)
    end

    before do
      sign_in(user)

      allow_next_instance_of(::MergeRequests::ApprovalService) do |service|
        allow(service).to receive(:approval_requires_saml_auth?).and_return(requires_saml_auth)
        allow(service).to receive(:execute).with(merge_request).and_return(service_response)
      end
    end

    it 'redirects to the merge request with a success notice', :aggregate_failures do
      send_request

      expect(response).to redirect_to(namespace_project_merge_request_path(group, project, merge_request))
      expect(flash[:notice]).to eq(_('Approved'))
      expect(flash[:alert]).to be_nil
    end

    context 'when the approval service returns an error' do
      let(:service_response) do
        ServiceResponse.error(message: 'SAML authentication is required', reason: :saml_reauthentication_required)
      end

      it 'redirects to the merge request with an alert', :aggregate_failures do
        send_request

        expect(response).to redirect_to(namespace_project_merge_request_path(group, project, merge_request))
        expect(flash[:alert]).to eq(_('Approval rejected.'))
        expect(flash[:notice]).to be_nil
      end
    end

    context 'when approval does not require SAML auth' do
      let(:requires_saml_auth) { false }

      it 'returns 404 without approving' do
        send_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when the merge request does not exist' do
      subject(:send_request) do
        get saml_approval_namespace_project_merge_request_path(group, project, non_existing_record_iid)
      end

      it 'returns 404' do
        send_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end
end
