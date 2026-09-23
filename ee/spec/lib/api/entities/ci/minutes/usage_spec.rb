# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::API::Entities::Ci::Minutes::Usage, feature_category: :hosted_runners do
  let_it_be(:namespace) do
    create(:group, :with_ci_minutes,
      ci_minutes_used: 450,
      ci_minutes_limit: 400,
      extra_shared_runners_minutes_limit: 100)
  end

  it 'contains the correct attributes', :aggregate_failures do
    usage = ::Ci::Minutes::Usage.new(namespace)
    entity = described_class.new(usage).as_json

    expect(entity[:total_minutes_used]).to eq(450)
    expect(entity[:monthly_minutes_used]).to eq(400)
    expect(entity[:purchased_minutes_used]).to eq(50)
  end
end
