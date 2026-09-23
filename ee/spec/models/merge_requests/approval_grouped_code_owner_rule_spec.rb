# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeRequests::ApprovalGroupedCodeOwnerRule, feature_category: :code_review_workflow do
  let_it_be_with_reload(:approver1) { create(:user) }
  let_it_be_with_reload(:approver2) { create(:user) }
  let_it_be_with_refind(:project) { create(:project, :repository, developers: [approver1, approver2]) }
  let_it_be_with_reload(:group_approver) { create(:user) }
  let_it_be_with_reload(:shared_group) { create(:group, developers: [approver1, approver2, group_approver]) }
  let_it_be_with_reload(:empty_private_group) { create(:group, :private) }

  let_it_be_with_reload(:merge_request) do
    create(:merge_request, source_project: project, target_project: project)
  end

  let_it_be(:protected_branch) do
    create(:protected_branch,
      project: project,
      name: merge_request.target_branch,
      code_owner_approval_required: true)
  end

  let(:rule_vue) do
    create(:code_owner_rule,
      merge_request: merge_request, name: '*.vue', section: 'Frontend',
      users: [approver1], groups: [shared_group], approvals_required: 2)
  end

  let(:rule_js) do
    create(:code_owner_rule,
      merge_request: merge_request, name: '*.js', section: 'Frontend',
      users: [approver2], groups: [shared_group, empty_private_group], approvals_required: 2)
  end

  subject(:grouped) do
    wrapped_rules = [rule_vue, rule_js].map { |rule| ApprovalWrappedCodeOwnerRule.new(merge_request, rule) }

    described_class.new(merge_request, wrapped_rules)
  end

  before do
    stub_licensed_features(code_owner_approval_required: true)
  end

  it 'exposes every underlying pattern' do
    expect(grouped.patterns).to match_array(['*.vue', '*.js'])
  end

  it 'names itself after the section' do
    expect(grouped.name).to eq('Frontend')
  end

  context 'when the section holds a single rule' do
    subject(:grouped) do
      described_class.new(merge_request, [ApprovalWrappedCodeOwnerRule.new(merge_request, rule_vue)])
    end

    it 'keeps the pattern as its name' do
      expect(grouped.name).to eq('*.vue')
    end
  end

  context 'when the rules have no section of their own' do
    let(:rule_vue) do
      create(:code_owner_rule,
        merge_request: merge_request, name: '*.vue', section: ::Gitlab::CodeOwners::Section::DEFAULT,
        users: [approver1], groups: [shared_group], approvals_required: 2)
    end

    let(:rule_js) do
      create(:code_owner_rule,
        merge_request: merge_request, name: '*.js', section: ::Gitlab::CodeOwners::Section::DEFAULT,
        users: [approver2], groups: [shared_group, empty_private_group], approvals_required: 2)
    end

    it 'names itself after the patterns it covers' do
      expect(grouped.name).to eq('*.vue, *.js')
    end
  end

  it 'unions the groups of every underlying rule without duplicating them' do
    expect(grouped.groups).to contain_exactly(shared_group, empty_private_group)
  end

  it 'exposes a groups relation that still detects hidden groups' do
    expect(ApprovalRules::GroupFinder.new(grouped, approver1).contains_hidden_groups?).to be(true)
  end

  it 'unions the directly assigned users of every underlying rule' do
    expect(grouped.users).to contain_exactly(approver1, approver2)
  end

  it 'resolves both rules to the same approvers by different routes' do
    approvers = grouped.wrapped_rules.map { |rule| rule.approvers.map(&:id).sort }

    expect(approvers.uniq.size).to eq(1)
  end

  it 'carries the approvals required by the section' do
    expect(grouped.approvals_required).to eq(2)
  end

  it 'is not approved while an underlying rule still needs approvals' do
    create(:approval, merge_request: merge_request, user: approver1)

    expect(grouped).not_to be_approved
    expect(grouped.approvals_left).to eq(1)
  end

  it 'is approved once every underlying rule is approved' do
    create(:approval, merge_request: merge_request, user: approver1)
    create(:approval, merge_request: merge_request, user: approver2)

    expect(grouped).to be_approved
    expect(grouped.approvals_left).to eq(0)
  end
end
