# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SecretsManagement::Entitlement::Resolver, :clean_gitlab_redis_shared_state,
  feature_category: :secrets_management do
  # Refind so the has_one gitlab_subscription association cache does not
  # leak between examples (the resolver reads it via the shared instance).
  let_it_be_with_refind(:root_group) { create(:group) }

  let(:resolver_user) { nil }

  subject(:resolved) { described_class.new(namespace, user: resolver_user).resolve }

  describe '#resolve' do
    context 'on self-managed with an offline cloud license' do
      let(:namespace) { nil }

      before do
        stub_saas_features(gitlab_com_subscriptions: false)
        allow(::License).to receive(:current).and_return(
          instance_double(License, online_cloud_license?: false, trial?: false)
        )
      end

      # The slot exists to bridge a CDot outage. Offline installs never call CDot, so a write here
      # would persist answers that can never be served, and would add a SharedState round trip to
      # every policy check.
      it 'never touches the last-known-good slot' do
        expect(SecretsManagement::Entitlement::LastKnownGoodStore).not_to receive(:write)
        expect(SecretsManagement::Entitlement::LastKnownGoodStore).not_to receive(:read)

        resolved
      end

      context 'with an active self-managed secrets manager add-on purchase' do
        before do
          create(:gitlab_subscription_add_on_purchase, :active, :secrets_manager, :self_managed)
        end

        it 'returns :offline_paid' do
          expect(resolved.state).to eq(:offline_paid)
        end

        it 'permits writes' do
          expect(resolved.permits_writes?).to be true
        end

        it 'leaves on_demand_enabled unresolved (nil) -- N/A on offline installs' do
          expect(resolved.on_demand_enabled).to be_nil
        end
      end

      context 'without an active self-managed secrets manager add-on purchase' do
        it 'returns :blocked + :subscription_grace_period_expired', :aggregate_failures do
          expect(resolved.state).to eq(:blocked)
          expect(resolved.blocked_reason).to eq(:subscription_grace_period_expired)
        end

        it 'does not permit writes' do
          expect(resolved.permits_writes?).to be false
        end
      end

      context 'with an expired self-managed secrets manager add-on purchase' do
        before do
          create(:gitlab_subscription_add_on_purchase, :expired, :secrets_manager, :self_managed)
        end

        it 'returns :blocked + :subscription_grace_period_expired', :aggregate_failures do
          expect(resolved.state).to eq(:blocked)
          expect(resolved.blocked_reason).to eq(:subscription_grace_period_expired)
        end
      end

      context 'with an active add-on tied to a namespace (not instance-wide)' do
        before do
          create(:gitlab_subscription_add_on_purchase, :active, :secrets_manager, namespace: root_group)
        end

        it 'is ignored -- offline branch only looks at instance-level purchases', :aggregate_failures do
          expect(resolved.state).to eq(:blocked)
          expect(resolved.blocked_reason).to eq(:subscription_grace_period_expired)
        end
      end
    end

    context 'on self-managed with no license installed' do
      let(:namespace) { nil }

      before do
        stub_saas_features(gitlab_com_subscriptions: false)
        allow(::License).to receive(:current).and_return(nil)
      end

      it 'returns :ineligible -- no license == no entitlement' do
        expect(resolved.state).to eq(:ineligible)
      end

      it 'does not consult AddOnPurchase (short-circuits before routing)' do
        expect(::GitlabSubscriptions::AddOnPurchase).not_to receive(:for_secrets_manager)

        resolved
      end

      it 'is unaffected by stray AddOnPurchase rows from an earlier license', :aggregate_failures do
        create(:gitlab_subscription_add_on_purchase, :active, :secrets_manager, :self_managed)

        expect(resolved.state).to eq(:ineligible)
        expect(resolved.blocked_reason).to be_nil
      end
    end

    context 'on SaaS with no license installed', :saas do
      let(:namespace) { root_group }

      before do
        stub_saas_features(gitlab_com_subscriptions: true)
        allow(::License).to receive(:current).and_return(nil)
      end

      it 'returns :ineligible without asking CDot', :aggregate_failures do
        expect(::Gitlab::SubscriptionPortal::Client).not_to receive(:secrets_manager_trial)
        expect(::Gitlab::SubscriptionPortal::Client).not_to receive(:secrets_manager_consumer_resolve)

        expect(resolved.state).to eq(:ineligible)
      end
    end

    shared_examples 'cloud branch precedence table' do
      let(:cdot_trial) do
        ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(
          state: trial_state,
          trial_started_at: trial_started_at,
          trial_expires_at: trial_expires_at,
          credits_remaining: credits_remaining,
          credits_total: credits_total,
          on_demand_enabled: on_demand_enabled
        )
      end

      let(:cdot_resolve) do
        ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(
          blocked: blocked,
          blocked_reason: blocked_reason
        )
      end

      let(:trial_started_at)  { 5.days.ago }
      let(:trial_expires_at)  { 25.days.from_now }
      let(:blocked)           { false }
      let(:blocked_reason)    { nil }
      let(:credits_remaining) { 100 }
      let(:credits_total)     { 500 }
      let(:on_demand_enabled) { true }

      before do
        allow(::Gitlab::SubscriptionPortal::Client)
          .to receive(:secrets_manager_trial).with(expected_client_kwargs).and_return(cdot_trial)
        allow(::Gitlab::SubscriptionPortal::Client)
          .to receive(:secrets_manager_consumer_resolve)
          .with(expected_client_kwargs.merge(user_id: resolver_user&.id)).and_return(cdot_resolve)
      end

      context 'with CDot state :trial_eligible (no trial yet)' do
        let(:trial_state)       { :trial_eligible }
        let(:trial_started_at)  { nil }
        let(:credits_remaining) { nil }
        let(:credits_total)     { nil }
        let(:on_demand_enabled) { nil }

        it 'returns :trial_eligible without quota fields', :aggregate_failures do
          expect(resolved.state).to eq(:trial_eligible)
          expect(resolved.blocked_reason).to be_nil
          expect(resolved.credits_total).to be_nil
          expect(resolved.on_demand_enabled).to be_nil
          expect(resolved.permits_writes?).to be false
        end

        it 'denies direct reads once the beta cutoff is active (flag on)', :aggregate_failures do
          expect(resolved.beta_program_ended).to be true
          expect(resolved.permits_direct_read?).to be false
        end

        context 'when the beta cutoff is not active yet' do
          before do
            stub_feature_flags(end_secrets_manager_beta_program: false)
          end

          it 'keeps permitting direct reads', :aggregate_failures do
            expect(resolved.beta_program_ended).to be false
            expect(resolved.permits_direct_read?).to be true
          end
        end

        context 'when the customer has already opted in to on-demand billing' do
          let(:on_demand_enabled) { true }

          it 'propagates on_demand_enabled from /trials' do
            expect(resolved.on_demand_enabled).to be true
          end
        end
      end

      context 'with CDot state :trial_eligible blocked on on_demand_disabled' do
        let(:trial_state)       { :trial_eligible }
        let(:trial_started_at)  { nil }
        let(:blocked)           { true }
        let(:blocked_reason)    { :on_demand_disabled }
        let(:credits_remaining) { nil }
        let(:credits_total)     { nil }
        let(:on_demand_enabled) { false }

        it 'keeps :trial_eligible so the trial stays reachable', :aggregate_failures do
          expect(resolved.state).to eq(:trial_eligible)
          expect(resolved.blocked_reason).to be_nil
          expect(resolved.permits_writes?).to be false
          expect(resolved.write_action_denial_reason).to eq(:trial_required)
        end

        it 'carries the beta cutoff through the un-blocked path', :aggregate_failures do
          expect(resolved.beta_program_ended).to be true
          expect(resolved.permits_direct_read?).to be false
        end

        context 'when the beta cutoff is not active yet' do
          before do
            stub_feature_flags(end_secrets_manager_beta_program: false)
          end

          it 'keeps permitting direct reads', :aggregate_failures do
            expect(resolved.beta_program_ended).to be false
            expect(resolved.permits_direct_read?).to be true
          end
        end
      end

      context 'with CDot state :trial_eligible blocked on an enforcing reason' do
        let(:trial_state)    { :trial_eligible }
        let(:blocked)        { true }
        let(:blocked_reason) { :credits_exhausted }

        it 'stays :blocked (only on_demand_disabled is a pre-trial default)', :aggregate_failures do
          expect(resolved.state).to eq(:blocked)
          expect(resolved.blocked_reason).to eq(:credits_exhausted)
        end
      end

      context 'with CDot state :trial_eligible blocked with no reason given' do
        let(:trial_state)    { :trial_eligible }
        let(:blocked)        { true }
        let(:blocked_reason) { nil }

        it 'fails closed to :ineligible rather than offering a trial' do
          expect(resolved.state).to eq(:ineligible)
        end
      end

      context 'with an active trial, not blocked' do
        let(:trial_state) { :trial }

        it 'returns :trial with quota fields from /trials', :aggregate_failures do
          expect(resolved.state).to eq(:trial)
          expect(resolved.credits_remaining).to eq(100)
          expect(resolved.credits_total).to eq(500)
          expect(resolved.on_demand_enabled).to be true
          expect(resolved.permits_writes?).to be true
        end
      end

      context 'with an active trial blocked on on_demand_disabled (CDot combined state)' do
        let(:trial_state)       { :trial }
        let(:blocked)           { true }
        let(:blocked_reason)    { :on_demand_disabled }
        let(:on_demand_enabled) { false }
        let(:credits_remaining) { 0 }

        it 'translates to :credits_exhausted and preserves credits_total', :aggregate_failures do
          expect(resolved.state).to eq(:blocked)
          expect(resolved.blocked_reason).to eq(:credits_exhausted)
          expect(resolved.credits_remaining).to eq(0)
          expect(resolved.credits_total).to eq(500)
          expect(resolved.permits_writes?).to be false
        end
      end

      context 'with an expired trial, not blocked (paid)' do
        let(:trial_state) { :expired }

        it 'returns :paid with on_demand_enabled but no credit fields', :aggregate_failures do
          expect(resolved.state).to eq(:paid)
          expect(resolved.on_demand_enabled).to be true
          expect(resolved.credits_remaining).to be_nil
          expect(resolved.credits_total).to be_nil
          expect(resolved.permits_writes?).to be true
        end
      end

      context 'with an expired trial blocked on on_demand_disabled' do
        let(:trial_state)       { :expired }
        let(:blocked)           { true }
        let(:blocked_reason)    { :on_demand_disabled }
        let(:on_demand_enabled) { false }

        it 'relabels to :trial_expired (never-bought trial under an active paid source)', :aggregate_failures do
          expect(resolved.state).to eq(:blocked)
          expect(resolved.blocked_reason).to eq(:trial_expired)
          expect(resolved.permits_writes?).to be false
        end
      end

      context 'with CDot state :ineligible' do
        let(:trial_state) { :ineligible }

        it 'returns :ineligible' do
          expect(resolved.state).to eq(:ineligible)
        end
      end

      context 'with CDot state :trial_eligible blocked on usage_not_allowed' do
        let(:trial_state)       { :trial_eligible }
        let(:trial_started_at)  { nil }
        let(:blocked)           { true }
        let(:blocked_reason)    { :usage_not_allowed }
        let(:credits_remaining) { nil }
        let(:credits_total)     { nil }
        let(:on_demand_enabled) { nil }

        it 'keeps :trial_eligible so the trial stays reachable', :aggregate_failures do
          expect(resolved.state).to eq(:trial_eligible)
          expect(resolved.blocked_reason).to be_nil
          expect(resolved.write_action_denial_reason).to eq(:trial_required)
        end
      end

      context 'with an active trial blocked on usage_not_allowed' do
        let(:trial_state)       { :trial }
        let(:blocked)           { true }
        let(:blocked_reason)    { :usage_not_allowed }
        let(:credits_remaining) { 0 }

        it 'translates to :credits_exhausted like on_demand_disabled', :aggregate_failures do
          expect(resolved.state).to eq(:blocked)
          expect(resolved.blocked_reason).to eq(:credits_exhausted)
        end
      end

      context 'with an expired trial blocked on usage_not_allowed' do
        let(:trial_state)    { :expired }
        let(:blocked)        { true }
        let(:blocked_reason) { :usage_not_allowed }

        it 'relabels to :trial_expired like on_demand_disabled', :aggregate_failures do
          expect(resolved.state).to eq(:blocked)
          expect(resolved.blocked_reason).to eq(:trial_expired)
        end
      end

      context 'with CDot state :ineligible blocked on usage_not_allowed' do
        let(:trial_state)       { :ineligible }
        let(:trial_started_at)  { nil }
        let(:blocked)           { true }
        let(:blocked_reason)    { :usage_not_allowed }
        let(:credits_remaining) { nil }
        let(:credits_total)     { nil }
        let(:on_demand_enabled) { nil }

        it 'returns :ineligible without tracking -- the expected plan-trial shape', :aggregate_failures do
          expect(::Gitlab::ErrorTracking).not_to receive(:track_exception)

          expect(resolved.state).to eq(:ineligible)
          expect(resolved.blocked_reason).to be_nil
        end
      end

      context 'when blocked on a reason outside the client allowlist' do
        let(:trial_state)    { :ineligible }
        let(:blocked)        { true }
        let(:blocked_reason) { :below_min_gitlab_version }

        it 'fails closed to :ineligible without raising', :aggregate_failures do
          expect(resolved.state).to eq(:ineligible)
          expect(resolved.blocked_reason).to be_nil
        end

        it 'tracks the unmapped reason so it reaches Sentry' do
          expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(
            an_instance_of(::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse::Error)
              .and(having_attributes(message: /below_min_gitlab_version/)),
            hash_including(issue_type: 'secrets_management_entitlement_fail_closed')
          )

          resolved
        end

        context 'with a real cache store', :use_clean_rails_memory_store_caching do
          it 'reports to Sentry once per dedup window, logging the occurrences it suppresses',
            :aggregate_failures do
            expect(::Gitlab::ErrorTracking).to receive(:track_exception).once.with(
              an_instance_of(::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse::Error),
              hash_including(issue_type: 'secrets_management_entitlement_fail_closed')
            )
            expect(::Gitlab::ErrorTracking).to receive(:log_exception).once.with(
              an_instance_of(::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse::Error)
                .and(having_attributes(message: /below_min_gitlab_version/)),
              hash_including(issue_type: 'secrets_management_entitlement_fail_closed')
            )

            2.times { described_class.new(namespace, user: resolver_user).resolve }
          end

          it 'reports again once the dedup window has passed' do
            expect(::Gitlab::ErrorTracking).to receive(:track_exception).twice

            described_class.new(namespace, user: resolver_user).resolve
            travel_to((described_class::UNMAPPED_REASON_REPORT_TTL + 1.minute).from_now) do
              described_class.new(namespace, user: resolver_user).resolve
            end
          end
        end
      end

      context 'when blocked on a reason outside the client allowlist with CDot state :trial_eligible' do
        let(:trial_state)       { :trial_eligible }
        let(:trial_started_at)  { nil }
        let(:blocked)           { true }
        let(:blocked_reason)    { :below_min_gitlab_version }
        let(:credits_remaining) { nil }
        let(:credits_total)     { nil }
        let(:on_demand_enabled) { nil }

        it 'fails closed to :ineligible instead of offering a trial (not a default-deny reason)',
          :aggregate_failures do
          expect(resolved.state).to eq(:ineligible)
          expect(resolved.blocked_reason).to be_nil
        end
      end

      context 'when resolve.blocked=true overrides lifecycle for any trial state' do
        let(:trial_state)    { :trial }
        let(:blocked)        { true }
        let(:blocked_reason) { :subscription_grace_period_expired }

        it 'returns :blocked + the resolve.blocked_reason regardless of trial.state' do
          expect(resolved.state).to eq(:blocked)
          expect(resolved.blocked_reason).to eq(:subscription_grace_period_expired)
        end
      end
    end

    context 'on SaaS', :saas do
      let(:namespace) { root_group }
      let(:expected_client_kwargs) { { namespace_id: root_group.id } }

      before do
        stub_saas_features(gitlab_com_subscriptions: true)
        # gitlab.com prod is itself an online cloud license -- mirror that
        # here so the cloud-vs-offline routing matches production reality.
        allow(::License).to receive(:current).and_return(
          instance_double(License, online_cloud_license?: true)
        )
      end

      it 'does not look at AddOnPurchase records' do
        expect(::GitlabSubscriptions::AddOnPurchase).not_to receive(:for_secrets_manager)

        allow(::Gitlab::SubscriptionPortal::Client).to receive_messages(
          secrets_manager_trial: nil,
          secrets_manager_consumer_resolve: nil
        )

        resolved
      end

      context 'when the secrets_manager_paid_experience feature flag is disabled' do
        before do
          stub_feature_flags(secrets_manager_paid_experience: false)
        end

        it 'returns :ineligible without calling CDot', :aggregate_failures do
          expect(::Gitlab::SubscriptionPortal::Client).not_to receive(:secrets_manager_trial)
          expect(::Gitlab::SubscriptionPortal::Client).not_to receive(:secrets_manager_consumer_resolve)

          expect(resolved.state).to eq(:ineligible)
        end
      end

      context 'with a nil namespace (personal namespace on SaaS has no instance-level entitlement)' do
        let(:namespace) { nil }

        it 'returns :ineligible without calling CDot', :aggregate_failures do
          expect(::Gitlab::SubscriptionPortal::Client).not_to receive(:secrets_manager_trial)
          expect(::Gitlab::SubscriptionPortal::Client).not_to receive(:secrets_manager_consumer_resolve)

          expect(resolved.state).to eq(:ineligible)
        end
      end

      context 'when either CDot call returns nil (requests disabled)' do
        before do
          allow(::Gitlab::SubscriptionPortal::Client).to receive_messages(
            secrets_manager_trial: nil,
            secrets_manager_consumer_resolve: nil
          )
        end

        it 'fails closed and returns :ineligible' do
          expect(resolved.state).to eq(:ineligible)
        end
      end

      describe 'precedence table' do
        include_examples 'cloud branch precedence table'
      end

      context 'with recorded add-on intent (paid without a trial)' do
        let(:cdot_trial) do
          ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(
            state: :trial_eligible, on_demand_enabled: true
          )
        end

        let(:cdot_resolve) do
          ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false)
        end

        before do
          allow(::Gitlab::SubscriptionPortal::Client).to receive_messages(
            secrets_manager_trial: cdot_trial,
            secrets_manager_consumer_resolve: cdot_resolve
          )
        end

        context 'when the enrollment carries add-on intent and resolve allows access' do
          before do
            create(:secrets_manager_namespace_enrollment, :add_on_requested, namespace: root_group)
          end

          it 'returns :paid without trial fields', :aggregate_failures do
            expect(resolved.state).to eq(:paid)
            expect(resolved.trial_started_at).to be_nil
            expect(resolved.trial_expires_at).to be_nil
            expect(resolved.on_demand_enabled).to be true
            expect(resolved.permits_writes?).to be true
          end

          it 'closes the beta window (paid is a converted state)' do
            expect(resolved.beta_window_eligible).to be false
          end

          context 'when resolve blocks on on_demand_disabled (acceptance reset by renewal)' do
            let(:cdot_resolve) do
              ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(
                blocked: true, blocked_reason: :on_demand_disabled
              )
            end

            it 'falls back to :trial_eligible instead of silently staying paid' do
              expect(resolved.state).to eq(:trial_eligible)
            end
          end

          context 'when the trial offer sunsets on CDot (state :ineligible, resolve still allows)' do
            let(:cdot_trial) do
              ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: :ineligible)
            end

            it 'stays :paid -- the customer is still billed and must keep access', :aggregate_failures do
              expect(resolved.state).to eq(:paid)
              expect(resolved.permits_writes?).to be true
            end
          end

          context 'when the trial state is :ineligible and resolve blocks' do
            let(:cdot_trial) do
              ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: :ineligible)
            end

            let(:cdot_resolve) do
              ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(
                blocked: true, blocked_reason: :usage_not_allowed
              )
            end

            it 'does not let the intent override enforcement' do
              expect(resolved.state).to eq(:ineligible)
            end
          end
        end

        context 'when the enrollment has no add-on intent' do
          before do
            create(:secrets_manager_namespace_enrollment, namespace: root_group)
          end

          it 'keeps :trial_eligible (plain enrollment is not paid intent)' do
            expect(resolved.state).to eq(:trial_eligible)
          end
        end

        context 'when the enrollment with add-on intent is disabled (opt-out)' do
          before do
            create(:secrets_manager_namespace_enrollment, :disabled, :add_on_requested, namespace: root_group)
          end

          it 'keeps :trial_eligible' do
            expect(resolved.state).to eq(:trial_eligible)
          end
        end
      end

      describe '.clear_cache' do
        let(:cdot_trial) do
          ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(
            state: :trial_eligible, on_demand_enabled: true
          )
        end

        let(:cdot_resolve) do
          ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false)
        end

        before do
          allow(::Gitlab::SubscriptionPortal::Client).to receive_messages(
            secrets_manager_trial: cdot_trial,
            secrets_manager_consumer_resolve: cdot_resolve
          )
        end

        it 'drops the memoized entitlement so intent recorded mid-request is visible',
          :request_store, :aggregate_failures do
          expect(resolved.state).to eq(:trial_eligible)

          create(:secrets_manager_namespace_enrollment, :add_on_requested, namespace: root_group)

          expect(described_class.new(namespace, user: resolver_user).resolve.state).to eq(:trial_eligible)

          described_class.clear_cache(namespace)

          expect(described_class.new(namespace, user: resolver_user).resolve.state).to eq(:paid)
        end

        it 'drops the cache_ttl layer too', :use_clean_rails_memory_store_caching, :aggregate_failures do
          resolve_with_ttl = -> { described_class.new(namespace, user: resolver_user, cache_ttl: 5.minutes).resolve! }

          expect(resolve_with_ttl.call.state).to eq(:trial_eligible)

          create(:secrets_manager_namespace_enrollment, :add_on_requested, namespace: root_group)

          expect(resolve_with_ttl.call.state).to eq(:trial_eligible)

          described_class.clear_cache(namespace)

          expect(resolve_with_ttl.call.state).to eq(:paid)
        end
      end

      context 'when blocked with no_billable_source_error (grace computed locally from end_date)' do
        let(:grace_days) { SecretsManagement::Entitlement::GRACE_DAYS }

        before do
          # Grace derives solely from the subscription end_date; the trial
          # response's state and on-demand opt-in play no part here.
          allow(::Gitlab::SubscriptionPortal::Client).to receive_messages(
            secrets_manager_trial: ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(
              state: :expired, on_demand_enabled: true
            ),
            secrets_manager_consumer_resolve:
              ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(
                blocked: true, blocked_reason: :no_billable_source_error
              )
          )
        end

        context 'with a subscription end_date inside the grace window' do
          before do
            create(:gitlab_subscription, namespace: root_group, end_date: Date.current - 5.days)
          end

          it 'returns :blocked + :grace (read-only window)', :aggregate_failures do
            expect(resolved.state).to eq(:blocked)
            expect(resolved.blocked_reason).to eq(:grace)
            expect(resolved.in_grace?).to be true
            expect(resolved.permits_direct_read?).to be true
            expect(resolved.permits_writes?).to be false
          end
        end

        context 'on the last day of the grace window (end_date + GRACE_DAYS == today)', :freeze_time do
          before do
            create(:gitlab_subscription, namespace: root_group, end_date: Date.current - grace_days.days)
          end

          it 'still returns :grace' do
            expect(resolved.blocked_reason).to eq(:grace)
          end
        end

        context 'with the grace window elapsed' do
          before do
            create(:gitlab_subscription, namespace: root_group, end_date: Date.current - (grace_days + 1).days)
          end

          it 'returns :blocked + :subscription_grace_period_expired (full lockout)', :aggregate_failures do
            expect(resolved.state).to eq(:blocked)
            expect(resolved.blocked_reason).to eq(:subscription_grace_period_expired)
            expect(resolved.in_grace?).to be false
            expect(resolved.permits_direct_read?).to be false
          end
        end

        context 'with a mid-term-cancelled subscription (end_date still in the future)' do
          before do
            # Cancelled paid customer with on-demand off: trialled first, so
            # the trial record reads :expired -- must not become :trial_expired.
            allow(::Gitlab::SubscriptionPortal::Client).to receive(:secrets_manager_trial).and_return(
              ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: :expired)
            )
            create(:gitlab_subscription, namespace: root_group, end_date: Date.current + 6.months)
          end

          it 'returns :grace (read-only through the paid term plus the window)', :aggregate_failures do
            expect(resolved.state).to eq(:blocked)
            expect(resolved.blocked_reason).to eq(:grace)
            expect(resolved.in_grace?).to be true
            expect(resolved.permits_direct_read?).to be true
            expect(resolved.permits_writes?).to be false
          end
        end

        context 'with a plan-trial subscription row (trial: true, future end_date)' do
          before do
            create(:gitlab_subscription, :active_trial, namespace: root_group, end_date: Date.current + 20.days)
          end

          it 'does not open the grace window: fails closed to :subscription_grace_period_expired',
            :aggregate_failures do
            expect(resolved.state).to eq(:blocked)
            expect(resolved.blocked_reason).to eq(:subscription_grace_period_expired)
          end

          context 'without any SM trial history' do
            before do
              allow(::Gitlab::SubscriptionPortal::Client).to receive(:secrets_manager_trial).and_return(
                ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: :trial_eligible)
              )
            end

            it 'fails closed to :subscription_grace_period_expired' do
              expect(resolved.blocked_reason).to eq(:subscription_grace_period_expired)
            end
          end
        end
      end

      context 'when blocked with no_billable_source_error and no subscription evidence' do
        before do
          allow(::Gitlab::SubscriptionPortal::Client).to receive_messages(
            secrets_manager_trial: ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: :expired),
            secrets_manager_consumer_resolve:
              ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(
                blocked: true, blocked_reason: :no_billable_source_error
              )
          )
        end

        context 'with an expired trial and no gitlab_subscription' do
          it 'fails closed to :subscription_grace_period_expired (no grace window)', :aggregate_failures do
            expect(resolved.state).to eq(:blocked)
            expect(resolved.blocked_reason).to eq(:subscription_grace_period_expired)
            expect(resolved.in_grace?).to be false
            expect(resolved.permits_direct_read?).to be false
            expect(resolved.permits_read?).to be true
            expect(resolved.permits_writes?).to be false
          end

          it 'does not consult the SM purchase mirror (SaaS anchors on gitlab_subscription only)' do
            expect(::GitlabSubscriptions::AddOnPurchase).not_to receive(:for_secrets_manager)

            expect(resolved.blocked_reason).to eq(:subscription_grace_period_expired)
          end
        end

        context 'with an expired trial and a subscription that has no end_date' do
          before do
            create(:gitlab_subscription, namespace: root_group, end_date: nil)
          end

          it 'fails closed to :subscription_grace_period_expired' do
            expect(resolved.blocked_reason).to eq(:subscription_grace_period_expired)
          end
        end

        context 'without any trial history (trial state is not :expired)' do
          before do
            allow(::Gitlab::SubscriptionPortal::Client).to receive(:secrets_manager_trial).and_return(
              ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: :trial_eligible)
            )
          end

          it 'fails closed to :subscription_grace_period_expired', :aggregate_failures do
            expect(resolved.state).to eq(:blocked)
            expect(resolved.blocked_reason).to eq(:subscription_grace_period_expired)
          end
        end
      end

      context 'with the beta cutoff flag scoped per namespace' do
        before do
          allow(::Gitlab::SubscriptionPortal::Client)
            .to receive(:secrets_manager_trial).with(namespace_id: root_group.id)
            .and_return(::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: :trial_eligible))
          allow(::Gitlab::SubscriptionPortal::Client)
            .to receive(:secrets_manager_consumer_resolve)
            .with(namespace_id: root_group.id, user_id: nil)
            .and_return(::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false))
        end

        context 'when the flag is enabled for the resolved namespace' do
          before do
            stub_feature_flags(end_secrets_manager_beta_program: root_group)
          end

          it 'ends the beta program for it' do
            expect(resolved.beta_program_ended).to be true
          end
        end

        context 'when the flag is enabled only for an unrelated group' do
          before do
            stub_feature_flags(end_secrets_manager_beta_program: create(:group))
          end

          it 'keeps the beta program active' do
            expect(resolved.beta_program_ended).to be false
          end
        end
      end

      context 'with beta enrollment for the resolved namespace' do
        before do
          allow(::Gitlab::SubscriptionPortal::Client)
            .to receive(:secrets_manager_trial).with(namespace_id: root_group.id)
            .and_return(::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: :trial_eligible))
          allow(::Gitlab::SubscriptionPortal::Client)
            .to receive(:secrets_manager_consumer_resolve)
            .with(namespace_id: root_group.id, user_id: nil)
            .and_return(::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false))
        end

        context 'when the namespace is enrolled in the beta cohort' do
          before do
            create(:secrets_manager_namespace_enrollment, namespace: root_group, beta: true)
          end

          it 'resolves beta_window_eligible' do
            expect(resolved.beta_window_eligible).to be true
          end

          it 'never consults the self-managed instance enrollment' do
            allow(::SecretsManagement::InstanceEnrollment).to receive(:beta_enrolled?).and_call_original

            resolved

            expect(::SecretsManagement::InstanceEnrollment).not_to have_received(:beta_enrolled?)
          end

          it 'keeps writes permitted while the beta program has not ended', :aggregate_failures do
            stub_feature_flags(end_secrets_manager_beta_program: false)

            expect(resolved.permits_writes?).to be true
            expect(resolved.write_action_denial_reason).to be_nil
          end

          it 'denies writes once the beta program has ended', :aggregate_failures do
            stub_feature_flags(end_secrets_manager_beta_program: true)

            expect(resolved.permits_writes?).to be false
            expect(resolved.write_action_denial_reason).to eq(:trial_required)
          end
        end

        context 'when the namespace enrollment is not beta' do
          before do
            create(:secrets_manager_namespace_enrollment, namespace: root_group, beta: false)
          end

          it 'resolves beta_window_eligible as false and keeps writes denied', :aggregate_failures do
            expect(resolved.beta_window_eligible).to be false
            expect(resolved.permits_writes?).to be false
          end
        end

        context 'when the beta enrollment is disabled (owner opted out)' do
          before do
            create(:secrets_manager_namespace_enrollment, namespace: root_group, beta: true, disabled_at: 1.day.ago)
          end

          it 'does not open the beta window', :aggregate_failures do
            stub_feature_flags(end_secrets_manager_beta_program: false)

            expect(resolved.beta_window_eligible).to be false
            expect(resolved.permits_writes?).to be false
          end
        end

        context 'when the namespace has no enrollment' do
          it 'resolves beta_window_eligible as false' do
            expect(resolved.beta_window_eligible).to be false
          end
        end

        context 'when CDot deems a beta-enrolled namespace ineligible' do
          before do
            create(:secrets_manager_namespace_enrollment, namespace: root_group, beta: true)
            allow(::Gitlab::SubscriptionPortal::Client)
              .to receive(:secrets_manager_trial).with(namespace_id: root_group.id)
              .and_return(::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: :ineligible))
          end

          it 'keeps full access while the beta program has not ended', :aggregate_failures do
            stub_feature_flags(end_secrets_manager_beta_program: false)

            expect(resolved.state).to eq(:ineligible)
            expect(resolved.beta_window_eligible).to be true
            expect(resolved.permits_read?).to be true
            expect(resolved.permits_writes?).to be true
            expect(resolved.permits_direct_read?).to be true
          end

          it 'denies access once the beta program has ended', :aggregate_failures do
            stub_feature_flags(end_secrets_manager_beta_program: true)

            expect(resolved.state).to eq(:ineligible)
            expect(resolved.permits_read?).to be false
            expect(resolved.permits_writes?).to be false
          end
        end

        context 'when resolution fails for a beta-enrolled namespace' do
          before do
            create(:secrets_manager_namespace_enrollment, namespace: root_group, beta: true)
            allow(::Gitlab::SubscriptionPortal::Client)
              .to receive(:secrets_manager_trial)
              .and_raise(::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse::Error, 'boom')
          end

          it 'fails closed to :ineligible but keeps the beta window open', :aggregate_failures do
            stub_feature_flags(end_secrets_manager_beta_program: false)

            expect(resolved.state).to eq(:ineligible)
            expect(resolved.beta_window_eligible).to be true
            expect(resolved.permits_read?).to be true
            expect(resolved.permits_writes?).to be true
          end

          it 'fails closed with no access once the beta program has ended', :aggregate_failures do
            stub_feature_flags(end_secrets_manager_beta_program: true)

            expect(resolved.state).to eq(:ineligible)
            expect(resolved.permits_read?).to be false
            expect(resolved.permits_writes?).to be false
          end
        end

        context 'when the namespace is beta enrolled but has converted (CDot state :trial)' do
          before do
            create(:secrets_manager_namespace_enrollment, namespace: root_group, beta: true)
            allow(::Gitlab::SubscriptionPortal::Client)
              .to receive(:secrets_manager_trial).with(namespace_id: root_group.id)
              .and_return(::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: :trial))
          end

          it 'skips the enrollment lookup entirely (the window cannot open)', :aggregate_failures do
            allow(::SecretsManagement::NamespaceEnrollment).to receive(:beta_enrolled?).and_call_original

            expect(resolved.state).to eq(:trial)
            expect(resolved.beta_window_eligible).to be false
            expect(::SecretsManagement::NamespaceEnrollment).not_to have_received(:beta_enrolled?)
          end
        end

        context 'when the beta enrollment lookup raises' do
          before do
            allow(::SecretsManagement::NamespaceEnrollment)
              .to receive(:beta_enrolled?)
              .and_raise(ActiveRecord::StatementInvalid.new('connection lost'))
          end

          it 'fails closed to :ineligible and reports the failure', :aggregate_failures do
            expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(
              an_instance_of(ActiveRecord::StatementInvalid),
              hash_including(issue_type: 'secrets_management_entitlement_fail_closed')
            )

            expect(resolved.state).to eq(:ineligible)
          end
        end
      end

      context 'when a requesting user is provided' do
        let(:resolver_user) { instance_double(User, id: 4242) }

        it 'forwards the user_id to /consumers/resolve (the per-actor check), not to /trials' do
          expect(::Gitlab::SubscriptionPortal::Client)
            .to receive(:secrets_manager_trial).with(namespace_id: root_group.id)
            .and_return(::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: :trial_eligible))
          expect(::Gitlab::SubscriptionPortal::Client)
            .to receive(:secrets_manager_consumer_resolve)
            .with(namespace_id: root_group.id, user_id: resolver_user.id)
            .and_return(::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false))

          expect(resolved.state).to eq(:trial_eligible)
        end
      end

      context 'when /trials raises an error' do
        before do
          allow(::Gitlab::SubscriptionPortal::Client)
            .to receive(:secrets_manager_trial)
            .and_raise(::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse::Error, 'boom')
          allow(::Gitlab::SubscriptionPortal::Client)
            .to receive(:secrets_manager_consumer_resolve)
            .and_return(::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false))
        end

        it 'fails closed and returns :ineligible' do
          expect(resolved.state).to eq(:ineligible)
        end

        it 'reports the failure via Gitlab::ErrorTracking.track_exception' do
          expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(
            an_instance_of(::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse::Error),
            hash_including(
              issue_type: 'secrets_management_entitlement_fail_closed',
              gl_namespace_id: root_group.id
            )
          )

          resolved
        end
      end

      context 'when /consumers/resolve raises an error' do
        before do
          allow(::Gitlab::SubscriptionPortal::Client)
            .to receive(:secrets_manager_trial)
            .and_return(::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: :trial))
          allow(::Gitlab::SubscriptionPortal::Client)
            .to receive(:secrets_manager_consumer_resolve)
            .and_raise(::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse::Error, 'boom')
        end

        it 'fails closed and returns :ineligible' do
          expect(resolved.state).to eq(:ineligible)
        end
      end

      context 'when /trials returns a state the resolver does not handle' do
        before do
          allow(::Gitlab::SubscriptionPortal::Client).to receive_messages(
            secrets_manager_trial: instance_double(
              ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse, state: :brand_new_state
            ),
            secrets_manager_consumer_resolve: ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(
              blocked: false
            )
          )
        end

        it 'fails closed and returns :ineligible' do
          expect(resolved.state).to eq(:ineligible)
        end

        it 'reports the failure via Gitlab::ErrorTracking.track_exception' do
          expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(
            an_instance_of(::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse::Error),
            hash_including(
              issue_type: 'secrets_management_entitlement_fail_closed',
              gl_namespace_id: root_group.id
            )
          )

          resolved
        end
      end

      context 'with a cache_ttl', :use_clean_rails_memory_store_caching do
        def resolve_with_ttl
          described_class.new(namespace, cache_ttl: 1.minute).resolve
        end

        before do
          allow(::Gitlab::SubscriptionPortal::Client).to receive_messages(
            secrets_manager_trial: ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: :trial),
            secrets_manager_consumer_resolve:
              ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false)
          )
        end

        it 'serves later resolutions from the cache without asking CDot again' do
          first = resolve_with_ttl
          second = resolve_with_ttl

          expect(second).to eq(first)
          expect(::Gitlab::SubscriptionPortal::Client).to have_received(:secrets_manager_trial).once
        end

        it 'resolves again once the TTL elapses' do
          resolve_with_ttl
          travel_to(2.minutes.from_now) { resolve_with_ttl }

          expect(::Gitlab::SubscriptionPortal::Client).to have_received(:secrets_manager_trial).twice
        end

        it 'resolves per call when cache_ttl is not given' do
          described_class.new(namespace).resolve
          described_class.new(namespace).resolve

          expect(::Gitlab::SubscriptionPortal::Client).to have_received(:secrets_manager_trial).twice
        end

        it 'warms the same cache_key that #resolve! reads, repairing a lost race' do
          resolve_with_ttl

          resolved_by_bang = described_class.new(namespace, cache_ttl: 1.minute).resolve!

          expect(resolved_by_bang.state).to eq(:trial)
          expect(::Gitlab::SubscriptionPortal::Client).to have_received(:secrets_manager_trial).once
        end
      end

      context 'when a CDot call raises with a cache_ttl', :use_clean_rails_memory_store_caching do
        before do
          allow(::Gitlab::SubscriptionPortal::Client)
            .to receive(:secrets_manager_trial)
            .and_raise(::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse::Error, 'boom')
        end

        it 'fails closed to :ineligible instead of propagating' do
          resolved_with_ttl = described_class.new(namespace, cache_ttl: 1.minute).resolve

          expect(resolved_with_ttl.state).to eq(:ineligible)
        end

        it 'never caches the fail-closed result, so the next call retries CDot' do
          2.times { described_class.new(namespace, cache_ttl: 1.minute).resolve }

          expect(::Gitlab::SubscriptionPortal::Client).to have_received(:secrets_manager_trial).twice
        end
      end
    end

    context 'on self-managed with an online cloud license' do
      let(:namespace) { nil }
      let(:instance_uuid) { 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' }
      let(:expected_client_kwargs) { { instance_id: instance_uuid } }

      before do
        stub_saas_features(gitlab_com_subscriptions: false)
        allow(::Gitlab).to receive(:com?).and_return(false)
        allow(::License).to receive(:current).and_return(
          instance_double(License, online_cloud_license?: true, trial?: false)
        )
        allow(::Gitlab::CurrentSettings).to receive(:uuid).and_return(instance_uuid)
      end

      it 'routes through the cloud branch and passes instance_id (not namespace_id)', :aggregate_failures do
        expect(::Gitlab::SubscriptionPortal::Client)
          .to receive(:secrets_manager_trial).with(instance_id: instance_uuid)
          .and_return(::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: :trial_eligible))
        expect(::Gitlab::SubscriptionPortal::Client)
          .to receive(:secrets_manager_consumer_resolve).with(instance_id: instance_uuid, user_id: nil)
          .and_return(::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false))

        expect(resolved.state).to eq(:trial_eligible)
      end

      # Self-managed records the beta cohort on the instance settings
      # (`secrets_manager_instance_beta_enrolled`), the counterpart of the SaaS
      # `beta` column on the namespace enrollment.
      describe 'beta window for the self-managed beta cohort' do
        let(:trial_state) { :trial_eligible }

        before do
          allow(::Gitlab::SubscriptionPortal::Client)
            .to receive(:secrets_manager_trial).with(instance_id: instance_uuid)
            .and_return(::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: trial_state))
          allow(::Gitlab::SubscriptionPortal::Client)
            .to receive(:secrets_manager_consumer_resolve).with(instance_id: instance_uuid, user_id: nil)
            .and_return(::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false))
        end

        it 'never consults the SaaS namespace enrollment' do
          allow(::SecretsManagement::NamespaceEnrollment).to receive(:beta_enrolled?).and_call_original

          resolved

          expect(::SecretsManagement::NamespaceEnrollment).not_to have_received(:beta_enrolled?)
        end

        context 'when the instance is beta-enrolled' do
          before do
            stub_application_setting(
              secrets_manager_instance_enrolled: true,
              secrets_manager_instance_beta_enrolled: true
            )
          end

          it 'resolves beta_window_eligible for instance-level resolution (nil namespace)', :aggregate_failures do
            expect(resolved.state).to eq(:trial_eligible)
            expect(resolved.beta_window_eligible).to be true
          end

          it 'keeps full access while the beta program has not ended', :aggregate_failures do
            stub_feature_flags(end_secrets_manager_beta_program: false)

            expect(resolved.permits_writes?).to be true
            expect(resolved.permits_direct_read?).to be true
            expect(resolved.beta_program_ended).to be false
          end

          it 'ends the window like SaaS once the beta program has ended', :aggregate_failures do
            stub_feature_flags(end_secrets_manager_beta_program: true)

            expect(resolved.beta_window_eligible).to be true
            expect(resolved.beta_program_ended).to be true
            expect(resolved.permits_read?).to be true
            expect(resolved.permits_writes?).to be false
            expect(resolved.permits_direct_read?).to be false
          end

          context 'with a top-level group namespace (group-scoped permission checks)' do
            let(:namespace) { root_group }

            it 'resolves beta_window_eligible' do
              expect(resolved.beta_window_eligible).to be true
            end
          end

          context 'when CDot deems the instance ineligible' do
            let(:trial_state) { :ineligible }

            it 'keeps the beta window open on the :ineligible state', :aggregate_failures do
              stub_feature_flags(end_secrets_manager_beta_program: false)

              expect(resolved.state).to eq(:ineligible)
              expect(resolved.beta_window_eligible).to be true
              expect(resolved.permits_writes?).to be true
            end
          end

          context 'when the instance has converted (CDot state :trial)' do
            let(:trial_state) { :trial }

            it 'closes the beta window without consulting the instance enrollment', :aggregate_failures do
              allow(::SecretsManagement::InstanceEnrollment).to receive(:beta_enrolled?).and_call_original

              expect(resolved.state).to eq(:trial)
              expect(resolved.beta_window_eligible).to be false
              expect(::SecretsManagement::InstanceEnrollment).not_to have_received(:beta_enrolled?)
            end
          end

          context 'when resolution fails' do
            before do
              allow(::Gitlab::SubscriptionPortal::Client)
                .to receive(:secrets_manager_trial)
                .and_raise(::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse::Error, 'CDot down')
            end

            it 'fails closed to :ineligible but keeps the beta window open', :aggregate_failures do
              stub_feature_flags(end_secrets_manager_beta_program: false)

              expect(resolved.state).to eq(:ineligible)
              expect(resolved.beta_window_eligible).to be true
              expect(resolved.permits_access?).to be true
            end
          end
        end

        context 'when the instance enrolled after the paid experience started' do
          before do
            stub_application_setting(
              secrets_manager_instance_enrolled: true,
              secrets_manager_instance_beta_enrolled: false
            )
          end

          it 'is not treated as beta', :aggregate_failures do
            expect(resolved.state).to eq(:trial_eligible)
            expect(resolved.beta_window_eligible).to be false
            expect(resolved.permits_writes?).to be false
          end
        end

        context 'when the instance is not enrolled' do
          before do
            stub_application_setting(
              secrets_manager_instance_enrolled: false,
              secrets_manager_instance_beta_enrolled: true
            )
          end

          it 'is not treated as beta even with a stale marker' do
            expect(resolved.beta_window_eligible).to be false
          end
        end
      end

      describe 'precedence table (mirror of SaaS)' do
        include_examples 'cloud branch precedence table'
      end

      context 'with recorded instance add-on intent (paid without a trial)' do
        let(:cdot_trial) do
          ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(
            state: :trial_eligible, on_demand_enabled: true
          )
        end

        let(:cdot_resolve) do
          ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false)
        end

        before do
          allow(::Gitlab::SubscriptionPortal::Client).to receive_messages(
            secrets_manager_trial: cdot_trial,
            secrets_manager_consumer_resolve: cdot_resolve
          )
        end

        context 'when the instance is enrolled with add-on intent and resolve allows access' do
          before do
            stub_application_setting(
              secrets_manager_instance_enrolled: true,
              secrets_manager_instance_add_on_requested_at: 1.day.ago
            )
          end

          it 'returns :paid without trial fields', :aggregate_failures do
            expect(resolved.state).to eq(:paid)
            expect(resolved.trial_started_at).to be_nil
            expect(resolved.trial_expires_at).to be_nil
            expect(resolved.on_demand_enabled).to be true
            expect(resolved.permits_writes?).to be true
          end

          it 'never reads namespace enrollments' do
            expect(::SecretsManagement::NamespaceEnrollment).not_to receive(:add_on_requested?)

            resolved
          end

          # Policies, CI registration and the service gates resolve with the root
          # group, not nil; the stamp must be visible on that shape too, or the
          # instance mutation reports :paid while nobody can create a secret.
          context 'with a top-level group namespace (group-scoped permission checks)' do
            let(:namespace) { root_group }

            it 'resolves :paid from the instance stamp, not from namespace enrollments', :aggregate_failures do
              expect(::SecretsManagement::NamespaceEnrollment).not_to receive(:add_on_requested?)

              expect(resolved.state).to eq(:paid)
              expect(resolved.permits_writes?).to be true
            end
          end

          context 'when resolve blocks on on_demand_disabled (acceptance reset by renewal)' do
            let(:cdot_resolve) do
              ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(
                blocked: true, blocked_reason: :on_demand_disabled
              )
            end

            it 'falls back to :trial_eligible instead of silently staying paid' do
              expect(resolved.state).to eq(:trial_eligible)
            end
          end

          context 'when the trial offer sunsets on CDot (state :ineligible, resolve still allows)' do
            let(:cdot_trial) do
              ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: :ineligible)
            end

            it 'stays :paid -- the customer is still billed and must keep access', :aggregate_failures do
              expect(resolved.state).to eq(:paid)
              expect(resolved.permits_writes?).to be true
            end
          end

          context 'when the trial state is :ineligible and resolve blocks' do
            let(:cdot_trial) do
              ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: :ineligible)
            end

            let(:cdot_resolve) do
              ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(
                blocked: true, blocked_reason: :usage_not_allowed
              )
            end

            it 'does not let the intent override enforcement' do
              expect(resolved.state).to eq(:ineligible)
            end
          end
        end

        context 'when the instance is enrolled without add-on intent' do
          before do
            stub_application_setting(
              secrets_manager_instance_enrolled: true,
              secrets_manager_instance_add_on_requested_at: nil
            )
          end

          it 'keeps :trial_eligible (plain enrollment is not paid intent)' do
            expect(resolved.state).to eq(:trial_eligible)
          end
        end

        context 'when the add-on intent is stamped but the instance is unenrolled (opt-out)' do
          before do
            stub_application_setting(
              secrets_manager_instance_enrolled: false,
              secrets_manager_instance_add_on_requested_at: 1.day.ago
            )
          end

          it 'keeps :trial_eligible' do
            expect(resolved.state).to eq(:trial_eligible)
          end
        end

        describe '.clear_cache with a nil namespace' do
          it 'drops the memoized entitlement so intent recorded mid-request is visible',
            :request_store, :aggregate_failures do
            expect(resolved.state).to eq(:trial_eligible)

            stub_application_setting(
              secrets_manager_instance_enrolled: true,
              secrets_manager_instance_add_on_requested_at: 1.day.ago
            )

            expect(described_class.new(nil, user: resolver_user).resolve.state).to eq(:trial_eligible)

            described_class.clear_cache(nil)

            expect(described_class.new(nil, user: resolver_user).resolve.state).to eq(:paid)
          end

          # The self-managed key has no namespace component, so nil and group
          # resolves share one entry; clearing it must refresh both shapes.
          it 'refreshes the shared entry for group-scoped resolves too', :request_store, :aggregate_failures do
            expect(described_class.new(root_group, user: resolver_user).resolve.state).to eq(:trial_eligible)

            stub_application_setting(
              secrets_manager_instance_enrolled: true,
              secrets_manager_instance_add_on_requested_at: 1.day.ago
            )
            described_class.clear_cache(nil)

            expect(described_class.new(root_group, user: resolver_user).resolve.state).to eq(:paid)
            expect(described_class.new(nil, user: resolver_user).resolve.state).to eq(:paid)
          end
        end
      end

      context 'when blocked with no_billable_source_error (grace computed locally from the purchase mirror)' do
        let(:grace_days) { SecretsManagement::Entitlement::GRACE_DAYS }

        before do
          # Grace derives solely from the Secrets Manager add-on purchase mirror; the trial
          # response's state and on-demand opt-in play no part here.
          allow(::Gitlab::SubscriptionPortal::Client).to receive_messages(
            secrets_manager_trial: ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(
              state: :expired, on_demand_enabled: true
            ),
            secrets_manager_consumer_resolve:
              ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(
                blocked: true, blocked_reason: :no_billable_source_error
              )
          )
        end

        context 'without any SM purchase mirror record' do
          it 'fails closed to :subscription_grace_period_expired (no grace window)', :aggregate_failures do
            expect(resolved.state).to eq(:blocked)
            expect(resolved.blocked_reason).to eq(:subscription_grace_period_expired)
            expect(resolved.in_grace?).to be false
            expect(resolved.permits_direct_read?).to be false
          end

          context 'without any trial history (trial state is not :expired)' do
            before do
              allow(::Gitlab::SubscriptionPortal::Client).to receive(:secrets_manager_trial).and_return(
                ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: :trial_eligible)
              )
            end

            it 'fails closed to :subscription_grace_period_expired' do
              expect(resolved.blocked_reason).to eq(:subscription_grace_period_expired)
            end
          end
        end

        context 'with a purchase mirror expiring inside the grace window' do
          before do
            create(:gitlab_subscription_add_on_purchase, :secrets_manager, :self_managed,
              started_at: 1.year.ago.to_date, expires_on: Date.current - 5.days)
          end

          it 'returns :blocked + :grace (read-only window)', :aggregate_failures do
            expect(resolved.state).to eq(:blocked)
            expect(resolved.blocked_reason).to eq(:grace)
            expect(resolved.in_grace?).to be true
            expect(resolved.permits_direct_read?).to be true
            expect(resolved.permits_writes?).to be false
          end
        end

        context 'on the last day of the grace window', :freeze_time do
          before do
            # expires_on is exclusive (last paid day precedes it), so the
            # window closes GRACE_DAYS - 1 days after expires_on.
            create(:gitlab_subscription_add_on_purchase, :secrets_manager, :self_managed,
              started_at: 1.year.ago.to_date, expires_on: Date.current - (grace_days - 1).days)
          end

          it 'still returns :grace' do
            expect(resolved.blocked_reason).to eq(:grace)
          end
        end

        context 'with the grace window elapsed', :freeze_time do
          before do
            create(:gitlab_subscription_add_on_purchase, :secrets_manager, :self_managed,
              started_at: 1.year.ago.to_date, expires_on: Date.current - grace_days.days)
          end

          it 'returns :blocked + :subscription_grace_period_expired (full lockout)', :aggregate_failures do
            expect(resolved.state).to eq(:blocked)
            expect(resolved.blocked_reason).to eq(:subscription_grace_period_expired)
            expect(resolved.in_grace?).to be false
            expect(resolved.permits_direct_read?).to be false
          end
        end

        context 'with a still-active purchase mirror (local sync lags the CDot lapse)' do
          before do
            create(:gitlab_subscription_add_on_purchase, :active, :secrets_manager, :self_managed)
          end

          it 'returns :grace (read-only through the mirrored term plus the window)', :aggregate_failures do
            expect(resolved.state).to eq(:blocked)
            expect(resolved.blocked_reason).to eq(:grace)
            expect(resolved.permits_direct_read?).to be true
            expect(resolved.permits_writes?).to be false
          end
        end

        context 'with only an SM trial purchase mirror (trial: true, future expiry)' do
          before do
            create(:gitlab_subscription_add_on_purchase, :active_trial, :secrets_manager, :self_managed)
          end

          it 'does not open the grace window: fails closed to :subscription_grace_period_expired',
            :aggregate_failures do
            expect(resolved.state).to eq(:blocked)
            expect(resolved.blocked_reason).to eq(:subscription_grace_period_expired)
          end
        end

        context 'with only a namespace-scoped purchase (not instance-wide)' do
          before do
            create(:gitlab_subscription_add_on_purchase, :active, :secrets_manager, namespace: root_group)
          end

          it 'is ignored -- grace only reads instance-level purchases' do
            expect(resolved.blocked_reason).to eq(:subscription_grace_period_expired)
          end
        end

        context 'with only an instance-wide purchase for a different add-on' do
          before do
            create(:gitlab_subscription_add_on_purchase, :active, :duo_pro, :self_managed)
          end

          it 'is ignored -- grace only reads Secrets Manager purchases' do
            expect(resolved.blocked_reason).to eq(:subscription_grace_period_expired)
          end
        end

        # Group-scoped permission checks pass the root group even on
        # self-managed -- the nil-namespace early return is .com-only.
        context 'with a top-level group namespace' do
          let(:namespace) { root_group }

          it 'fails closed to :subscription_grace_period_expired without a purchase mirror' do
            expect(resolved.blocked_reason).to eq(:subscription_grace_period_expired)
          end

          context 'with a purchase mirror inside the grace window' do
            before do
              create(:gitlab_subscription_add_on_purchase, :secrets_manager, :self_managed,
                started_at: 1.year.ago.to_date, expires_on: Date.current - 5.days)
            end

            it 'returns :grace (the namespace does not divert self-managed routing)' do
              expect(resolved.blocked_reason).to eq(:grace)
            end
          end

          it 'never reads gitlab_subscription -- the self-managed anchor is the purchase mirror' do
            expect(namespace).not_to receive(:gitlab_subscription)

            expect(resolved.blocked_reason).to eq(:subscription_grace_period_expired)
          end
        end
      end
    end

    context 'on self-managed with a trial license' do
      let(:namespace) { nil }

      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      context 'when the trial license is online cloud licensed' do
        before do
          allow(::License).to receive(:current).and_return(
            instance_double(License, online_cloud_license?: true, trial?: true)
          )
        end

        it 'returns :ineligible without asking CDot', :aggregate_failures do
          expect(::Gitlab::SubscriptionPortal::Client).not_to receive(:secrets_manager_trial)
          expect(::Gitlab::SubscriptionPortal::Client).not_to receive(:secrets_manager_consumer_resolve)

          expect(resolved.state).to eq(:ineligible)
        end
      end

      context 'when the trial license is offline cloud licensed' do
        before do
          allow(::License).to receive(:current).and_return(
            instance_double(License, online_cloud_license?: false, trial?: true)
          )
        end

        it 'returns :ineligible without consulting AddOnPurchase', :aggregate_failures do
          create(:gitlab_subscription_add_on_purchase, :active, :secrets_manager, :self_managed)

          expect(::GitlabSubscriptions::AddOnPurchase).not_to receive(:for_secrets_manager)

          expect(resolved.state).to eq(:ineligible)
        end
      end
    end

    context 'when the underlying lookup raises' do
      let(:namespace) { nil }

      before do
        stub_saas_features(gitlab_com_subscriptions: false)
        allow(::GitlabSubscriptions::AddOnPurchase).to receive(:for_secrets_manager)
          .and_raise(ActiveRecord::StatementInvalid.new('connection lost'))
      end

      it 'fails closed and returns :ineligible' do
        expect(resolved.state).to eq(:ineligible)
      end

      it 'reports the rescued exception via Gitlab::ErrorTracking.track_exception with namespace context' do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(
          an_instance_of(ActiveRecord::StatementInvalid),
          hash_including(
            issue_type: 'secrets_management_entitlement_fail_closed',
            gl_namespace_id: nil
          )
        )
        expect(::Gitlab::ErrorTracking).not_to receive(:track_and_raise_for_dev_exception)

        expect(resolved.state).to eq(:ineligible)
      end

      context 'with a real cache store', :use_clean_rails_memory_store_caching do
        it 'reports to Sentry once per throttle window, logging the resolves it suppresses',
          :aggregate_failures do
          expect(::Gitlab::ErrorTracking).to receive(:track_exception).once.with(
            an_instance_of(ActiveRecord::StatementInvalid),
            hash_including(issue_type: 'secrets_management_entitlement_fail_closed')
          )
          expect(::Gitlab::ErrorTracking).to receive(:log_exception).once.with(
            an_instance_of(ActiveRecord::StatementInvalid),
            hash_including(issue_type: 'secrets_management_entitlement_fail_closed')
          )

          2.times { described_class.new(namespace, user: resolver_user).resolve }
        end
      end
    end
  end

  describe '#resolve!' do
    subject(:resolved!) { described_class.new(namespace, user: resolver_user, http_timeout: http_timeout).resolve! }

    let(:namespace) { root_group }
    let(:http_timeout) { nil }

    context 'on SaaS', :saas do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
        allow(::License).to receive(:current).and_return(
          instance_double(License, online_cloud_license?: true)
        )
      end

      context 'when resolution succeeds' do
        before do
          allow(::Gitlab::SubscriptionPortal::Client).to receive_messages(
            secrets_manager_trial: ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: :trial),
            secrets_manager_consumer_resolve:
              ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false)
          )
        end

        it 'resolves like #resolve' do
          expect(resolved!.state).to eq(:trial)
        end

        it 'does not forward a timeout to the client by default' do
          resolved!

          expect(::Gitlab::SubscriptionPortal::Client)
            .to have_received(:secrets_manager_trial).with(namespace_id: root_group.id)
          expect(::Gitlab::SubscriptionPortal::Client)
            .to have_received(:secrets_manager_consumer_resolve).with(namespace_id: root_group.id, user_id: nil)
        end

        context 'with an http_timeout' do
          let(:http_timeout) { 0.25 }

          it 'forwards the timeout to both CDot calls' do
            resolved!

            expect(::Gitlab::SubscriptionPortal::Client)
              .to have_received(:secrets_manager_trial).with(namespace_id: root_group.id, timeout: 0.25)
            expect(::Gitlab::SubscriptionPortal::Client)
              .to have_received(:secrets_manager_consumer_resolve)
              .with(namespace_id: root_group.id, timeout: 0.25, user_id: nil)
          end
        end

        context 'with a cache_ttl', :use_clean_rails_memory_store_caching do
          def resolve_with_ttl
            described_class.new(namespace, cache_ttl: 1.minute).resolve!
          end

          it 'serves later resolutions from the cache without asking CDot again' do
            first = resolve_with_ttl
            second = resolve_with_ttl

            expect(second).to eq(first)
            expect(::Gitlab::SubscriptionPortal::Client).to have_received(:secrets_manager_trial).once
          end

          it 'resolves again once the TTL elapses' do
            resolve_with_ttl
            travel_to(2.minutes.from_now) { resolve_with_ttl }

            expect(::Gitlab::SubscriptionPortal::Client).to have_received(:secrets_manager_trial).twice
          end

          it 'resolves per call when cache_ttl is not given' do
            described_class.new(namespace).resolve!
            described_class.new(namespace).resolve!

            expect(::Gitlab::SubscriptionPortal::Client).to have_received(:secrets_manager_trial).twice
          end
        end
      end

      context 'when the beta enrollment lookup raises' do
        before do
          allow(::Gitlab::SubscriptionPortal::Client).to receive_messages(
            secrets_manager_trial:
              ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: :trial_eligible),
            secrets_manager_consumer_resolve:
              ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false)
          )
          allow(::SecretsManagement::NamespaceEnrollment)
            .to receive(:beta_enrolled?)
            .and_raise(ActiveRecord::StatementInvalid.new('connection lost'))
        end

        it 'propagates the error instead of failing closed to :ineligible' do
          expect { resolved! }.to raise_error(ActiveRecord::StatementInvalid)
        end
      end

      context 'when a CDot call raises' do
        before do
          allow(::Gitlab::SubscriptionPortal::Client)
            .to receive(:secrets_manager_trial)
            .and_raise(::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse::Error, 'boom')
        end

        it 'propagates the error instead of failing closed to :ineligible' do
          expect { resolved! }.to raise_error(
            ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse::Error, 'boom'
          )
        end

        it 'neither logs nor reports the exception (the caller owns failure handling)' do
          expect(::Gitlab::ErrorTracking).not_to receive(:log_exception)
          expect(::Gitlab::ErrorTracking).not_to receive(:track_exception)

          expect { resolved! }.to raise_error(::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse::Error)
        end

        it 'does not cache failures, so the next call retries', :use_clean_rails_memory_store_caching do
          2.times do
            expect { described_class.new(namespace, cache_ttl: 1.minute).resolve! }
              .to raise_error(::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse::Error)
          end

          expect(::Gitlab::SubscriptionPortal::Client).to have_received(:secrets_manager_trial).twice
        end
      end
    end
  end

  describe 'argument validation' do
    it 'raises ArgumentError for a subgroup' do
      subgroup = create(:group, parent: root_group)

      expect { described_class.new(subgroup) }
        .to raise_error(ArgumentError, /top-level Group or nil/)
    end

    it 'raises ArgumentError for a project' do
      project = create(:project, group: root_group)

      expect { described_class.new(project) }
        .to raise_error(ArgumentError, /top-level Group or nil/)
    end

    it 'accepts nil' do
      expect { described_class.new(nil) }.not_to raise_error
    end

    it 'accepts a top-level Group' do
      expect { described_class.new(root_group) }.not_to raise_error
    end

    it 'accepts an optional user: kwarg (default nil)', :aggregate_failures do
      user = build_stubbed(:user)

      expect { described_class.new(root_group) }.not_to raise_error
      expect { described_class.new(root_group, user: nil) }.not_to raise_error
      expect { described_class.new(root_group, user: user) }.not_to raise_error
    end
  end

  describe 'last-known-good fallback', :saas do
    let(:namespace) { root_group }
    let(:lkg_key) { described_class.cache_key_for(root_group) }
    let(:blocked) { false }
    let(:blocked_reason) { nil }

    let(:cdot_trial) do
      ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(
        state: :trial,
        trial_started_at: 5.days.ago,
        trial_expires_at: 25.days.from_now,
        credits_remaining: 100.0,
        credits_total: 500.0,
        on_demand_enabled: true
      )
    end

    let(:cdot_resolve) do
      ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(
        blocked: blocked, blocked_reason: blocked_reason
      )
    end

    before do
      stub_saas_features(gitlab_com_subscriptions: true)
      allow(::License).to receive(:current).and_return(
        instance_double(License, online_cloud_license?: true)
      )
    end

    def resolve_now
      described_class.new(namespace).resolve
    end

    def stub_cdot_success
      allow(::Gitlab::SubscriptionPortal::Client).to receive_messages(
        secrets_manager_trial: cdot_trial,
        secrets_manager_consumer_resolve: cdot_resolve
      )
    end

    # Mirrors the client: a transport failure is UnavailableError, re-raised from a
    # rescue so `cause` still names the network error for the log line.
    def stub_cdot_transport_failure
      allow(::Gitlab::SubscriptionPortal::Client).to receive(:secrets_manager_trial) do
        raise ::Gitlab::SubscriptionPortal::SecretsManagerResponseError::UnavailableError.new('unreachable'),
          cause: Net::ReadTimeout.new('timed out')
      end
    end

    # Mirrors the client: 5xx raise UnavailableError, anything else a plain Error,
    # both carrying the status and neither with a `cause`.
    def stub_cdot_status_failure(code = 403, endpoint: :secrets_manager_trial, block_reason: nil)
      response_class = if endpoint == :secrets_manager_trial
                         ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse
                       else
                         ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse
                       end

      unavailable = ::Gitlab::SubscriptionPortal::SecretsManagerResponseError.unavailable_status?(code)
      error_class = if unavailable
                      ::Gitlab::SubscriptionPortal::SecretsManagerResponseError::UnavailableError
                    else
                      response_class::Error
                    end

      allow(::Gitlab::SubscriptionPortal::Client).to receive(endpoint).and_raise(
        error_class.new("HTTP #{code}", cdot_status: code, cdot_block_reason: block_reason)
      )
    end

    describe 'writing the slot' do
      before do
        stub_cdot_success
      end

      it 'stores both CDot responses after a successful resolution', :aggregate_failures do
        expect(resolve_now.state).to eq(:trial)

        record = SecretsManagement::Entitlement::LastKnownGoodStore.read(lkg_key)
        expect(record.trial).to eq(cdot_trial)
        expect(record.resolve).to eq(cdot_resolve)
      end

      context 'when CDot answers with an explicit deny' do
        let(:blocked) { true }
        let(:blocked_reason) { :credits_exhausted }

        it 'replaces a granting slot, so the deny is not delayed by the window' do
          granting = ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false)
          SecretsManagement::Entitlement::LastKnownGoodStore
            .write(lkg_key, trial: cdot_trial, resolve: granting)

          resolve_now

          record = SecretsManagement::Entitlement::LastKnownGoodStore.read(lkg_key)
          expect(record.resolve.blocked_reason).to eq(:credits_exhausted)
        end
      end
    end

    describe 'serving the slot' do
      it 'extends the last proven state instead of failing closed', :aggregate_failures do
        stub_cdot_success
        expect(resolve_now.state).to eq(:trial)

        stub_cdot_transport_failure
        served = resolve_now

        expect(served.state).to eq(:trial)
        expect(served.permits_direct_read?).to be true
      end

      it 'fails closed when no slot has ever been written' do
        stub_cdot_transport_failure

        expect(resolve_now.state).to eq(:ineligible)
      end

      it 'fails closed on an unexpected HTTP status, which is an explicit CDot answer' do
        stub_cdot_success
        resolve_now

        stub_cdot_status_failure(403)

        expect(resolve_now.state).to eq(:ineligible)
      end

      # The 2026-08-25 incident shape: CDot answers 5xx without deciding anything,
      # which must read as an outage, not a denial.
      describe 'CDot 5xx as unavailability' do
        ::Gitlab::SubscriptionPortal::SecretsManagerResponseError::UNAVAILABLE_STATUSES.each do |code|
          context "when /trials answers HTTP #{code}" do
            it 'serves a warm slot', :aggregate_failures do
              stub_cdot_success
              expect(resolve_now.state).to eq(:trial)

              stub_cdot_status_failure(code)
              served = resolve_now

              expect(served.state).to eq(:trial)
              expect(served.permits_direct_read?).to be true
            end

            it 'fails closed on a cold slot' do
              stub_cdot_status_failure(code)

              expect(resolve_now.state).to eq(:ineligible)
            end
          end

          context "when /consumers/resolve answers HTTP #{code}" do
            it 'serves a warm slot' do
              stub_cdot_success
              resolve_now

              stub_cdot_status_failure(code, endpoint: :secrets_manager_consumer_resolve)

              expect(resolve_now.state).to eq(:trial)
            end

            it 'fails closed on a cold slot' do
              stub_cdot_success
              stub_cdot_status_failure(code, endpoint: :secrets_manager_consumer_resolve)

              expect(resolve_now.state).to eq(:ineligible)
            end
          end
        end

        # A 4xx other than 402 is CDot's own decision and fails closed even with a warm slot.
        [400, 401, 403, 422].each do |code|
          context "when /trials answers HTTP #{code}" do
            it 'fails closed even with a warm slot', :aggregate_failures do
              stub_cdot_success
              expect(resolve_now.state).to eq(:trial)

              stub_cdot_status_failure(code)

              expect(resolve_now.state).to eq(:ineligible)
            end
          end

          context "when /consumers/resolve answers HTTP #{code}" do
            it 'fails closed even with a warm slot', :aggregate_failures do
              stub_cdot_success
              expect(resolve_now.state).to eq(:trial)

              stub_cdot_status_failure(code, endpoint: :secrets_manager_consumer_resolve)

              expect(resolve_now.state).to eq(:ineligible)
            end
          end
        end

        it 'does not serve a stored deny on a 5xx', :aggregate_failures do
          denying = ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(
            blocked: true, blocked_reason: :credits_exhausted
          )
          SecretsManagement::Entitlement::LastKnownGoodStore.write(lkg_key, trial: cdot_trial, resolve: denying)

          stub_cdot_status_failure(502)

          expect(resolve_now.state).to eq(:ineligible)
        end

        it 'fails closed on a 5xx once the window has elapsed' do
          stub_cdot_success
          resolve_now

          stub_cdot_status_failure(504)

          travel_to(SecretsManagement::Entitlement::LastKnownGoodStore::WINDOW.from_now + 1.minute) do
            expect(resolve_now.state).to eq(:ineligible)
          end
        end

        context 'with the secrets_manager_entitlement_lkg_fallback kill switch off' do
          before do
            stub_feature_flags(secrets_manager_entitlement_lkg_fallback: false)
          end

          it 'fails closed on a 5xx even with a warm slot' do
            stub_cdot_success
            resolve_now

            stub_cdot_status_failure(502)

            expect(resolve_now.state).to eq(:ineligible)
          end
        end
      end

      it 'serves the slot when the resolve endpoint is the one that fails' do
        stub_cdot_success
        resolve_now

        allow(::Gitlab::SubscriptionPortal::Client).to receive(:secrets_manager_consumer_resolve) do
          raise ::Gitlab::SubscriptionPortal::SecretsManagerResponseError::UnavailableError.new('unreachable'),
            cause: Errno::ECONNREFUSED.new('refused')
        end

        expect(resolve_now.state).to eq(:trial)
      end

      # The client keeps our own guards (SSRF and the like) as a plain Error, and the
      # resolver must not second-guess that by reading `cause`.
      it 'fails closed on a plain client Error even when its cause is a network error' do
        stub_cdot_success
        resolve_now

        allow(::Gitlab::SubscriptionPortal::Client).to receive(:secrets_manager_trial) do
          raise ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse::Error.new('blocked'),
            cause: ::Gitlab::HTTP::BlockedUrlError.new('URL is blocked')
        end

        expect(resolve_now.state).to eq(:ineligible)
      end

      it 'fails closed on a local error rather than replaying CDot' do
        stub_cdot_success
        resolve_now

        allow(::Gitlab::SubscriptionPortal::Client)
          .to receive(:secrets_manager_trial)
          .and_raise(ActiveRecord::StatementInvalid, 'connection lost')

        expect(resolve_now.state).to eq(:ineligible)
      end

      # The window runs from the write, so serving from the slot must not push
      # it out -- otherwise a busy namespace never leaves the outage.
      it 'fails closed once the window has elapsed, even after serving from the slot' do
        stub_cdot_success
        resolve_now

        stub_cdot_transport_failure
        travel_to(2.hours.from_now) { expect(resolve_now.state).to eq(:trial) }

        travel_to(SecretsManagement::Entitlement::LastKnownGoodStore::WINDOW.from_now + 1.minute) do
          expect(resolve_now.state).to eq(:ineligible)
        end
      end

      context 'when the stored state was not entitled' do
        let(:blocked) { true }
        let(:blocked_reason) { :credits_exhausted }

        it 'does not extend it', :aggregate_failures do
          stub_cdot_success
          expect(resolve_now.blocked_reason).to eq(:credits_exhausted)

          stub_cdot_transport_failure

          expect(resolve_now.state).to eq(:ineligible)
        end
      end
    end

    describe 'the secrets_manager_entitlement_lkg_fallback kill switch' do
      before do
        stub_feature_flags(secrets_manager_entitlement_lkg_fallback: false)
      end

      it 'fails closed on a transport failure even with a warm slot', :aggregate_failures do
        stub_cdot_success
        expect(resolve_now.state).to eq(:trial)

        stub_cdot_transport_failure
        expect(SecretsManagement::Entitlement::LastKnownGoodStore).not_to receive(:read)

        expect(resolve_now.state).to eq(:ineligible)
      end

      # The write stays ungated on purpose: flipping the switch back on has to
      # serve straight away rather than wait for the next successful resolution.
      it 'still writes the slot on a live resolution' do
        stub_cdot_success
        resolve_now

        expect(SecretsManagement::Entitlement::LastKnownGoodStore.read(lkg_key)).not_to be_nil
      end
    end

    describe 're-deriving on serve rather than replaying a frozen answer' do
      # The merge derives the grace window from the clock, so a slot stored
      # while in grace must stop being extended once the window lapses --
      # otherwise a stored entitlement would keep permitting CI reads.
      context 'when the subscription grace window lapses during the outage' do
        let(:blocked) { true }
        let(:blocked_reason) { :no_billable_source_error }

        # Two sequential travel_to blocks rather than nested ones, which Rails
        # rejects. 20 hours keeps the slot inside its 24h window, so what
        # expires between them is the grace period, not the slot.
        it 'stops extending access', :aggregate_failures do
          base = Time.zone.parse('2026-06-15 12:00:00')

          travel_to(base) do
            create(:gitlab_subscription, namespace: root_group,
              end_date: Date.current - SecretsManagement::Entitlement::GRACE_DAYS.days)

            stub_cdot_success
            stored = resolve_now

            expect(stored.blocked_reason).to eq(:grace)
            expect(stored.permits_direct_read?).to be true
          end

          # Positive control first: without the lapse the slot IS served, so the
          # assertion below cannot pass merely because the gate is missing.
          travel_to(base + 1.hour) do
            stub_cdot_transport_failure

            expect(resolve_now.blocked_reason).to eq(:grace)
          end

          travel_to(base + 20.hours) do
            stub_cdot_transport_failure

            expect(resolve_now.state).to eq(:ineligible)
          end
        end
      end

      context 'when the beta program ends during the outage' do
        let(:cdot_trial) do
          ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(state: :trial_eligible)
        end

        before do
          create(:secrets_manager_namespace_enrollment, namespace: root_group, beta: true)
          stub_feature_flags(end_secrets_manager_beta_program: false)
        end

        it 'reads the flag as it stands on serve, not as stored', :aggregate_failures do
          stub_cdot_success
          expect(resolve_now.permits_direct_read?).to be true

          stub_cdot_transport_failure
          expect(resolve_now.permits_direct_read?).to be true

          stub_feature_flags(end_secrets_manager_beta_program: true)

          expect(resolve_now.state).to eq(:ineligible)
        end
      end
    end

    describe 'telemetry' do
      it 'logs a searchable line when it serves a stale answer', :aggregate_failures do
        stub_cdot_success
        resolve_now

        stub_cdot_transport_failure

        expect(::Gitlab::AppJsonLogger).to receive(:info).with(
          hash_including(
            'message' => 'Secrets Manager entitlement resolution',
            'source' => 'lkg_stale',
            Labkit::Fields::CLASS_NAME => described_class.name,
            'cdot_error_class' => 'Net::ReadTimeout',
            Labkit::Fields::GL_NAMESPACE_ID => root_group.id
          )
        )

        resolve_now
      end

      it 'reports the slot age so an operator can see how much window is left' do
        stub_cdot_success
        resolve_now

        stub_cdot_transport_failure

        travel_to(2.hours.from_now) do
          expect(::Gitlab::AppJsonLogger).to receive(:info).with(
            hash_including('lkg_age_s' => be_within(60).of(2.hours.to_f))
          )

          resolve_now
        end
      end

      it 'logs the fail-closed path' do
        stub_cdot_transport_failure

        expect(::Gitlab::AppJsonLogger).to receive(:info).with(
          hash_including('source' => 'fail_closed', 'cdot_error_class' => 'Net::ReadTimeout')
        )

        resolve_now
      end

      # A transport failure has no status, and `compact` drops the nil keys.
      it 'omits the CDot status fields on a transport failure' do
        stub_cdot_transport_failure

        expect(::Gitlab::AppJsonLogger).to receive(:info) do |payload|
          expect(payload).not_to include('cdot_status', 'cdot_block_reason')
        end

        resolve_now
      end

      # The status CDot answered and, on a 403, the reason it gave.
      it 'logs what CDot returned on a fail-closed status', :aggregate_failures do
        stub_cdot_success
        resolve_now

        stub_cdot_status_failure(403, endpoint: :secrets_manager_consumer_resolve, block_reason: 'resolution_error')

        expect(::Gitlab::AppJsonLogger).to receive(:info).with(
          hash_including(
            'source' => 'fail_closed',
            'cdot_error_class' => ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse::Error.name,
            'cdot_status' => 403,
            'cdot_block_reason' => 'resolution_error'
          )
        )

        expect(resolve_now.state).to eq(:ineligible)
      end

      it 'logs the 5xx status when it serves a stale answer', :aggregate_failures do
        stub_cdot_success
        resolve_now

        stub_cdot_status_failure(502)

        expect(::Gitlab::AppJsonLogger).to receive(:info).with(
          hash_including(
            'source' => 'lkg_stale',
            'cdot_error_class' => ::Gitlab::SubscriptionPortal::SecretsManagerResponseError::UnavailableError.name,
            'cdot_status' => 502
          )
        )

        expect(resolve_now.state).to eq(:trial)
      end

      it 'does not log a live resolution', :aggregate_failures do
        stub_cdot_success

        expect(::Gitlab::AppJsonLogger).not_to receive(:info).with(hash_including('source' => 'live'))

        expect(resolve_now.state).to eq(:trial)
      end

      it 'counts each source' do
        counter = described_class.resolutions_total

        stub_cdot_success
        expect { resolve_now }.to change { counter.get({ source: 'live' }) }.by(1)

        stub_cdot_transport_failure
        expect { resolve_now }.to change { counter.get({ source: 'lkg_stale' }) }.by(1)

        SecretsManagement::Entitlement::LastKnownGoodStore.delete(lkg_key)
        expect { resolve_now }.to change { counter.get({ source: 'fail_closed' }) }.by(1)
      end

      # Two of the three only appear during an outage, and an absent series
      # reads the same as a healthy one.
      # Asserts on `values`, not `get`: the client's `@values` is a Hash with a
      # default block, so `get` would create the series it is checking for and
      # pass with the pre-creation removed.
      it 'pre-creates a series for every source' do
        expected = described_class::SOURCES.map { |source| { source: source.to_s } }

        expect(described_class.resolutions_total.values.keys).to include(*expected)
      end
    end

    describe '.clear_cache' do
      it 'drops the slot, so a later failure cannot replay a pre-change answer' do
        stub_cdot_success
        resolve_now

        described_class.clear_cache(root_group)

        expect(SecretsManagement::Entitlement::LastKnownGoodStore.read(lkg_key)).to be_nil
      end
    end
  end

  # Everything above is :saas. Self-managed drives the issue -- one instance-wide
  # slot keyed without a namespace, reached via instance_id, so every namespace
  # on the install shares the outcome.
  describe 'last-known-good fallback on self-managed online cloud' do
    let_it_be(:other_group) { create(:group) }

    let(:instance_uuid) { 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' }
    let(:lkg_key) { described_class.cache_key_for(nil) }

    let(:cdot_trial) do
      ::Gitlab::SubscriptionPortal::SecretsManagerTrialResponse.new(
        state: :trial,
        trial_started_at: 5.days.ago,
        trial_expires_at: 25.days.from_now,
        credits_remaining: 100.0,
        credits_total: 500.0,
        on_demand_enabled: true
      )
    end

    let(:cdot_resolve) do
      ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(blocked: false)
    end

    before do
      stub_saas_features(gitlab_com_subscriptions: false)
      allow(::License).to receive(:current).and_return(
        instance_double(License, online_cloud_license?: true, trial?: false)
      )
      allow(::Gitlab::CurrentSettings).to receive(:uuid).and_return(instance_uuid)
    end

    def stub_cdot_success
      allow(::Gitlab::SubscriptionPortal::Client).to receive_messages(
        secrets_manager_trial: cdot_trial,
        secrets_manager_consumer_resolve: cdot_resolve
      )
    end

    def stub_cdot_transport_failure
      allow(::Gitlab::SubscriptionPortal::Client).to receive(:secrets_manager_trial) do
        raise ::Gitlab::SubscriptionPortal::SecretsManagerResponseError::UnavailableError.new('unreachable'),
          cause: Net::ReadTimeout.new('timed out')
      end
    end

    it 'keys the slot per install, not per namespace', :aggregate_failures do
      stub_cdot_success
      expect(described_class.new(root_group).resolve.state).to eq(:trial)

      expect(lkg_key).to eq([described_class::MEMOIZATION_KEY, :self_managed])
      expect(SecretsManagement::Entitlement::LastKnownGoodStore.read(lkg_key)).not_to be_nil
    end

    it 'serves the slot a different namespace wrote, since entitlement is install-wide' do
      stub_cdot_success
      described_class.new(root_group).resolve

      stub_cdot_transport_failure

      expect(described_class.new(other_group).resolve.state).to eq(:trial)
    end

    it 'fails closed when no slot has ever been written' do
      stub_cdot_transport_failure

      expect(described_class.new(root_group).resolve.state).to eq(:ineligible)
    end

    # The self-managed grace anchor reads the AddOnPurchase mirror rather than
    # gitlab_subscription, so it is a different branch from the SaaS example.
    context 'when the self-managed grace window lapses during the outage' do
      let(:cdot_resolve) do
        ::Gitlab::SubscriptionPortal::SecretsManagerConsumerResolveResponse.new(
          blocked: true, blocked_reason: :no_billable_source_error
        )
      end

      # Noon, so the second block is 08:00 the next calendar day whatever time
      # the suite runs -- the grace check compares dates, not instants. 20 hours
      # also keeps the slot inside its own 24h window, so what lapses between
      # the two blocks is the grace period and not the slot.
      it 'stops extending access', :aggregate_failures do
        base = Time.current.beginning_of_day + 12.hours
        grace_days = SecretsManagement::Entitlement::GRACE_DAYS

        travel_to(base) do
          # Last day of the window, matching the boundary convention above:
          # expires_on is exclusive, so the window closes GRACE_DAYS - 1 days on.
          create(:gitlab_subscription_add_on_purchase, :secrets_manager, :self_managed,
            started_at: 1.year.ago.to_date, expires_on: Date.current - (grace_days - 1).days)

          stub_cdot_success
          expect(described_class.new(root_group).resolve.blocked_reason).to eq(:grace)
        end

        travel_to(base + 20.hours) do
          stub_cdot_transport_failure

          expect(described_class.new(root_group).resolve.state).to eq(:ineligible)
        end
      end
    end
  end
end
