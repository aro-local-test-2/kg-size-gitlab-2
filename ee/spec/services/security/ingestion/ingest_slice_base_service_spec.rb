# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::Ingestion::IngestSliceBaseService, :elastic, feature_category: :vulnerability_management do
  let_it_be(:pipeline) { create(:ci_pipeline) }
  let_it_be(:vulnerability_1) { create(:vulnerability, :with_read) }
  let_it_be(:vulnerability_2) { create(:vulnerability, :with_read) }

  let(:finding_map_1) { create(:finding_map, vulnerability: vulnerability_1) }
  let(:finding_map_2) { create(:finding_map, vulnerability: vulnerability_2) }
  let(:finding_maps) { [finding_map_1, finding_map_2] }

  let(:service_class) do
    Class.new(described_class) do
      const_set(:SEC_DB_TASKS, %w[TaskOne])
      const_set(:MAIN_DB_TASKS, %w[TaskTwo])
    end
  end

  subject(:service) { service_class.new(pipeline, finding_maps) }

  before do
    stub_const('Security::Ingestion::Tasks::TaskOne', Class.new)
    stub_const('Security::Ingestion::Tasks::TaskTwo', Class.new)

    allow(Security::Ingestion::Tasks::TaskOne).to receive(:execute).and_return(true)
    allow(Security::Ingestion::Tasks::TaskTwo).to receive(:execute).and_return(true)
  end

  describe '#execute' do
    it 'executes all tasks and returns the vulnerability IDs' do
      expect(Security::Ingestion::Tasks::TaskOne).to receive(:execute).with(pipeline, finding_maps)
      expect(Security::Ingestion::Tasks::TaskTwo).to receive(:execute).with(pipeline, finding_maps)

      result = service.execute

      expect(result).to contain_exactly(vulnerability_1.id, vulnerability_2.id)
    end

    it 'does not run the namespace statistics task for a subclass that does not declare it' do
      expect(Security::Ingestion::Tasks::IngestVulnerabilityNamespaceStatistics).not_to receive(:execute)

      service.execute
    end

    context 'with IngestVulnerabilityNamespaceStatistics in the task list' do
      let(:service_class) do
        Class.new(described_class) do
          const_set(:SEC_DB_TASKS, %i[TaskOne IngestVulnerabilityNamespaceStatistics])
          const_set(:MAIN_DB_TASKS, %i[])
        end
      end

      let(:namespace_statistics) { Security::Ingestion::Tasks::IngestVulnerabilityNamespaceStatistics }

      before do
        allow(namespace_statistics).to receive(:execute)
      end

      it 'runs it after the rest of the slice' do
        expect(Security::Ingestion::Tasks::TaskOne).to receive(:execute).ordered
        expect(namespace_statistics).to receive(:execute).ordered.with(pipeline, finding_maps)

        service.execute
      end

      context 'when it fails' do
        before do
          allow(namespace_statistics).to receive(:execute).and_raise(ActiveRecord::StatementInvalid)
          allow(Security::Ingestion::Tasks::TaskOne).to receive(:execute) do
            create(:vulnerabilities_identifier, project: pipeline.project)
          end
        end

        it 'keeps the writes the slice already committed' do
          expect { suppress(ActiveRecord::StatementInvalid) { service.execute } }
            .to change { Vulnerabilities::Identifier.count }.by(1)
        end

        context 'and the feature flag is disabled' do
          before do
            stub_feature_flags(ingest_namespace_statistics_in_own_transaction: false)
          end

          it 'rolls those writes back, since it shares the slice transaction' do
            expect { suppress(ActiveRecord::StatementInvalid) { service.execute } }
              .not_to change { Vulnerabilities::Identifier.count }
          end
        end
      end
    end

    it_behaves_like 'sync vulnerabilities changes to ES' do
      let(:expected_vulnerabilities) { [vulnerability_1, vulnerability_2].map(&:vulnerability_read) }

      subject do
        service.execute
      end
    end
  end
end
