# frozen_string_literal: true

require 'spec_helper'

# The EE incident-management throttle (throttle_incident_management_notification_web)
# fires only on alerts/notify requests, and alerts_notify? requires web_request?,
# so it always co-fires with the general web throttle. Rack::Attack counts such a
# request under both throttles independently, so the Labkit shadow must too: the
# incident throttle lives in its own limiter (rack_request_incident_management,
# counted by path) while the web throttle stays in rack_request (counted by ip).
#
# This proves one alerts/notify request increments both counters once, in disjoint
# keyspaces, rather than one masking the other (which a shared limiter would cause,
# since the middleware records only the first throttle that fires per limiter).
RSpec.describe 'Labkit::RateLimit rack middleware (EE throttles)', :clean_gitlab_redis_rate_limiting, feature_category: :rate_limiting do
  include RackAttackSpecHelpers
  using RSpec::Parameterized::TableSyntax

  let(:path) { '/group/project/alerts/notify' }

  before do
    stub_application_setting(
      throttle_unauthenticated_enabled: true,
      throttle_incident_management_notification_enabled: true,
      throttle_incident_management_notification_per_period: 100,
      throttle_incident_management_notification_period_in_seconds: 60
    )

    # spec/support/rate_limiter_labkit_rack_shadow.rb stubs all cohort flags to
    # false globally to keep the shadow out of unrelated specs; re-enable both
    # cohorts here so the middleware actually runs for the throttles under test.
    stub_feature_flags(
      rate_limiter_use_labkit_rack_cohort_1: true,
      rate_limiter_use_labkit_rack_cohort_2: true
    )
  end

  # Sum every labkit counter under a limiter's keyspace. The ':' delimiter after
  # the limiter name keeps rack_request from matching rack_request_protected_paths
  # or rack_request_incident_management, so each limiter is counted in isolation.
  def labkit_total_for(limiter)
    Gitlab::Redis::RateLimiting.with do |redis|
      keys = redis.scan_each(match: "labkit:rl:{#{limiter}:*").to_a
      keys.sum { |key| redis.get(key).to_i }
    end
  end

  # The same keyspace broken out per rule, as { rule_name => count }. Asserting the
  # whole hash says which rule counted and that nothing else did, which a total
  # cannot: a rule pair whose names share a prefix would otherwise be summed
  # together, and an unrelated throttle claiming the request would look identical.
  def labkit_counts_for(limiter)
    Gitlab::Redis::RateLimiting.with do |redis|
      redis.scan_each(match: "labkit:rl:{#{limiter}:*").to_a.each_with_object({}) do |key, counts|
        rule = key[/\{#{Regexp.escape(limiter)}:(.+?):/, 1]
        counts[rule] = counts.fetch(rule, 0) + redis.get(key).to_i
      end
    end
  end

  # Pre-load a rule's counter so an example can reach a 60-per-hour limit in two
  # requests rather than sixty-one. Writes the key layout labkit_counts_for reads
  # back, so a drift in it fails these examples rather than quietly skipping the
  # boundary: a key labkit does not recognise leaves the request counting from zero.
  def seed_labkit_counter(limiter, rule, count, ip: '127.0.0.1')
    Gitlab::Redis::RateLimiting.with do |redis|
      redis.set("labkit:rl:{#{limiter}:#{rule}:ip:#{ip}}", count)
    end
  end

  it 'counts one alerts/notify request in both the incident and web limiters' do
    post path

    expect(labkit_total_for('rack_request_incident_management')).to eq(1)
    expect(labkit_total_for('rack_request')).to eq(1)
  end

  # The tier-aware rollout must outlive the Rack::Attack migration flags.
  context 'with every migration cohort inactive' do
    before do
      stub_saas_features(gitlab_com_subscriptions: true)
      stub_feature_flags(
        rate_limiter_use_labkit_rack_cohort_1: false,
        rate_limiter_use_labkit_rack_cohort_2: false,
        rate_limiter_use_labkit_rack_cohort_3: false,
        rate_limiter_plan_limits_free_info: true
      )
    end

    it 'still evaluates the rules when a plan flag is on' do
      post path

      expect(labkit_total_for('rack_request')).to eq(1)
    end

    it 'evaluates nothing when the plan flags are off too' do
      stub_feature_flags(rate_limiter_plan_limits_free_info: false)

      post path

      expect(labkit_total_for('rack_request')).to eq(0)
    end

    # The state after the cohort flags are deleted: no cohort to enumerate, so no
    # cohort flag is read at all and the plan flags are the only thing running it.
    context 'when the registry declares no cohorts at all' do
      before do
        allow(Gitlab::RackAttack::LabkitRateLimit::ThrottleRegistry).to receive(:cohorts).and_return([])
      end

      it 'still evaluates the rules' do
        post path

        expect(labkit_total_for('rack_request')).to eq(1)
      end
    end
  end

  describe 'the unauthenticated per-IP throttle' do
    let(:anonymous_path) { '/api/v4/projects' }

    before do
      stub_saas_features(gitlab_com_subscriptions: true)
      stub_feature_flags(
        rate_limiter_use_labkit_rack_cohort_1: false,
        rate_limiter_use_labkit_rack_cohort_2: false,
        rate_limiter_use_labkit_rack_cohort_3: false
      )
      # for_limiter reads the SaaS gate at build time and the rule set is memoized,
      # so it must be rebuilt after the stub or an earlier example's build wins.
      Gitlab::RackAttack::LabkitRateLimit::Limiters.reset!
    end

    after do
      Gitlab::RackAttack::LabkitRateLimit::Limiters.reset!
    end

    it 'counts an anonymous request once the info flag is on' do
      stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)

      get anonymous_path

      expect(labkit_total_for('rack_request')).to eq(1)
    end

    it 'counts nothing while both flags are off' do
      get anonymous_path

      expect(labkit_total_for('rack_request')).to eq(0)
    end

    it 'counts nothing off GitLab.com even with the flag on' do
      stub_saas_features(gitlab_com_subscriptions: false)
      stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)

      get anonymous_path

      expect(labkit_total_for('rack_request')).to eq(0)
    end

    context 'with Git over HTTPS' do
      before do
        stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
        stub_application_setting(throttle_unauthenticated_enabled: true)
      end

      # Excluded from the plan rule but not ungoverned: throttle_unauthenticated_git_http
      # is off by default here, so the request falls through to the web throttle, which
      # claims it. One hash assertion covers both halves of that. LFS is covered by the
      # same exclusion, since repository_git_lfs_route_regex nests inside the git one.
      where(:case_name, :path) do
        'a git path'  | '/group/project.git/info/refs'
        'an LFS path' | '/group/project.git/info/lfs/objects/batch'
      end

      with_them do
        it 'leaves the request to an existing throttle instead of the plan rule' do
          get path

          expect(labkit_counts_for('rack_request')).to eq({ 'unauthenticated_web' => 1 })
        end
      end

      it 'still counts an unauthenticated non-git request under the plan rule' do
        get anonymous_path

        expect(labkit_counts_for('rack_request')).to eq({ 'unauthenticated_traffic_per_ip_log' => 1 })
      end
    end

    # The plan rule carries no setting_* fact and sits above every registry rule, so
    # the admin toggle that governs the generic throttles cannot gate it either way.
    describe 'independence from the unauthenticated admin setting' do
      before do
        stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
      end

      where(:setting) { [true, false] }

      with_them do
        it 'counts under the plan rule whether the setting is on or off' do
          stub_application_setting(throttle_unauthenticated_enabled: setting)

          get anonymous_path

          expect(labkit_counts_for('rack_request')).to include('unauthenticated_traffic_per_ip_log' => 1)
        end
      end
    end

    # The rule each flag combination selects, as the counter actually written. The
    # facts behind it are tabled in
    # ee/spec/lib/ee/gitlab/rack_attack/labkit_rate_limit/classified_request_spec.rb;
    # this is the rule those facts then select. Row 3 is the one worth having: enforce
    # without info counts nothing, so info alone is the off switch.
    describe 'the info and enforce flag combinations' do
      where(:info, :enforce, :counts) do
        false | false | {}
        true  | false | { 'unauthenticated_traffic_per_ip_log' => 1 }
        false | true  | {}
        true  | true  | { 'unauthenticated_traffic_per_ip' => 1 }
      end

      with_them do
        it 'counts under the rule the flags select' do
          stub_feature_flags(
            rate_limiter_unauthenticated_limits_info: info,
            rate_limiter_unauthenticated_limits_enforce: enforce
          )

          get anonymous_path

          expect(labkit_counts_for('rack_request')).to eq(counts)
        end
      end
    end

    describe 'enforcement at the published ceiling' do
      let(:limit) { 60 }
      let(:rule) { 'unauthenticated_traffic_per_ip' }

      before do
        stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
      end

      it 'allows the request at the limit and rejects the one past it', :aggregate_failures do
        stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)
        seed_labkit_counter('rack_request', rule, limit - 1)

        get anonymous_path
        expect(response).not_to have_gitlab_http_status(:too_many_requests)

        expect_rejection(rule) { get anonymous_path }
      end

      # The _log rule counts past its limit and never blocks, which is what makes
      # observe mode safe to leave on.
      it 'keeps counting past the limit without blocking while enforce is off', :aggregate_failures do
        seed_labkit_counter('rack_request', "#{rule}_log", limit)

        get anonymous_path

        expect(response).not_to have_gitlab_http_status(:too_many_requests)
        expect(labkit_counts_for('rack_request')).to eq({ "#{rule}_log" => limit + 1 })
      end
    end
  end

  describe 'enforcement and the admin setting toggle' do
    before do
      stub_feature_flags(
        rate_limiter_use_labkit_rack_cohort_1: true,
        rate_limiter_use_labkit_rack_cohort_1_enforce: true
      )
    end

    it 'rejects requests over the rate limit with the full RateLimit-* header set', :aggregate_failures do
      stub_application_setting(
        throttle_incident_management_notification_enabled: true,
        throttle_incident_management_notification_per_period: 1,
        throttle_incident_management_notification_period_in_seconds: 60
      )

      post path
      expect(response).not_to have_gitlab_http_status(:too_many_requests)

      expect_rejection('throttle_incident_management_notification_web') { post path }
    end

    it 'does not block requests over the same limit when the throttle setting is disabled', :aggregate_failures do
      stub_application_setting(
        throttle_incident_management_notification_enabled: false,
        throttle_incident_management_notification_per_period: 1,
        throttle_incident_management_notification_period_in_seconds: 60
      )

      3.times do
        post path
        expect(response).not_to have_gitlab_http_status(:too_many_requests)
      end
    end
  end

  # A plan-rule request is also counted by the general throttle below it: the
  # plan rules never claim, so evaluation continues into the registry rules.
  describe 'the per-plan throttles' do
    let_it_be(:project) { create(:project, :public) }
    let_it_be(:user) { create(:user) }
    let_it_be(:token) { create(:personal_access_token, user: user) }

    let(:path) { "/api/v4/projects/#{project.id}/issues" }
    let(:headers) { personal_access_token_headers(token) }

    before do
      stub_saas_features(gitlab_com_subscriptions: true)
      stub_application_setting(
        throttle_authenticated_api_enabled: true,
        throttle_authenticated_api_requests_per_period: 1000,
        throttle_authenticated_api_period_in_seconds: 60
      )
      stub_feature_flags(rate_limiter_plan_limits_free_info: true)
      # for_limiter reads the SaaS gate at build time and the rule set is memoized.
      Gitlab::RackAttack::LabkitRateLimit::Limiters.reset!
    end

    after do
      Gitlab::RackAttack::LabkitRateLimit::Limiters.reset!
    end

    def counter_for(rule_name)
      Gitlab::Redis::RateLimiting.with do |redis|
        keys = redis.scan_each(match: "labkit:rl:{rack_request:#{rule_name}:*").to_a
        keys.sum { |key| redis.get(key).to_i }
      end
    end

    it 'counts one request in the Free log rules and in the general throttle', :aggregate_failures do
      get path, headers: headers

      expect(response).to have_gitlab_http_status(:ok)
      expect(counter_for('authenticated_api')).to eq(1)
      expect(counter_for('sustained_traffic_per_user_free_plan_log')).to eq(1)
      expect(counter_for('burst_traffic_per_user_free_plan_log')).to eq(1)
      expect(counter_for('burst_traffic_per_namespace_free_plan_log')).to eq(1)
      expect(counter_for('sustained_traffic_per_namespace_free_plan_log')).to eq(1)
      expect(counter_for('burst_traffic_per_user_free_plan')).to eq(0)
    end

    it 'counts nothing in the plan rules while the flag is off' do
      stub_feature_flags(rate_limiter_plan_limits_free_info: false)

      get path, headers: headers

      expect(counter_for('sustained_traffic_per_user_free_plan_log')).to eq(0)
      expect(counter_for('authenticated_api')).to eq(1)
    end
  end
end
