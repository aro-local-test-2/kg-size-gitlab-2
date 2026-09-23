# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::RateLimit::PlanRules, feature_category: :rate_limiting do
  using RSpec::Parameterized::TableSyntax

  describe '.flags' do
    it 'is the eight flags the design document names' do
      expect(described_class.flags).to contain_exactly(
        :rate_limiter_plan_limits_free_info,
        :rate_limiter_plan_limits_free_enforce,
        :rate_limiter_plan_limits_premium_info,
        :rate_limiter_plan_limits_premium_enforce,
        :rate_limiter_plan_limits_ultimate_info,
        :rate_limiter_plan_limits_ultimate_enforce,
        :rate_limiter_unauthenticated_limits_info,
        :rate_limiter_unauthenticated_limits_enforce
      )
    end

    # An unmatched name silently leaves the real flag on across the suite.
    it 'names only flags with a definition' do
      described_class.flags.each do |flag|
        expect(Feature::Definition.get(flag)).to be_present, "#{flag} has no definition file"
      end
    end
  end

  describe '.active?' do
    context 'on GitLab.com' do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it 'is false while every flag is off' do
        expect(described_class.active?).to be(false)
      end

      # Driven off .flags so a flag added there without a matching read fails here.
      described_class.flags.each do |flag|
        it "is true when #{flag} alone is on" do
          stub_feature_flags(flag => true)

          expect(described_class.active?).to be(true)
        end
      end

      it 'reflects a flag flip rather than memoizing' do
        expect(described_class.active?).to be(false)

        stub_feature_flags(rate_limiter_plan_limits_free_info: true)

        expect(described_class.active?).to be(true)
      end

      it 'reads every flag with the request as actor and the derisk type' do
        allow(::Feature).to receive(:enabled?).and_return(false)

        described_class.active?

        described_class.flags.each do |flag|
          expect(::Feature).to have_received(:enabled?)
            .with(flag, ::Feature.current_request, type: :gitlab_com_derisk)
        end
      end
    end

    context 'when not on GitLab.com' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
        stub_feature_flags(described_class.flags.index_with(true))
      end

      it 'is false even with every flag on' do
        expect(described_class.active?).to be(false)
      end

      it 'rules the limits out before reading any flag' do
        expect(::Feature).not_to receive(:enabled?)

        described_class.active?
      end
    end
  end

  describe '.for_limiter' do
    let(:general) { ::Gitlab::RackAttack::LabkitRateLimit::ThrottleRegistry::GENERAL }
    let(:protected_paths) { ::Gitlab::RackAttack::LabkitRateLimit::ThrottleRegistry::PROTECTED }

    # The plan-independent pair first, then each plan as sustained user, burst user,
    # sustained namespace, burst namespace. Sustained before burst throughout. The
    # design doc's table lists the namespace pair the other way round, but both are
    # :log so the order there is cosmetic.
    # Spelled out rather than interpolated so every rule name is greppable.
    #
    # Per user enforces, because those are the published limits. Per namespace is
    # observe only, so it has no :limit twin.
    let(:expected_names) do
      %w[
        unauthenticated_traffic_per_ip
        unauthenticated_traffic_per_ip_log

        sustained_traffic_per_user_free_plan
        sustained_traffic_per_user_free_plan_log
        burst_traffic_per_user_free_plan
        burst_traffic_per_user_free_plan_log
        sustained_traffic_per_namespace_free_plan_log
        burst_traffic_per_namespace_free_plan_log

        sustained_traffic_per_user_premium_plan
        sustained_traffic_per_user_premium_plan_log
        burst_traffic_per_user_premium_plan
        burst_traffic_per_user_premium_plan_log
        sustained_traffic_per_namespace_premium_plan_log
        burst_traffic_per_namespace_premium_plan_log

        sustained_traffic_per_user_ultimate_plan
        sustained_traffic_per_user_ultimate_plan_log
        burst_traffic_per_user_ultimate_plan
        burst_traffic_per_user_ultimate_plan_log
        sustained_traffic_per_namespace_ultimate_plan_log
        burst_traffic_per_namespace_ultimate_plan_log
      ]
    end

    def rule(name)
      described_class.for_limiter(general).find { |candidate| candidate.name == name } ||
        raise("no rule named #{name}")
    end

    context 'on GitLab.com' do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it 'is the twenty rules in the design document order' do
        expect(described_class.for_limiter(general).map(&:name)).to eq(expected_names)
      end

      # Only the published per-user limits enforce. A namespace rule that blocked
      # would be enforcing a number no customer has been told about.
      it 'enforces per user only, never per namespace', :aggregate_failures do
        enforcing = described_class::PLAN_RULES.select { |rule| rule.action == :limit }

        expect(enforcing.size).to eq(6)
        enforcing.each do |rule|
          expect(rule.name).to include('_per_user_'), rule.name
        end
      end

      it 'is empty for the protected paths limiter' do
        expect(described_class.for_limiter(protected_paths)).to be_empty
      end

      it 'ends every :log rule name with _log and nothing else', :aggregate_failures do
        described_class.for_limiter(general).each do |candidate|
          expect(candidate.name.end_with?('_log')).to be(candidate.action == :log), candidate.name
        end
      end

      describe 'the unauthenticated pair' do
        let(:enforcing) { rule('unauthenticated_traffic_per_ip') }
        let(:logging) { rule('unauthenticated_traffic_per_ip_log') }

        it 'is 60 an hour per IP on both, the published unauthenticated ceiling', :aggregate_failures do
          [enforcing, logging].each do |candidate|
            expect(candidate.limit).to eq(60)
            expect(candidate.period).to eq(1.hour)
            expect(candidate.characteristics).to eq(%i[ip])
          end
        end

        it 'matches only a request with no requester and no runner', :aggregate_failures do
          [enforcing, logging].each do |candidate|
            expect(candidate.match[:requester_id].match?(nil)).to be(true)
            expect(candidate.match[:requester_id].match?('42')).to be(false)
            expect(candidate.match[:runner_id].match?(nil)).to be(true)
            expect(candidate.match[:runner_id].match?('7')).to be(false)
          end
        end

        it 'splits on unauthenticated_enforced', :aggregate_failures do
          expect(enforcing.match[:unauthenticated_enforced].match?(true)).to be(true)
          expect(enforcing.match[:unauthenticated_enforced].match?(false)).to be(false)
          expect(logging.match[:unauthenticated_enforced].match?(false)).to be(true)
          expect(logging.match[:unauthenticated_enforced].match?(true)).to be(false)
        end

        it 'requires unauthenticated_limits_active on both', :aggregate_failures do
          [enforcing, logging].each do |candidate|
            expect(candidate.match[:unauthenticated_limits_active].match?(true)).to be(true)
            expect(candidate.match[:unauthenticated_limits_active].match?(false)).to be(false)
          end
        end

        it 'requires git_http false on both, excluding Git over HTTPS', :aggregate_failures do
          [enforcing, logging].each do |rule|
            expect(rule.match[:git_http].match?(false)).to be(true)
            expect(rule.match[:git_http].match?(true)).to be(false)
          end
        end
      end

      # The matchers above only prove the gate is declared. This evaluates the pair
      # against the facts a real request carries, the way Labkit's evaluator does.
      describe 'the Git over HTTPS exclusion' do
        def matching_rule_names(path)
          facts = ::Gitlab::RackAttack::LabkitRateLimit::ClassifiedRequest
                    .new(Rack::MockRequest.env_for(path)).labkit_facts

          described_class.for_limiter(general)
            .select { |rule| rule.match.all? { |key, matcher| matcher.match?(facts[key]) } }
            .map(&:name)
        end

        before do
          stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
        end

        it 'leaves a git and an LFS request to throttle_unauthenticated_git_http', :aggregate_failures do
          expect(matching_rule_names('/group/project.git/info/refs')).to be_empty
          expect(matching_rule_names('/group/project.git/info/lfs/objects/batch')).to be_empty
        end

        it 'still counts an unauthenticated non-git request' do
          expect(matching_rule_names('/group/project')).to eq(%w[unauthenticated_traffic_per_ip_log])
        end
      end

      # The design document's Limits table, one row per plan budget. The Free
      # burst-per-namespace 400 is deliberate (the published 100, widened to
      # validate in log mode) and Ultimate burst per user is the revised 2,000.
      describe 'the plan budgets' do
        where(:plan, :kind, :limit, :period, :characteristics) do
          'free'     | 'sustained_traffic_per_user'      | 5_000   | 1.hour   | %i[requester_type requester_id]
          'free'     | 'burst_traffic_per_user'          | 100     | 1.minute | %i[requester_type requester_id]
          'free'     | 'burst_traffic_per_namespace'     | 400     | 1.minute | %i[target_root_namespace_id]
          'free'     | 'sustained_traffic_per_namespace' | 5_000   | 1.hour   | %i[target_root_namespace_id]
          'premium'  | 'sustained_traffic_per_user'      | 15_000  | 1.hour   | %i[requester_type requester_id]
          'premium'  | 'burst_traffic_per_user'          | 1_250   | 1.minute | %i[requester_type requester_id]
          'premium'  | 'burst_traffic_per_namespace'     | 5_000   | 1.minute | %i[target_root_namespace_id]
          'premium'  | 'sustained_traffic_per_namespace' | 60_000  | 1.hour   | %i[target_root_namespace_id]
          'ultimate' | 'sustained_traffic_per_user'      | 25_000  | 1.hour   | %i[requester_type requester_id]
          'ultimate' | 'burst_traffic_per_user'          | 2_000   | 1.minute | %i[requester_type requester_id]
          'ultimate' | 'burst_traffic_per_namespace'     | 10_000  | 1.minute | %i[target_root_namespace_id]
          'ultimate' | 'sustained_traffic_per_namespace' | 100_000 | 1.hour   | %i[target_root_namespace_id]
        end

        with_them do
          let(:logging) { rule("#{kind}_#{plan}_plan_log") }
          let(:plan_fact) { kind.end_with?('_namespace') ? :target_namespace_plan : :requester_plan }
          let(:observe_only) { kind.end_with?('_namespace') }
          let(:info_fact) { :"plan_limits_#{plan}_info" }
          let(:enforce_fact) { :"plan_limits_#{plan}_enforce" }

          it 'carries the limit, period and counter key from the Limits table', :aggregate_failures do
            rules = observe_only ? [logging] : [rule("#{kind}_#{plan}_plan"), logging]

            rules.each do |candidate|
              expect(candidate.limit).to eq(limit), candidate.name
              expect(candidate.period).to eq(period), candidate.name
              expect(candidate.characteristics).to eq(characteristics), candidate.name
            end
          end

          it 'matches its own plan and a present requester only', :aggregate_failures do
            expect(logging.match[plan_fact].match?(plan)).to be(true)
            expect(logging.match[plan_fact].match?(nil)).to be(false)
            expect(logging.match[plan_fact].match?('bronze')).to be(false)
            expect(logging.match[:requester_id].match?('42')).to be(true)
            expect(logging.match[:requester_id].match?(nil)).to be(false)
          end

          # Every rule states info-gates-enforce itself now, rather than reading a
          # boolean FlagPolicy had already combined.
          it 'requires its own info flag' do
            expect(logging.match[info_fact].match?(true)).to be(true)
            expect(logging.match[info_fact].match?(false)).to be(false)
          end

          it 'splits the per-user pair on the enforce flag, and leaves namespace observe only',
            :aggregate_failures do
            if observe_only
              expect(described_class.for_limiter(general).map(&:name)).not_to include("#{kind}_#{plan}_plan")
              expect(logging.match).not_to have_key(enforce_fact)
              expect(logging.action).to eq(:log)
            else
              enforcing = rule("#{kind}_#{plan}_plan")

              expect(enforcing.action).to eq(:limit)
              expect(enforcing.match[enforce_fact].match?(true)).to be(true)
              expect(enforcing.match[enforce_fact].match?(false)).to be(false)
              expect(logging.action).to eq(:log)
              expect(logging.match[enforce_fact].match?(false)).to be(true)
              expect(logging.match[enforce_fact].match?(true)).to be(false)
            end
          end
        end
      end

      # GraphQL carries its target in the body, so TargetKey derives no namespace
      # for /api/graphql and the fact is nil. The per-user rules still apply.
      it 'matches no namespace rule without a target namespace, while the user rules still match',
        :aggregate_failures do
        rules = described_class.for_limiter(general)
        namespace_rules = rules.select { |candidate| candidate.name.include?('_namespace_') }
        user_rules = rules.select { |candidate| candidate.name.include?('_user_') }

        expect(namespace_rules.size).to eq(6)
        namespace_rules.each do |candidate|
          expect(candidate.match[:target_root_namespace_id].match?(nil)).to be(false), candidate.name
          expect(candidate.match[:target_root_namespace_id].match?('9970')).to be(true), candidate.name
        end

        expect(user_rules.size).to eq(12)
        user_rules.each do |candidate|
          expect(candidate.match).not_to have_key(:target_root_namespace_id), candidate.name
        end
      end
    end

    context 'when not on GitLab.com' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      it 'is empty for the general limiter' do
        expect(described_class.for_limiter(general)).to be_empty
      end
    end
  end

  # The tiers the rules are keyed by are the ones Plan.tier_for can return, and
  # that mapping is the design document's Plan Name Mapping table.
  describe 'plan name mapping' do
    let(:rule_tiers) do
      described_class::PLAN_RULES.filter_map { |rule| rule.name[/_([^_]+)_plan(?:_log)?\z/, 1] }.uniq
    end

    where(:plan_name, :tier) do
      nil                            | 'free'
      'default'                      | 'free'
      'free'                         | 'free'
      'early_adopter'                | 'free'
      'bronze'                       | 'premium'
      'silver'                       | 'premium'
      'premium'                      | 'premium'
      'premium_trial'                | 'premium'
      'opensource'                   | 'ultimate'
      'gold'                         | 'ultimate'
      'ultimate'                     | 'ultimate'
      'ultimate_trial'               | 'ultimate'
      'ultimate_trial_paid_customer' | 'ultimate'
    end

    with_them do
      it 'collapses the plan name onto a tier the rules know' do
        expect(::Plan.tier_for(plan_name)).to eq(tier)
        expect(rule_tiers).to include(tier)
      end
    end

    it 'has rules for every tier, in rank order' do
      expect(rule_tiers).to eq(::Plan::TIERS)
    end
  end
end
