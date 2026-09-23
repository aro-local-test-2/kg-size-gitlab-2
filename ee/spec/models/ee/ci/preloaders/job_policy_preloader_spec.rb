# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::Preloaders::JobPolicyPreloader, feature_category: :continuous_integration do
  let_it_be(:project) { create(:project, :repository) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:pipeline) { create(:ci_pipeline, project: project, sha: project.commit.sha) }
  let_it_be(:environment) { create(:environment, project: project, name: 'production') }
  let_it_be(:protected_environment) { create(:protected_environment, project: project, name: environment.name) }
  let_it_be(:deploy_build) do
    create(:ci_build, :running, :deploy_job, :with_deployment, pipeline: pipeline, environment: environment.name)
  end

  let_it_be(:manual_deploy) do
    create(:ci_build, :manual, :deploy_job, :with_deployment, pipeline: pipeline, environment: environment.name)
  end

  let_it_be(:stop_build) do
    create(:ci_build, :with_deployment, pipeline: pipeline, environment: environment.name,
      options: { environment: { name: environment.name, action: 'stop' } })
  end

  let(:jobs) { pipeline.statuses.reload.to_a } # let_it_be shares the pipeline instance across examples

  def loaded(job)
    jobs.find { |loaded_job| loaded_job.id == job.id }
  end

  before do
    stub_licensed_features(protected_environments: true)
  end

  it 'preloads the protected environments and their deploy access levels for every environment job' do
    described_class.new(jobs, user).execute

    [deploy_build, manual_deploy, stop_build].each do |job|
      loaded_environment = loaded(job).persisted_environment
      expect(loaded_environment.associated_protected_environments).to contain_exactly(protected_environment)
      expect(loaded_environment.associated_protected_environments.first.association(:deploy_access_levels)).to be_loaded
    end
  end

  it 'preloads what the deployment approval summary reads' do
    described_class.new(jobs, user).execute

    job = loaded(manual_deploy)
    expect(job.deployment.association(:approvals)).to be_loaded
    expect(job.persisted_environment.associated_protected_environments.first.association(:approval_rules)).to be_loaded
    expect { job.persisted_environment.associated_approval_rules }.not_to exceed_query_limit(0)
  end

  context 'when protected environments are not licensed' do
    before do
      stub_licensed_features(protected_environments: false)
    end

    it 'skips the protected environment and approval preloads' do
      described_class.new(jobs, user).execute

      job = loaded(deploy_build)
      expect(job.persisted_environment.strong_memoized?(:associated_protected_environments)).to be(false)
      expect(job.deployment.association(:approvals)).not_to be_loaded
    end
  end

  context 'with an approval rule' do
    let_it_be(:approval_rule) do
      create(:protected_environment_approval_rule, user: user, protected_environment: protected_environment)
    end

    def create_manual_deploy(factory = :ci_build)
      create(factory, :manual, :deploy_job, :with_deployment, pipeline: pipeline, environment: environment.name)
    end

    it 'keeps approval state separate for deployments sharing the environment' do
      approved_deploy = create_manual_deploy
      create(:deployment_approval, deployment: approved_deploy.deployment, user: user, approval_rule: approval_rule)

      described_class.new(jobs, user).execute

      expect(loaded(approved_deploy).deployment).not_to be_waiting_for_approval
      expect(loaded(manual_deploy).deployment).to be_waiting_for_approval
      expect(loaded(approved_deploy).deployment).not_to be_waiting_for_approval
    end

    it 'checks the playability of manual deployment bridges without a query per bridge' do
      create_manual_deploy(:ci_bridge)
      control = ActiveRecord::QueryRecorder.new { described_class.new(pipeline.statuses.reload.to_a, user).execute }

      2.times { create_manual_deploy(:ci_bridge) }

      expect { described_class.new(pipeline.statuses.reload.to_a, user).execute }.not_to exceed_query_limit(control)
    end
  end

  it 'replaces protected environments memoized before the preload ran' do
    loaded(manual_deploy).playable?

    described_class.new(jobs, user).execute

    protected_env = loaded(manual_deploy).persisted_environment.associated_protected_environments.first
    expect(protected_env.association(:deploy_access_levels)).to be_loaded
  end
end
