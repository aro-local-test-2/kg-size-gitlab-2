# frozen_string_literal: true

FactoryBot.define do
  factory :cd_rollout_transition, class: 'Cd::RolloutTransition' do
    rollout { association(:cd_rollout) }
    from_state { :pending }
    to_state { :in_progress }
    event { 'start' }
    # Not a `user:` principal: a literal user id here would coincidentally resolve to a
    # real User record whenever this spec file happens to run first in a worker (making
    # that a valid User#id), breaking tests that assert the default transition has no
    # resolvable acting/principal user. Tests that need a resolvable user override this.
    principal { 'system:autoflow' }
  end
end
