# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::Ingestion::Tasks::HooksExecution, feature_category: :vulnerability_management do
  describe '#execute' do
    let_it_be(:pipeline) { create(:ci_pipeline) }
    let_it_be(:tracked_context) do
      create(:security_project_tracked_context, :default, :tracked, project: pipeline.project)
    end

    let_it_be(:non_default_tracked_context) do
      create(:security_project_tracked_context, :tracked, context_name: 'dev', project: pipeline.project)
    end

    let_it_be(:vulnerabilities) { create_list(:vulnerability, 4) }

    let_it_be(:finding_map_1) do
      create(:finding_map, vulnerability: vulnerabilities[0], tracked_context: tracked_context, new_record: true)
    end

    let_it_be(:finding_map_2) do
      create(:finding_map, vulnerability: vulnerabilities[1], tracked_context: tracked_context, new_record: true)
    end

    let_it_be(:finding_map_3) do
      create(:finding_map, vulnerability: vulnerabilities[2], tracked_context: tracked_context)
    end

    let_it_be(:finding_map_4) do
      create(:finding_map, vulnerability: vulnerabilities[3],
        tracked_context: non_default_tracked_context, new_record: true)
    end

    let(:new_vulnerabilities) { vulnerabilities[0..1] }
    let(:new_vulnerabilities_relation) { Vulnerability.where(id: new_vulnerabilities.map(&:id)) }

    let!(:service_object) do
      described_class.new(pipeline, [finding_map_1, finding_map_2, finding_map_3, finding_map_4])
    end

    subject(:ingest_finding_remediations) { service_object.execute }

    before do
      vulnerabilities.each do |vulnerability|
        allow(vulnerability).to receive(:execute_hooks)
        allow(vulnerability).to receive(:trigger_false_positive_detection)
      end

      allow(new_vulnerabilities_relation).to receive(:with_projects).and_return(new_vulnerabilities)
      allow(Vulnerability).to receive(:id_in)
        .with(new_vulnerabilities.map(&:id)).and_return(new_vulnerabilities_relation)

      SecApplicationRecord.transaction { ingest_finding_remediations }
    end

    it 'executes the hooks associated with all new vulnerabilities' do
      expect(vulnerabilities[0]).to have_received(:execute_hooks)
      expect(vulnerabilities[1]).to have_received(:execute_hooks)
    end

    it 'triggers false positive detection associated with all new vulnerabilities' do
      expect(vulnerabilities[0]).to have_received(:trigger_false_positive_detection)
      expect(vulnerabilities[1]).to have_received(:trigger_false_positive_detection)
    end

    it 'does not execute the hooks associated with existing vulnerabilities' do
      expect(vulnerabilities[2]).not_to have_received(:execute_hooks)
    end

    it 'does not execute the hooks on non default branches' do
      expect(vulnerabilities[3]).not_to have_received(:execute_hooks)
    end

    it 'does not trigger false positive detection associated with existing vulnerabilities' do
      expect(vulnerabilities[2]).not_to have_received(:trigger_false_positive_detection)
    end

    it 'does not trigger false positive detection associated on non default branches' do
      expect(vulnerabilities[3]).not_to have_received(:trigger_false_positive_detection)
    end
  end

  describe 'project preloading' do
    let_it_be(:project) { create(:project) }
    let_it_be(:pipeline) { create(:ci_pipeline, project: project) }
    let_it_be(:tracked_context) do
      create(:security_project_tracked_context, :default, :tracked, project: project)
    end

    def build_finding_maps(count)
      create_list(:vulnerability, count, :sast, project: project).map do |vulnerability|
        create(:finding_map, vulnerability: vulnerability, tracked_context: tracked_context, new_record: true)
      end
    end

    def ingest(finding_maps)
      SecApplicationRecord.transaction { described_class.new(pipeline, finding_maps).execute }
    end

    # Eligibility reads project_setting, and `root_ancestor`, which loads namespace.
    it 'avoids N+1 database queries', :aggregate_failures do
      one_finding_map = build_finding_maps(1)
      many_finding_maps = build_finding_maps(3)

      control = ActiveRecord::QueryRecorder.new { ingest(one_finding_map) }

      expect { ingest(many_finding_maps) }.not_to exceed_query_limit(control).for_model(ProjectSetting)
      expect { ingest(many_finding_maps) }
        .not_to exceed_query_limit(control).for_query(/find_namespaces_by_id/)
    end
  end
end
