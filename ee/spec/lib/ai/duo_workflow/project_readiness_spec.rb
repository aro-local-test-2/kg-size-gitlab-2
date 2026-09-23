# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflow::ProjectReadiness, feature_category: :duo_agent_platform do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, namespace: group) }
  let_it_be(:user) { create(:user, maintainer_of: project) }

  let(:readiness) { described_class.new(project, user) }

  describe '#platform_enabled?' do
    subject { readiness.platform_enabled? }

    it 'reports whether the Agent Platform is on above this project' do
      allow(::Ai::DuoWorkflow).to receive(:duo_agent_platform_available?).with(project).and_return(true)

      is_expected.to be(true)
    end

    it 'is false when the platform is off' do
      allow(::Ai::DuoWorkflow).to receive(:duo_agent_platform_available?).with(project).and_return(false)

      is_expected.to be(false)
    end

    # The self-managed path re-reads the Ai::Setting singleton on every call.
    it 'is read once' do
      expect(::Ai::DuoWorkflow).to receive(:duo_agent_platform_available?).once.and_return(true)

      3.times { readiness.platform_enabled? }
    end
  end

  describe '#runner_available?' do
    subject { readiness.runner_available? }

    let(:workload_tag) { ::Ai::DuoWorkflows::Workflow::WORKLOAD_TAG }

    def create_duo_runner(*traits, **runner_args)
      create(:ci_runner, :online, *traits, tag_list: [workload_tag], **runner_args).tap do |runner|
        create(:ci_runner_machine, runner: runner, executor_type: :docker)
      end
    end

    context 'with an online, Duo-tagged instance runner on a Docker executor' do
      before do
        create_duo_runner(:instance)
      end

      it { is_expected.to be(true) }
    end

    it 'is false when no runner carries the workload tag' do
      runner = create(:ci_runner, :instance, :online, tag_list: %w[some-other-tag])
      create(:ci_runner_machine, runner: runner, executor_type: :docker)

      is_expected.to be(false)
    end

    it 'is false when the only tagged runner is paused' do
      create_duo_runner(:instance, :paused)

      is_expected.to be(false)
    end

    it 'is false when the only tagged runner has stopped checking in' do
      create_duo_runner(:instance, :offline)

      is_expected.to be(false)
    end

    it 'is false when the runner has no Docker-compatible executor' do
      runner = create(:ci_runner, :instance, :online, tag_list: [workload_tag])
      create(:ci_runner_machine, runner: runner, executor_type: :shell)

      is_expected.to be(false)
    end

    it 'is false when the runner never registered a manager' do
      create(:ci_runner, :instance, :online, tag_list: [workload_tag])

      is_expected.to be(false)
    end

    context 'when the only tagged runner is a project runner' do
      before do
        create_duo_runner(:project, projects: [project])
      end

      it { is_expected.to be(false) }

      context 'when duo_runner_restrictions is disabled' do
        before do
          stub_feature_flags(duo_runner_restrictions: false)
        end

        it { is_expected.to be(true) }
      end
    end

    context 'with a top-level group runner' do
      before do
        create_duo_runner(:group, groups: [group])
      end

      it { is_expected.to be(true) }
    end

    it 'looks the runner up once, however many readers ask' do
      expect(project).to receive(:all_available_runners).once.and_call_original

      readiness.runner_available?
      readiness.runner_available?
      readiness.usable_runner_type
    end
  end

  describe '#usable_runner_type' do
    subject { readiness.usable_runner_type }

    let(:workload_tag) { ::Ai::DuoWorkflows::Workflow::WORKLOAD_TAG }

    def create_duo_runner(*traits, **runner_args)
      create(:ci_runner, :online, *traits, tag_list: [workload_tag], **runner_args).tap do |runner|
        create(:ci_runner_machine, runner: runner, executor_type: :docker)
      end
    end

    it 'is instance_type for an instance runner' do
      create_duo_runner(:instance)

      is_expected.to eq('instance_type')
    end

    it 'is group_type for a top-level group runner' do
      create_duo_runner(:group, groups: [group])

      is_expected.to eq('group_type')
    end

    context 'when duo_runner_restrictions is disabled, so project runners count too' do
      before do
        stub_feature_flags(duo_runner_restrictions: false)
      end

      it 'is project_type for a project runner' do
        create_duo_runner(:project, projects: [project])

        is_expected.to eq('project_type')
      end
    end

    it 'is nil when nothing qualifies' do
      is_expected.to be_nil
    end
  end

  describe '#agent_config_present?' do
    let_it_be(:repo_project) { create(:project, :repository, namespace: group, maintainers: user) }

    it 'is false when the file is absent from the default branch' do
      expect(described_class.new(repo_project, user).agent_config_present?).to be(false)
    end

    context 'when the file is on the default branch' do
      # A separate project: repository writes are not rolled back between examples, so
      # committing to a shared project would leak into every other example.
      let_it_be(:configured_project) do
        create(:project, :repository, namespace: group).tap do |configured|
          configured.repository.create_file(
            configured.creator,
            described_class::AGENT_CONFIG_PATH,
            "image: ruby:3.3\n",
            message: 'Add agent config',
            branch_name: configured.default_branch
          )
        end
      end

      it { expect(described_class.new(configured_project, user)).to be_agent_config_present }
    end
  end

  describe '#agent_config_merge_request' do
    let_it_be(:merge_request_project) { create(:project, :repository, namespace: group, maintainers: user) }
    let(:merge_request_readiness) { described_class.new(merge_request_project, user) }

    it 'is nil when nothing is open' do
      expect(merge_request_readiness.agent_config_merge_request).to be_nil
    end

    context 'when an open merge request adds the file' do
      let_it_be(:merge_request) do
        merge_request_project.repository.create_file(
          merge_request_project.creator,
          described_class::AGENT_CONFIG_PATH,
          "image: ruby:3.3\n",
          message: 'Add agent config',
          branch_name: 'add-agent-config'
        )

        create(:merge_request,
          source_project: merge_request_project,
          target_project: merge_request_project,
          source_branch: 'add-agent-config',
          target_branch: merge_request_project.default_branch)
      end

      it 'finds it, so the row can link to it instead of generating a duplicate' do
        expect(merge_request_readiness.agent_config_merge_request).to eq(merge_request)
      end

      it 'is skipped once the file is already on the default branch' do
        allow(merge_request_readiness).to receive(:agent_config_present?).and_return(true)

        expect(merge_request_readiness.agent_config_merge_request).to be_nil
      end
    end
  end

  describe '#agent_config_workflow_id' do
    it 'is nil when no generation run is active' do
      expect(readiness.agent_config_workflow_id).to be_nil
    end

    context 'when a generation run is active' do
      let(:workflow) { build_stubbed(:duo_workflows_workflow) }

      before do
        allow_next_instance_of(::Ai::DuoWorkflow::AgentConfigWorkflowTracker) do |tracker|
          allow(tracker).to receive(:active_workflow).and_return(workflow)
        end
      end

      it 'returns the workflow id, so the row can link the running session' do
        expect(readiness.agent_config_workflow_id).to eq(workflow.id)
      end

      it 'is nil once the file is on the default branch' do
        allow(readiness).to receive(:agent_config_present?).and_return(true)

        expect(readiness.agent_config_workflow_id).to be_nil
      end
    end
  end

  describe '#repository_empty?' do
    let_it_be(:repo_project) { create(:project, :repository, namespace: group) }

    it 'is true when the project has no commits' do
      expect(readiness.repository_empty?).to be(true)
    end

    it 'is false when the default branch has commits' do
      expect(described_class.new(repo_project, user).repository_empty?).to be(false)
    end
  end

  describe '#generate_available?' do
    let_it_be(:repo_project) { create(:project, :repository, namespace: group) }

    let(:readiness_project) { repo_project }
    let(:readiness) { described_class.new(readiness_project, user) }

    subject { readiness.generate_available? }

    it 'is false when the developer flow has no consumer for the project' do
      is_expected.to be(false)
    end

    context 'when the catalog is unseeded' do
      before do
        allow(::Ai::Catalog::FoundationalFlow).to receive(:[]).and_return(nil)
      end

      it 'is false rather than raising' do
        is_expected.to be(false)
      end
    end

    context 'when a consumer exists for the project' do
      before do
        consumer = create(:ai_catalog_item_consumer, :for_flow, project: readiness_project)

        allow(::Ai::Catalog::FoundationalFlow.developer_v1).to receive(:catalog_item)
          .and_return(consumer.item)
      end

      it { is_expected.to be(true) }

      context 'when the repository is empty' do
        let(:readiness_project) { project }

        it 'is false, because the generate run has no commit to branch from' do
          is_expected.to be(false)
        end
      end
    end
  end

  describe '#mcp_servers_count' do
    let_it_be(:mcp_group, freeze: false) { create(:group) }
    let_it_be(:mcp_project) { create(:project, group: mcp_group) }
    let_it_be(:organization) { mcp_project.organization }

    let(:project) { mcp_project }
    let(:user) { create(:user, maintainer_of: mcp_project, organizations: [organization]) }

    subject(:count) { readiness.mcp_servers_count }

    before do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?)
        .with(user, :read_ai_catalog_item_consumer, mcp_project).and_return(true)
      allow(::Ai::Catalog).to receive(:mcp_servers_available?).with(user).and_return(true)
    end

    it 'is zero when no configured agent uses an MCP server' do
      expect(count).to eq(0)
    end

    context 'when configured agents use MCP servers' do
      let_it_be(:server) { create(:ai_catalog_mcp_server, organization: organization) }
      let_it_be(:shared_server) { create(:ai_catalog_mcp_server, organization: organization) }

      before_all do
        create(:ai_catalog_mcp_server, organization: organization)

        [[server.id, shared_server.id], [shared_server.id]].each do |server_ids|
          create_configured_agent(server_ids)
        end

        mcp_group.namespace_settings.update!(duo_custom_agents_enabled: true)
      end

      def create_configured_agent(server_ids)
        agent = create(:ai_catalog_agent, organization: mcp_project.organization)
        create(:ai_catalog_agent_version, item: agent, definition: {
          'system_prompt' => 'Test prompt',
          'tools' => [],
          'user_prompt' => '',
          'mcp_servers' => server_ids
        })
        create(:ai_catalog_item_consumer, project: mcp_project, item: agent)
      end

      it 'counts each server of the configured agents once' do
        expect(count).to eq(2)
      end

      it 'is read once' do
        expect(::Ai::Catalog::ItemConsumersFinder).to receive(:new).once.and_call_original

        2.times { readiness.mcp_servers_count }
      end

      it 'does not run a query per configured agent' do
        control = ActiveRecord::QueryRecorder.new { described_class.new(project, user).mcp_servers_count }

        [[server.id], [shared_server.id]].each { |server_ids| create_configured_agent(server_ids) }

        expect { described_class.new(project, user).mcp_servers_count }.not_to exceed_query_limit(control)
      end
    end
  end
end
