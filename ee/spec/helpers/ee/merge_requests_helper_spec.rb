# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EE::MergeRequestsHelper, feature_category: :code_review_workflow do
  include Users::CalloutsHelper
  include ApplicationHelper
  include PageLayoutHelper
  include ProjectsHelper

  describe 'AI overview predicates' do
    let_it_be(:user) { build_stubbed(:user) }

    let(:cookies) { {} }

    before do
      allow(helper).to receive_messages(current_user: user, cookies: cookies)
    end

    describe '#ai_overview_available?' do
      it 'is true when the flag is enabled for the current user' do
        stub_feature_flags(mr_ai_overview: user)

        expect(helper.ai_overview_available?).to be(true)
      end

      it 'is false when the flag is enabled for a different user' do
        stub_feature_flags(mr_ai_overview: build_stubbed(:user))

        expect(helper.ai_overview_available?).to be(false)
      end

      it 'is false when the flag is disabled' do
        stub_feature_flags(mr_ai_overview: false)

        expect(helper.ai_overview_available?).to be(false)
      end
    end

    describe '#ai_overview_enabled?' do
      context 'when the flag is enabled for the current user' do
        before do
          stub_feature_flags(mr_ai_overview: user)
        end

        it 'is false without the opt-in cookie' do
          expect(helper.ai_overview_enabled?).to be(false)
        end

        it 'is true with the opt-in cookie' do
          cookies[:mr_ai_overview_enabled] = 'true'

          expect(helper.ai_overview_enabled?).to be(true)
        end

        it 'is false when the cookie opts out' do
          cookies[:mr_ai_overview_enabled] = 'false'

          expect(helper.ai_overview_enabled?).to be(false)
        end
      end

      it 'is false when the flag is disabled even with the opt-in cookie' do
        stub_feature_flags(mr_ai_overview: false)
        cookies[:mr_ai_overview_enabled] = 'true'

        expect(helper.ai_overview_enabled?).to be(false)
      end
    end
  end

  describe '#diffs_tab_pane_data' do
    subject(:diffs_tab_pane_data) { helper.diffs_tab_pane_data(project, merge_request, {}) }

    let_it_be(:current_user) { build_stubbed(:user) }
    let_it_be(:project) { build_stubbed(:project) }
    let_it_be(:merge_request) { build_stubbed(:merge_request, project: project) }

    before do
      project.add_developer(current_user)

      allow(helper).to receive(:current_user).and_return(current_user)
    end

    context 'for endpoint_codequality' do
      before do
        stub_licensed_features(inline_codequality: true)

        allow(merge_request).to receive(:has_codequality_mr_diff_report?).and_return(true)
      end

      it 'returns expected value' do
        expect(
          diffs_tab_pane_data[:endpoint_codequality]
        ).to eq("/#{project.full_path}/-/merge_requests/#{merge_request.iid}/codequality_mr_diff_reports.json")
      end
    end

    context 'for codequality_report_available' do
      context 'when feature is licensed' do
        before do
          stub_licensed_features(inline_codequality: true)

          allow(merge_request).to receive(:has_codequality_reports?).and_return('true')
        end

        it 'returns expected value' do
          expect(diffs_tab_pane_data[:codequality_report_available]).to eq('true')
        end

        context 'when merge request does not have codequality reports' do
          before do
            allow(merge_request).to receive(:has_codequality_reports?).and_return('false')
          end

          it 'returns expected value' do
            expect(diffs_tab_pane_data[:codequality_report_available]).to eq('false')
          end
        end
      end

      context 'when feature is not licensed' do
        it 'does not return the variable' do
          expect(diffs_tab_pane_data).not_to have_key(:codequality_report_available)
        end
      end
    end

    context 'for sast_report_available' do
      before do
        allow(merge_request).to receive(:has_sast_reports?).and_return(true)
      end

      it 'returns expected value' do
        expect(diffs_tab_pane_data[:sast_report_available]).to eq('true')
      end

      context 'when merge request does not have SAST reports' do
        before do
          allow(merge_request).to receive(:has_sast_reports?).and_return(false)
        end

        it 'returns expected value' do
          expect(diffs_tab_pane_data[:sast_report_available]).to eq('false')
        end
      end
    end
  end

  describe '#identity_verification_alert_data' do
    let_it_be(:current_user) { build_stubbed(:user) }
    let(:author) { current_user }
    let(:merge_request) { build_stubbed(:merge_request, author: author) }

    subject(:identity_verification_alert_data) { helper.identity_verification_alert_data(merge_request) }

    before do
      allow(helper).to receive(:current_user).and_return(current_user)
      allow_next_instance_of(::Users::IdentityVerification::AuthorizeCi) do |instance|
        allow(instance).to receive(:user_can_run_jobs?).and_return(false)
      end
    end

    shared_examples 'returns the correct data' do
      specify do
        expected_data = {
          identity_verification_required: iv_required.to_s,
          identity_verification_path: identity_verification_path
        }

        expect(identity_verification_alert_data).to eq(expected_data)
      end
    end

    it_behaves_like 'returns the correct data' do
      let(:iv_required) { true }
    end

    context 'when the MR author is not the current user' do
      let(:author) { build_stubbed(:user) }

      it_behaves_like 'returns the correct data' do
        let(:iv_required) { false }
      end
    end

    context 'when the user is authorized to run jobs' do
      before do
        allow_next_instance_of(::Users::IdentityVerification::AuthorizeCi) do |instance|
          allow(instance).to receive(:user_can_run_jobs?).and_return(true)
        end
      end

      it_behaves_like 'returns the correct data' do
        let(:iv_required) { false }
      end
    end

    context 'when current_user is nil' do
      before do
        allow(helper).to receive(:current_user).and_return(nil)
      end

      it_behaves_like 'returns the correct data' do
        let(:iv_required) { false }
      end
    end

    context 'when merge_request.project is nil' do
      before do
        allow(merge_request).to receive(:project).and_return(nil)
      end

      it_behaves_like 'returns the correct data' do
        let(:iv_required) { false }
      end
    end
  end

  describe '#sticky_header_data' do
    # rubocop:disable RSpec/FactoryBot/AvoidCreate -- Helper method accesses database
    let_it_be(:current_user) { create(:user) }
    let_it_be(:merge_request) { create(:merge_request, author: current_user) }
    # rubocop:enable RSpec/FactoryBot/AvoidCreate
    let(:reports_tab_data) do
      ['reports', _('Reports'), reports_project_merge_request_path(merge_request.project, merge_request), '-']
    end

    before do
      stub_licensed_features(security_dashboard: true)
      allow(helper).to receive(:current_user).and_return(current_user)
    end

    it 'includes reports tab data' do
      expect(helper.sticky_header_data(merge_request.project, merge_request)[:tabs]).to include(reports_tab_data)
    end

    context 'when license is not available' do
      before do
        stub_licensed_features(security_dashboard: false)
      end

      it 'does not include reports tab data' do
        expect(helper.sticky_header_data(merge_request.project, merge_request)[:tabs]).not_to include(reports_tab_data)
      end
    end
  end

  describe '#summarize_new_merge_request_disabled_reason' do
    subject(:summarize_new_merge_request_disabled_reason) do
      helper.summarize_new_merge_request_disabled_reason(merge_request)
    end

    let(:project) { build_stubbed(:project) }
    let(:merge_request) { build_stubbed(:merge_request, project: project) }
    let(:source_branch_sha) { 'abc' }
    let(:target_branch_sha) { 'def' }
    let(:diff_collection) { instance_double(Gitlab::Git::DiffCollection, any?: true) }

    before do
      allow(merge_request).to receive_messages(
        source_branch_sha: source_branch_sha,
        target_branch_sha: target_branch_sha
      )

      allow_next_instance_of(Gitlab::Git::Compare) do |compare|
        allow(compare).to receive(:diffs).and_return(diff_collection)
      end
    end

    context 'when no source branch' do
      let(:source_branch_sha) { nil }

      it { is_expected.to eq('Source branch not available') }
    end

    context 'when no target branch' do
      let(:target_branch_sha) { nil }

      it { is_expected.to eq('Target branch not available') }
    end

    context 'when diff between source and target branches is empty' do
      let(:diff_collection) { instance_double(Gitlab::Git::DiffCollection, any?: false) }

      it { is_expected.to eq('No changes between source and target branches') }
    end

    context 'when diff between source and target branches is not empty' do
      let(:diff_collection) { instance_double(Gitlab::Git::DiffCollection, any?: true) }

      it { is_expected.to be_nil }
    end
  end

  describe '#can_resolve_with_ai?' do
    let(:current_user) { build_stubbed(:user) }
    let(:merge_request) { build_stubbed(:merge_request) }

    before do
      allow(helper).to receive(:current_user).and_return(current_user)
      allow(merge_request).to receive(:can_resolve_with_ai?).with(current_user).and_return(true)
    end

    it 'delegates to the merge request' do
      expect(helper.can_resolve_with_ai?(merge_request)).to be true
      expect(merge_request).to have_received(:can_resolve_with_ai?).with(current_user)
    end
  end

  describe '#merge_request_dashboard_search_data' do
    let_it_be(:current_user) { build_stubbed(:user) }

    subject(:data) { helper.merge_request_dashboard_search_data }

    before do
      allow(helper).to receive_messages(current_user: current_user, default_merge_request_sort: 'created_desc')
    end

    context 'when scoped labels are available' do
      before do
        stub_licensed_features(scoped_labels: true)
      end

      it { expect(data[:has_scoped_labels_feature]).to eq('true') }
    end

    context 'when scoped labels are not available' do
      before do
        stub_licensed_features(scoped_labels: false)
      end

      it { expect(data[:has_scoped_labels_feature]).to eq('false') }
    end
  end

  describe '#code_dropdown_data' do
    let_it_be(:merge_request) { build_stubbed(:merge_request) }

    subject(:data) { helper.code_dropdown_data(merge_request) }

    before do
      allow(helper).to receive_messages(
        current_user: build_stubbed(:user),
        controller_name: 'merge_requests',
        action_name: 'show'
      )
    end

    context 'when remote development is available' do
      before do
        stub_licensed_features(remote_development: true)
      end

      it 'returns the workspace path and event label' do
        expect(data).to include(
          workspace_path: helper.workspace_path_with_params(
            project_path: merge_request.source_project.full_path,
            ref: merge_request.source_branch
          ),
          workspace_event_label: 'merge_requests:show'
        )
      end
    end

    context 'when remote development is not available' do
      before do
        stub_licensed_features(remote_development: false)
      end

      it 'omits the workspace path' do
        expect(data).not_to have_key(:workspace_path)
      end
    end
  end
end
