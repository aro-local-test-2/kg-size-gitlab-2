# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['PolicyStoreRule'], feature_category: :security_policy_management do
  specify { expect(described_class).to have_graphql_fields(:id, :name) }
end
