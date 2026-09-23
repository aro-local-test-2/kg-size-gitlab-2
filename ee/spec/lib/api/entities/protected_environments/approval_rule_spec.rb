# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Entities::ProtectedEnvironments::ApprovalRule, feature_category: :continuous_delivery do
  subject(:approval_rule_entity) { described_class.new(approval_rule).as_json }

  let(:approval_rule) { build(:protected_environment_approval_rule) }

  it 'exposes correct attributes' do
    expect(approval_rule_entity.keys).to contain_exactly(
      :id, :user_id, :group_id, :access_level, :access_level_description,
      :required_approvals, :group_inheritance_type
    )
  end
end
