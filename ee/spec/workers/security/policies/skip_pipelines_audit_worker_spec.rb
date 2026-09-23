# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::Policies::SkipPipelinesAuditWorker, feature_category: :security_policy_management do
  describe '#perform' do
    let_it_be(:pipeline) { create(:ci_pipeline) }

    subject(:run_worker) { described_class.new.perform(pipeline_id) }

    shared_examples_for 'does not call PipelineSkippedAuditor' do
      specify do
        expect(Security::SecurityOrchestrationPolicies::PipelineSkippedAuditor).not_to receive(:new)

        run_worker
      end
    end

    context 'when pipeline is not found' do
      let(:pipeline_id) { non_existing_record_id }

      it_behaves_like 'does not call PipelineSkippedAuditor'
    end

    context 'when pipeline exist' do
      let(:pipeline_id) { pipeline.id }

      context 'when security_orchestration_policies feature is available' do
        before do
          stub_licensed_features(security_orchestration_policies: true)
        end

        it 'calls PipelineSkippedAuditor' do
          expect_next_instance_of(Security::SecurityOrchestrationPolicies::PipelineSkippedAuditor,
            pipeline: pipeline) do |auditor|
            expect(auditor).to receive(:audit)
          end

          run_worker
        end

        it_behaves_like 'an idempotent worker' do
          let(:job_args) { pipeline.id }
        end
      end

      context 'when security_orchestration_policies feature is not available' do
        let(:pipeline_id) { pipeline.id }

        before do
          stub_licensed_features(security_orchestration_policies: false)
        end

        it_behaves_like 'does not call PipelineSkippedAuditor'
      end

      context 'when the dependency firewall is enforced without the security_orchestration_policies licence' do
        let_it_be_with_reload(:root_group) { create(:group) }
        let_it_be(:dependency_firewall_project) { create(:project, group: root_group) }
        let_it_be(:dependency_firewall_pipeline) { create(:ci_pipeline, project: dependency_firewall_project) }

        let(:pipeline_id) { dependency_firewall_pipeline.id }

        include_context 'with dependency firewall enforced without security_orchestration_policies licence'

        it 'has the dependency firewall enforced for the project' do
          expect(::Security::PolicyAvailability.any_available?(dependency_firewall_project)).to be(true)
        end

        it_behaves_like 'does not call PipelineSkippedAuditor'
      end
    end
  end
end
