# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['FunctionalVerificationStatus'], feature_category: :duo_agent_platform do
  let(:fields) { %i[state message updated_at] }

  it { expect(described_class).to have_graphql_fields(*fields) }
end
