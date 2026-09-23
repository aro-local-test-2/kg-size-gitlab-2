# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['Organization'], feature_category: :organization do
  let_it_be(:expected_fields) do
    %w[workspacesClusterAgents workItemSettings policyStore]
  end

  specify { expect(described_class).to include_graphql_fields(*expected_fields) }

  describe 'policyStore' do
    it 'is priced so it cannot be fanned out across an organizations connection' do
      expect(described_class.fields['policyStore'].complexity).to eq(10)
    end
  end
end
