# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['GitlabSubscriptionsUserRole'], feature_category: :seat_cost_management do
  it 'exposes all user roles' do
    expect(described_class.values.keys).to match_array(%w[GUEST PLANNER REPORTER SECURITY_MANAGER DEVELOPER
      MAINTAINER OWNER])
  end
end
