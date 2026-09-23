# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::Concerns::GovernanceResolution, feature_category: :ai_agents do
  let(:host_class) do
    Class.new do
      include ::Ai::DuoWorkflows::Concerns::GovernanceResolution

      public :resolve_governance_with_retry, :governance_failure_message
    end
  end

  let(:host) { host_class.new }
  let(:service) { instance_double(::Ai::ToolRules::ResolutionService) }
  let(:transient_failure) { ServiceResponse.error(message: 'something went wrong') }
  let(:ungoverned_failure) do
    ServiceResponse.error(message: 'Surface is ungoverned', reason: :ungoverned_surface)
  end

  describe '#resolve_governance_with_retry' do
    it 'returns the first success without retrying' do
      success = ServiceResponse.success(payload: {})
      expect(service).to receive(:execute).once.and_return(success)

      expect(host.resolve_governance_with_retry(service)).to eq(success)
    end

    it 'retries a transient failure and returns the last response' do
      expect(service).to receive(:execute)
        .exactly(described_class::MAX_GOVERNANCE_RETRIES).times
        .and_return(transient_failure)

      expect(host.resolve_governance_with_retry(service)).to eq(transient_failure)
    end

    context 'when the surface is ungoverned' do
      it 'gives up after one attempt, since retrying cannot change a surface' do
        expect(service).to receive(:execute).once.and_return(ungoverned_failure)

        expect(host.resolve_governance_with_retry(service).reason).to eq(:ungoverned_surface)
      end

      it 'logs nothing, leaving the single message to the caller' do
        allow(service).to receive(:execute).and_return(ungoverned_failure)

        expect(Gitlab::AppLogger).not_to receive(:warn)

        host.resolve_governance_with_retry(service)
      end
    end
  end

  describe '#governance_failure_message' do
    it 'names the retry count when retries were genuinely exhausted' do
      expect(host.governance_failure_message('failing closed with no tools', transient_failure))
        .to eq(
          "Governance resolution failed after #{described_class::MAX_GOVERNANCE_RETRIES} retries, " \
            "failing closed with no tools"
        )
    end

    it 'does not claim retries for an ungoverned surface' do
      expect(host.governance_failure_message('failing closed with no tools', ungoverned_failure))
        .to eq('Governance resolution skipped for an ungoverned surface, failing closed with no tools')
    end

    it 'treats a missing result as a genuine failure' do
      expect(host.governance_failure_message('failing closed with no tools', nil))
        .to include('after')
    end
  end
end
