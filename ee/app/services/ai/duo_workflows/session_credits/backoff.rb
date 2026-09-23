# frozen_string_literal: true

module Ai
  module DuoWorkflows
    module SessionCredits
      # Shared back-off latch between the session credits workers. The cron skips
      # whole cycles while it is set so a degraded CustomersDot is not hit by a fresh
      # fan-out every 15 minutes, and already-queued child batches wait it out too.
      #
      # The kill switch (:disabled) latches on first sight: every request fails while
      # it is on. Degradation signals (connection errors, 5xx, 429) latch once
      # FAILURE_THRESHOLD distinct sources fail inside one fixed FAILURE_WINDOW. The
      # source is the root namespace (a batch on self-managed): CustomersDot's cost is
      # per subscription and its query timeout is deliberate load shedding, so one heavy
      # subscription failing on every tick and retry stays one source and never pauses
      # everyone else, while an outage or rate limiting fails many sources at once.
      # Successes do not reset the count, so partial degradation still latches.
      #
      # Each consecutive degradation latch doubles up to MAX_BACKOFF_DURATION, so a long
      # outage gets probed a few times a day instead of every half hour. A successful
      # fetch resets it.
      #
      # Redis errors are swallowed because a lost latch is the safe failure mode.
      module Backoff
        # Hash-tagged so the keys share a slot on Redis Cluster.
        LATCH_KEY = 'duo_workflow_session_credits:{backoff}:latch'
        FAILURES_KEY_PREFIX = 'duo_workflow_session_credits:{backoff}:failures'
        STREAK_KEY = 'duo_workflow_session_credits:{backoff}:streak'
        BACKOFF_DURATION = 30.minutes
        MAX_BACKOFF_DURATION = 4.hours
        # A latch-free hour after the last latch ran out means that outage is over.
        STREAK_QUIET_PERIOD = 1.hour
        # A switched-off field stays off for hours, not minutes; probing it every 30
        # minutes would push 1,000 more sessions into retry ladders each time.
        DISABLED_BACKOFF_DURATION = 6.hours
        FAILURE_THRESHOLD = 3
        FAILURE_WINDOW = 15.minutes

        def self.record_failure(reason:, source:)
          return trigger!(reason: reason) if reason == :disabled

          key = failures_key
          distinct = with_redis do |redis|
            redis.multi do |multi|
              multi.sadd(key, source)
              multi.expire(key, FAILURE_WINDOW.to_i)
              multi.scard(key)
            end&.last
          end

          trigger!(reason: reason) if distinct && distinct >= FAILURE_THRESHOLD
        end

        # A success lifts a kill-switch latch, since the field is evidently back on. A
        # degradation latch runs out its window instead, so a partially failing
        # CustomersDot cannot flap the cron back on.
        def self.record_success
          with_redis do |redis|
            redis.del(LATCH_KEY) if redis.get(LATCH_KEY) == 'disabled'
            redis.del(STREAK_KEY)
          end
        end

        def self.trigger!(reason:)
          with_redis do |redis|
            if reason == :disabled
              redis.set(LATCH_KEY, reason.to_s, ex: DISABLED_BACKOFF_DURATION.to_i)
            elsif redis.set(LATCH_KEY, reason.to_s, ex: BACKOFF_DURATION.to_i, nx: true)
              # NX makes the first failure of an episode the only one that escalates.
              redis.expire(LATCH_KEY, escalate(redis).to_i, gt: true)
            else
              # A failure late in a running latch keeps it up for at least a base window;
              # GT means neither call can ever shorten an escalated latch.
              redis.expire(LATCH_KEY, BACKOFF_DURATION.to_i, gt: true)
              redis.expire(STREAK_KEY, (BACKOFF_DURATION + STREAK_QUIET_PERIOD).to_i, gt: true)
            end
          end
        end

        def self.active?
          reason.present?
        end

        # The reason recorded by the latching failure, or nil when not latched.
        def self.reason
          with_redis { |redis| redis.get(LATCH_KEY) }&.to_sym
        end

        # Seconds left on a degradation latch, nil otherwise. The kill switch is left
        # out on purpose: a batch that gets through is what lifts that latch early.
        def self.retry_floor
          reason, ttl = with_redis do |redis|
            redis.multi do |multi|
              multi.get(LATCH_KEY)
              multi.ttl(LATCH_KEY)
            end
          end

          ttl if reason && reason != 'disabled' && ttl.to_i > 0
        end

        # Console override when CustomersDot is known healthy again.
        def self.clear!
          with_redis do |redis|
            redis.del(LATCH_KEY, failures_key, STREAK_KEY)
          end
        end

        # 30 minutes, then 1, 2 and 4 hours. The streak outlives the latch by the quiet
        # period so a trip right after expiry counts as the same outage.
        def self.escalate(redis)
          streak = redis.incr(STREAK_KEY)
          duration = [BACKOFF_DURATION * (2**(streak - 1)), MAX_BACKOFF_DURATION].min
          redis.expire(STREAK_KEY, (duration + STREAK_QUIET_PERIOD).to_i)

          duration
        end
        private_class_method :escalate

        # Fixed windows, not a sliding one: distinct sources have to fail inside the
        # same 15 minutes, so one failing source per tick never accumulates across ticks.
        def self.failures_key
          "#{FAILURES_KEY_PREFIX}:#{Time.current.to_i / FAILURE_WINDOW.to_i}"
        end
        private_class_method :failures_key

        def self.with_redis(&block)
          ::Gitlab::Redis::SharedState.with(&block) # rubocop:disable CodeReuse/ActiveRecord -- redis pool, not active record
        rescue ::Redis::BaseError, ::RedisClient::Error => e
          ::Gitlab::ErrorTracking.track_exception(e)
          nil
        end
        private_class_method :with_redis
      end
    end
  end
end
