# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanResultPolicies::HumanizationHelpers, feature_category: :security_policy_management do
  using RSpec::Parameterized::TableSyntax

  # Included into services and lib/, not a view helper, so the spec exercises a
  # bare includer rather than the Rails helper object this directory implies.
  let(:humanizer) do
    helper_module = described_class

    Class.new do
      include helper_module
    end.new
  end

  describe '#humanized_approval_setting' do
    where(:attribute, :expected) do
      :prevent_approval_by_author        | 'Prevent approval by merge request creator'
      :prevent_approval_by_commit_author | 'Prevent approvals by users who add commits'
      :require_password_to_approve       | 'Require user re-authentication (password or SAML) to approve'
      :remove_approvals_with_new_commit  | 'When a commit is added: Remove all approvals'
      :block_branch_modification         | 'Prevent branch modification'
      :prevent_pushing_and_force_pushing | 'Prevent pushing and force pushing'
    end

    with_them do
      it 'returns the humanized setting' do
        expect(humanizer.humanized_approval_setting(attribute)).to eq(expected)
      end
    end

    context 'with an unmapped attribute' do
      # Unlike #humanized_boolean, this falls through to nil rather than UNKNOWN,
      # so an unmapped setting renders as a blank audit event or violation comment.
      it 'returns nil' do
        expect(humanizer.humanized_approval_setting(:not_a_real_setting)).to be_nil
      end
    end

    context 'with a nil attribute' do
      it 'returns nil' do
        expect(humanizer.humanized_approval_setting(nil)).to be_nil
      end
    end

    context 'with a string rather than a symbol' do
      it 'returns nil' do
        expect(humanizer.humanized_approval_setting('prevent_approval_by_author')).to be_nil
      end
    end
  end

  describe '#humanized_boolean' do
    where(:value, :expected) do
      true   | 'Yes'
      false  | 'No'
      nil    | 'Unknown'
      'true' | 'Unknown'
      0      | 'Unknown'
    end

    with_them do
      it 'returns the humanized boolean' do
        expect(humanizer.humanized_boolean(value)).to eq(expected)
      end
    end
  end
end
