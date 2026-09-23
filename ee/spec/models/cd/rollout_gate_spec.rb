# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::RolloutGate, feature_category: :continuous_delivery do
  let_it_be(:rollout) { create(:cd_rollout) }
  let_it_be(:step) do
    create(:cd_rollout_step, rollout: rollout, path: '0.0', step_type: Cd::RolloutStep::APPROVAL_STEP_TYPE,
      name: 'Deploy to production')
  end

  describe '#state' do
    it 'is pending when there is no resolution transition' do
      request = build(:cd_rollout_transition, rollout: rollout, event: 'request_approval')

      gate = described_class.new(request_transition: request)

      expect(gate.state).to eq(:pending)
    end

    it 'is approved when the resolution transition is an approve event' do
      request = build(:cd_rollout_transition, rollout: rollout, event: 'request_approval')
      resolution = build(:cd_rollout_transition, rollout: rollout, event: 'approve')

      gate = described_class.new(request_transition: request, resolution_transition: resolution)

      expect(gate.state).to eq(:approved)
    end

    it 'is rejected when the resolution transition is a reject event' do
      request = build(:cd_rollout_transition, rollout: rollout, event: 'request_approval')
      resolution = build(:cd_rollout_transition, rollout: rollout, event: 'reject')

      gate = described_class.new(request_transition: request, resolution_transition: resolution)

      expect(gate.state).to eq(:rejected)
    end
  end

  describe '#resolved?' do
    it 'is false when there is no resolution transition' do
      request = build(:cd_rollout_transition, rollout: rollout, event: 'request_approval')

      expect(described_class.new(request_transition: request).resolved?).to be(false)
    end

    it 'is true once a resolution transition is present' do
      request = build(:cd_rollout_transition, rollout: rollout, event: 'request_approval')
      resolution = build(:cd_rollout_transition, rollout: rollout, event: 'approve')

      expect(described_class.new(request_transition: request, resolution_transition: resolution).resolved?)
        .to be(true)
    end
  end

  describe '#resolve!' do
    it 'sets the resolution transition, changing the gate from pending to resolved' do
      request = build(:cd_rollout_transition, rollout: rollout, event: 'request_approval')
      resolution = build(:cd_rollout_transition, rollout: rollout, event: 'approve')

      gate = described_class.new(request_transition: request)

      expect { gate.resolve!(resolution) }.to change { gate.resolved? }.from(false).to(true)
      expect(gate.resolution_transition).to eq(resolution)
      expect(gate.state).to eq(:approved)
    end
  end

  describe '#step, #name, #rollout' do
    it 'delegates to the request transition' do
      request = build(:cd_rollout_transition, rollout: rollout, event: 'request_approval', rollout_step: step)

      gate = described_class.new(request_transition: request)

      expect(gate.step).to eq(step)
      expect(gate.name).to eq('Deploy to production')
      expect(gate.rollout).to eq(rollout)
    end

    it 'returns a nil step and name when the gate was not opened for a step' do
      request = build(:cd_rollout_transition, rollout: rollout, event: 'request_approval', rollout_step: nil)

      gate = described_class.new(request_transition: request)

      expect(gate.step).to be_nil
      expect(gate.name).to be_nil
    end
  end

  describe '#reason, #request_reason' do
    it 'is read from the request transition, unaffected by resolution' do
      request = build(:cd_rollout_transition, rollout: rollout, event: 'request_approval', reason: 'needs sign-off')
      resolution = build(:cd_rollout_transition, rollout: rollout, event: 'approve', resolution_reason: 'looks good')

      gate = described_class.new(request_transition: request, resolution_transition: resolution)

      expect(gate.reason).to eq('needs sign-off')
      expect(gate.request_reason).to eq('needs sign-off')
    end
  end

  describe '#resolution_reason, #resolved_at, #resolved_by_user_id' do
    it 'is nil for an unresolved gate' do
      request = build(:cd_rollout_transition, rollout: rollout, event: 'request_approval')

      gate = described_class.new(request_transition: request)

      expect(gate.resolution_reason).to be_nil
      expect(gate.resolved_at).to be_nil
      expect(gate.resolved_by_user_id).to be_nil
    end

    it 'is read from the resolution transition once resolved' do
      request = build(:cd_rollout_transition, rollout: rollout, event: 'request_approval')
      resolution = build(:cd_rollout_transition, rollout: rollout, event: 'approve',
        resolution_reason: 'looks good', principal: 'user:42', created_at: 1.hour.ago)

      gate = described_class.new(request_transition: request, resolution_transition: resolution)

      expect(gate.resolution_reason).to eq('looks good')
      expect(gate.resolved_at).to eq(resolution.created_at)
      expect(gate.resolved_by_user_id).to eq(42)
    end
  end

  describe '.for_rollout' do
    it 'returns an empty array when the rollout has no gate events' do
      create(:cd_rollout_transition, rollout: rollout, event: 'start')

      expect(described_class.for_rollout(rollout)).to eq([])
    end

    it 'returns a single pending gate for an unresolved request_approval' do
      request = create(:cd_rollout_transition, rollout: rollout, event: 'request_approval', rollout_step: step)

      gates = described_class.for_rollout(rollout)

      expect(gates.size).to eq(1)
      expect(gates.first.state).to eq(:pending)
      expect(gates.first.request_transition).to eq(request)
      expect(gates.first.resolution_transition).to be_nil
    end

    it 'pairs a request_approval with its resolving approve transition' do
      request = create(:cd_rollout_transition,
        rollout: rollout, event: 'request_approval', rollout_step: step, created_at: 2.hours.ago)
      resolution = create(:cd_rollout_transition, rollout: rollout, event: 'approve', created_at: 1.hour.ago)

      gates = described_class.for_rollout(rollout)

      expect(gates.size).to eq(1)
      expect(gates.first.state).to eq(:approved)
      expect(gates.first.request_transition).to eq(request)
      expect(gates.first.resolution_transition).to eq(resolution)
    end

    it 'returns every gate in the journal, not just the latest' do
      first_request = create(:cd_rollout_transition,
        rollout: rollout, event: 'request_approval', created_at: 4.hours.ago)
      create(:cd_rollout_transition, rollout: rollout, event: 'reject', created_at: 3.hours.ago)

      second_request = create(:cd_rollout_transition,
        rollout: rollout, event: 'request_approval', created_at: 2.hours.ago)

      gates = described_class.for_rollout(rollout)

      expect(gates.size).to eq(2)
      expect(gates.map(&:request_transition)).to match_array([first_request, second_request])
      expect(gates.first.state).to eq(:rejected)
      expect(gates.second.state).to eq(:pending)
    end

    it 'ignores a resolution event with no preceding open request' do
      create(:cd_rollout_transition, rollout: rollout, event: 'approve')

      expect(described_class.for_rollout(rollout)).to eq([])
    end
  end

  describe '.for_rollouts' do
    let_it_be(:other_rollout) { create(:cd_rollout) }

    it 'returns a hash of gates keyed by rollout id, in one query per table' do
      request = create(:cd_rollout_transition,
        rollout: rollout, event: 'request_approval', rollout_step: step, created_at: 2.hours.ago)
      resolution = create(:cd_rollout_transition, rollout: rollout, event: 'approve', created_at: 1.hour.ago)
      other_request = create(:cd_rollout_transition, rollout: other_rollout, event: 'request_approval')

      result = nil
      queries = ActiveRecord::QueryRecorder.new do
        result = described_class.for_rollouts([rollout.id, other_rollout.id])
      end

      expect(queries.log.count { |sql| sql.include?('"cd_rollout_transitions"') }).to eq(1)
      expect(queries.log.count { |sql| sql.include?('"cd_rollout_steps"') }).to eq(1)

      expect(result[rollout.id].size).to eq(1)
      expect(result[rollout.id].first).to have_attributes(
        state: :approved, request_transition: request, resolution_transition: resolution
      )

      expect(result[other_rollout.id].size).to eq(1)
      expect(result[other_rollout.id].first).to have_attributes(state: :pending, request_transition: other_request)
    end

    it 'omits rollout ids with no gate events from the result' do
      create(:cd_rollout_transition, rollout: rollout, event: 'start')

      expect(described_class.for_rollouts([rollout.id])).to eq({})
    end

    it 'returns an empty hash for an empty list of rollout ids' do
      expect(described_class.for_rollouts([])).to eq({})
    end
  end
end
