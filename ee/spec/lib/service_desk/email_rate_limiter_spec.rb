# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ServiceDesk::EmailRateLimiter, :saas, :clean_gitlab_redis_rate_limiting, :freeze_time,
  feature_category: :service_desk do
  before_all do
    create(:plan_limits, :free_plan, service_desk_outbound_emails_per_hour: 1)
    create(:plan_limits, :ultimate_plan, service_desk_outbound_emails_per_hour: 3)
  end

  let_it_be(:group_free_plan) { create(:group_with_plan, plan: :free_plan) }
  let_it_be(:group_ultimate_plan) { create(:group_with_plan, plan: :ultimate_plan) }

  let_it_be(:project_free_plan) { create(:project, group: group_free_plan, service_desk_enabled: true) }
  let_it_be(:project_ultimate_plan) { create(:project, group: group_ultimate_plan, service_desk_enabled: true) }

  before do
    allow(::ServiceDesk).to receive(:enabled?).and_return(true)
  end

  describe '#rate_limit_batch!' do
    using RSpec::Parameterized::TableSyntax

    where(:project, :limit) do
      ref(:project_free_plan)     | 1
      ref(:project_ultimate_plan) | 3
    end

    with_them do
      it 'resolves the per-plan threshold' do
        limiter = described_class.new(project)

        limit.times { expect(limiter.rate_limit_batch!(1)).to be(false) }

        expect(limiter.rate_limit_batch!(1)).to be(true)
      end
    end
  end
end
