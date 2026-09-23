# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::MergeRequests::GetMergeRequestTool, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public, :repository) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project, target_project: project) }

  let(:params) do
    { project_id: project.id.to_s, merge_request_iid: merge_request.iid, include: ['diffs'], detail: 'full_patch' }
  end

  let(:tool) { described_class.new(current_user: user, params: params) }

  before_all do
    project.add_developer(user)
  end

  def count_approval_queries
    run = -> { described_class.new(current_user: user, params: params).execute }
    run.call # warm the license and project lookups so only the rule fan-out is measured

    ActiveRecord::QueryRecorder.new { run.call }.count
  end

  def set_exclusion_rules(rules)
    project.reload
    project.create_project_setting unless project.project_setting
    project.project_setting.update!(duo_context_exclusion_settings: { exclusion_rules: rules })
  end

  describe '#process_result' do
    context 'when the upstream result is an error' do
      let(:params) { { project_id: project.id.to_s, merge_request_iid: non_existing_record_iid } }

      it 'returns the error without consulting the file exclusion service' do
        expect(::Ai::FileExclusionService).not_to receive(:new)

        result = tool.execute

        expect(result[:isError]).to be(true)
      end
    end

    context 'when detail is stats (no diffs node in response)' do
      let(:params) do
        { project_id: project.id.to_s, merge_request_iid: merge_request.iid, include: ['diffs'], detail: 'stats' }
      end

      it 'skips exclusion filtering and returns the response as-is' do
        expect(::Ai::FileExclusionService).not_to receive(:new)

        result = tool.execute

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent]).not_to have_key('diffs')
      end
    end

    context 'when detail is none (no diffs node in response)' do
      let(:params) do
        { project_id: project.id.to_s, merge_request_iid: merge_request.iid, include: ['diffs'], detail: 'none' }
      end

      it 'skips exclusion filtering and returns the response as-is' do
        expect(::Ai::FileExclusionService).not_to receive(:new)

        result = tool.execute

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent]).not_to have_key('diffs')
      end
    end

    context 'when the project excludes no files' do
      before do
        set_exclusion_rules([])
      end

      it 'returns the per-file patch text unfiltered', :aggregate_failures do
        result = tool.execute

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent].dig('diffs', 'nodes')).to be_present
      end
    end

    context 'when the project excludes a file from AI context' do
      let(:excluded_path) { merge_request.diffs.diffs.filter_map(&:new_path).first }

      before do
        set_exclusion_rules([excluded_path])
      end

      it 'removes the excluded file while keeping the others', :aggregate_failures do
        result = tool.execute

        returned_paths = result[:structuredContent].dig('diffs', 'nodes').map { |diff| diff['newPath'] }

        expect(result[:isError]).to be(false)
        expect(returned_paths).not_to include(excluded_path)
        expect(result[:structuredContent].dig('diffs', 'nodes')).to be_present
      end

      it 'consults the file exclusion service' do
        expect(::Ai::FileExclusionService).to receive(:new).with(project).and_call_original

        tool.execute
      end
    end
  end

  describe 'conflict files exclusion' do
    let_it_be(:conflict_mr) do
      create(:merge_request, source_branch: 'conflict-resolvable', target_branch: 'conflict-start',
        source_project: project, merge_status: :cannot_be_merged)
    end

    let(:params) do
      { project_id: project.id.to_s, merge_request_iid: conflict_mr.iid, include: ['conflicts'] }
    end

    before do
      ::MergeRequests::MergeabilityCheckService.new(conflict_mr).execute
    end

    context 'when no exclusion rules are set' do
      it 'returns all conflict files', :aggregate_failures do
        result = tool.execute

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent]['conflictFiles']).to be_present
      end
    end

    context 'when the project excludes a conflict file from AI context' do
      let(:excluded_path) do
        result = tool.execute
        result[:structuredContent]['conflictFiles'].first['ourPath']
      end

      before do
        set_exclusion_rules([excluded_path])
      end

      it 'removes the excluded conflict file', :aggregate_failures do
        result = tool.execute

        returned_paths = result[:structuredContent]['conflictFiles'].map { |f| f['ourPath'] }

        expect(result[:isError]).to be(false)
        expect(returned_paths).not_to include(excluded_path)
      end

      it 'consults the file exclusion service' do
        expect(::Ai::FileExclusionService).to receive(:new).with(project).and_call_original

        tool.execute
      end
    end

    context 'when conflicts are not requested' do
      let(:params) { { project_id: project.id.to_s, merge_request_iid: conflict_mr.iid } }

      it 'does not consult the file exclusion service' do
        expect(::Ai::FileExclusionService).not_to receive(:new)

        tool.execute
      end
    end
  end

  describe 'approvals facet' do
    let(:params) { { project_id: project.id.to_s, merge_request_iid: merge_request.iid, include: ['approvals'] } }

    it 'builds the query from the EE override so the rule fields resolve' do
      expect(described_class.build_query).to include('approvalState')
    end

    it 'keeps every CE selection, so the two query copies cannot drift apart' do
      ce_path = 'app/graphql/queries/mcp/merge_requests/get_merge_request.query.graphql'
      ce_lines = File.read(Rails.root.join(ce_path)).lines.map(&:rstrip)
      ce_lines = ce_lines.map { |line| line.sub('query getMergeRequest(', 'query getMergeRequestEE(') }
      ee_lines = described_class.build_query.lines.map(&:rstrip)

      missing = ce_lines.tally.filter_map { |line, count| line if ee_lines.count(line) < count }

      expect(missing).to be_empty, "EE query dropped CE selections: #{missing.inspect}"
    end

    context 'without a Premium or Ultimate license' do
      before do
        stub_licensed_features(merge_request_approvers: false)
      end

      it 'still returns the base approval fields and degrades the rule data', :aggregate_failures do
        result = tool.execute

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent]['approved']).to be(false)
        expect(result[:structuredContent]['approvedBy']).to include('nodes' => [])
        expect(result[:structuredContent]['approvalsRequired']).to eq(0)
        expect(result[:structuredContent]['approvalsLeft']).to eq(0)
        expect(result[:structuredContent].dig('approvalState', 'rules')).to eq([])
      end
    end

    context 'with a Premium or Ultimate license' do
      # A plain let, because approval rules assign to the user record and let_it_be freezes it.
      let(:rule_approver) { create(:user, developer_of: project) }

      let!(:approval_rule) do
        create(:approval_merge_request_rule, merge_request: merge_request, users: [rule_approver],
          approvals_required: 1)
      end

      before do
        # multiple_approval_rules is what lifts ApprovalState's one rule cap, so without it the
        # breakdown below would only ever hold a single rule.
        stub_licensed_features(merge_request_approvers: true, multiple_approval_rules: true)
      end

      it 'includes the approval rule breakdown and the outstanding counts', :aggregate_failures do
        result = tool.execute

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent]['approved']).to be(false)
        expect(result[:structuredContent].dig('approvalState', 'rules')).to contain_exactly(
          a_hash_including(
            'id' => approval_rule.to_global_id.to_s,
            'name' => approval_rule.name,
            'type' => 'REGULAR',
            'approvalsRequired' => 1,
            'approved' => false,
            'overridden' => false
          )
        )
        expect(result[:structuredContent]['approvalsRequired']).to eq(1)
        expect(result[:structuredContent]['approvalsLeft']).to eq(1)
      end

      it 'lists who already approved each rule', :aggregate_failures do
        rule = tool.execute[:structuredContent].dig('approvalState', 'rules').first

        expect(rule.dig('approvedBy', 'nodes')).to eq([])
        expect(rule.dig('approvedBy', 'pageInfo')).to have_key('hasNextPage')
      end

      it 'returns the rest of the approval state alongside the rules', :aggregate_failures do
        approval_state = tool.execute[:structuredContent]['approvalState']

        expect(approval_state['approvalRulesOverwritten']).to be(true)
        expect(approval_state['invalidApproversRules']).to eq([])
      end

      context 'with more than one rule' do
        let!(:second_rule) do
          create(:approval_merge_request_rule, merge_request: merge_request, name: 'security',
            users: [create(:user, developer_of: project)], approvals_required: 1)
        end

        it 'returns every rule and adds up the required approvals', :aggregate_failures do
          result = tool.execute

          rules = result[:structuredContent].dig('approvalState', 'rules')
          expect(rules.pluck('name')).to contain_exactly(approval_rule.name, 'security')
          expect(result[:structuredContent]['approvalsRequired']).to eq(2)
          expect(result[:structuredContent]['approvalsLeft']).to eq(2)
        end

        # Each rule costs a couple of queries. Selecting eligibleApprovers or suggestedApprovers here
        # would resolve rule.approvers once per rule and push that to eight, so this pins the shape of
        # the query rather than the exact count.
        it 'does not fan out per rule beyond a small fixed cost' do
          baseline = count_approval_queries

          extra_rules = 4
          extra_rules.times do |i|
            create(:approval_merge_request_rule, merge_request: merge_request, name: "extra-#{i}",
              users: [create(:user, developer_of: project)], approvals_required: 1)
          end

          expect((count_approval_queries - baseline).fdiv(extra_rules)).to be <= 3
        end
      end
    end

    context 'when approvals are not requested' do
      let(:params) { { project_id: project.id.to_s, merge_request_iid: merge_request.iid } }

      it 'omits every approval field', :aggregate_failures do
        result = tool.execute

        expect(result[:structuredContent]).not_to have_key('approvalsRequired')
        expect(result[:structuredContent]).not_to have_key('approvalState')
      end
    end
  end
end
