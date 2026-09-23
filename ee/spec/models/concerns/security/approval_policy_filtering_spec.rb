# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ApprovalPolicyFiltering, feature_category: :security_policy_management do
  let_it_be_with_reload(:root_group) { create(:group) }
  let_it_be(:project) { create(:project, group: root_group) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project) }

  let(:rule) do
    create(:report_approver_rule, :scan_finding, merge_request: merge_request)
  end

  before do
    stub_licensed_features(security_orchestration_policies: true)
    allow(project).to receive_messages(
      merge_requests_author_approval?: true,
      merge_requests_disable_committers_approval?: false
    )
  end

  describe '#prevents_author_approval?' do
    context 'when approval_policy_source is nil' do
      it 'returns false' do
        expect(rule.prevents_author_approval?).to be(false)
      end
    end

    context 'when approval_policy_source prevents author approval' do
      let(:rule) do
        create(:report_approver_rule, :scan_finding, merge_request: merge_request,
          scan_result_policy_read: create(:scan_result_policy_read, project: project,
            project_approval_settings: { 'prevent_approval_by_author' => true }))
      end

      it 'returns true' do
        expect(rule.prevents_author_approval?).to be(true)
      end
    end

    context 'when approval_policy_source does not prevent author approval' do
      let(:rule) do
        create(:report_approver_rule, :scan_finding, merge_request: merge_request,
          scan_result_policy_read: create(:scan_result_policy_read, project: project,
            project_approval_settings: { 'prevent_approval_by_author' => false }))
      end

      it 'returns false' do
        expect(rule.prevents_author_approval?).to be(false)
      end
    end
  end

  describe 'without the security_orchestration_policies license' do
    let(:rule) do
      create(:report_approver_rule, :scan_finding, merge_request: merge_request,
        scan_result_policy_read: create(:scan_result_policy_read, project: project,
          project_approval_settings: { 'prevent_approval_by_author' => true,
                                       'prevent_approval_by_commit_author' => true }))
    end

    before do
      stub_licensed_features(security_orchestration_policies: false)
    end

    it 'does not prevent author or committer approval' do
      expect(rule.prevents_author_approval?).to be(false)
      expect(rule.prevents_committer_approval?).to be(false)
    end

    context 'when the dependency firewall is enforced' do
      before do
        stub_saas_features(dependency_firewall: true)
        stub_licensed_features(security_orchestration_policies: false, dependency_firewall: true)
        root_group.namespace_settings.update!(dependency_firewall_enabled: true)
      end

      it 'still does not prevent author or committer approval' do
        expect(::Security::DependencyFirewall::Availability.enforced_for?(project)).to be(true)

        expect(rule.prevents_author_approval?).to be(false)
        expect(rule.prevents_committer_approval?).to be(false)
      end
    end
  end

  describe '#prevents_committer_approval?' do
    context 'when approval_policy_source is nil' do
      it 'returns false' do
        expect(rule.prevents_committer_approval?).to be(false)
      end
    end

    context 'when approval_policy_source prevents committer approval' do
      let(:rule) do
        create(:report_approver_rule, :scan_finding, merge_request: merge_request,
          scan_result_policy_read: create(:scan_result_policy_read, project: project,
            project_approval_settings: { 'prevent_approval_by_commit_author' => true }))
      end

      it 'returns true' do
        expect(rule.prevents_committer_approval?).to be(true)
      end
    end

    context 'when approval_policy_source does not prevent committer approval' do
      let(:rule) do
        create(:report_approver_rule, :scan_finding, merge_request: merge_request,
          scan_result_policy_read: create(:scan_result_policy_read, project: project,
            project_approval_settings: { 'prevent_approval_by_commit_author' => false }))
      end

      it 'returns false' do
        expect(rule.prevents_committer_approval?).to be(false)
      end
    end
  end
end
