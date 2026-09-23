# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Govern::PolicyStoreRoleType, feature_category: :security_policy_management do
  specify { expect(described_class.graphql_name).to eq('PolicyStoreRole') }

  it 'has the expected fields' do
    expected_fields = %w[id name]

    expect(described_class).to have_graphql_fields(*expected_fields).only
  end
end
