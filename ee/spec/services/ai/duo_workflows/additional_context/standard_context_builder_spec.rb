# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::AdditionalContext::StandardContextBuilder, feature_category: :duo_agent_platform do
  let(:schema_path) do
    Rails.root.join('app/validators/json_schemas/agent_platform/agent_platform_standard_context/1.1.0.json')
  end

  let(:schema) { JSONSchemer.schema(schema_path) }

  let_it_be(:project) { create(:project, :repository) }
  let_it_be(:current_user) { create(:user) }
  let_it_be(:service_account) { create(:user, :service_account) }

  let(:source_branch) { nil }
  let(:ref) { 'refs/workloads/1' }
  let(:session_url) { 'http://example.com/-/automate/agent-sessions/1' }

  subject(:fields) do
    described_class.build(
      project: project,
      current_user: current_user,
      service_account: service_account,
      source_branch: source_branch,
      session_url: session_url,
      ref: ref
    )
  end

  shared_examples 'a schema-conformant context' do
    it 'is valid against the schema' do
      expect(schema.valid?(fields)).to be(true), schema.validate(fields).to_a.inspect
    end
  end

  include_examples 'a schema-conformant context'

  it 'builds the standard context fields' do
    expect(fields).to eq(
      "workload_branch" => ref,
      "primary_branch" => project.default_branch_or_main,
      "session_owner_id" => current_user.id.to_s,
      "session_owner_username" => current_user.username,
      "service_account_name" => service_account.username,
      "session_url" => session_url
    )
  end

  context 'when source_branch exists in the repository' do
    let(:source_branch) { 'feature-branch' }

    before do
      project.repository.create_branch(source_branch, project.default_branch)
    end

    it 'uses source_branch as primary_branch' do
      expect(fields["primary_branch"]).to eq(source_branch)
    end
  end

  context 'when source_branch does not exist in the repository' do
    let(:source_branch) { 'non-existent-branch' }

    it 'falls back to the default branch' do
      expect(fields["primary_branch"]).to eq(project.default_branch_or_main)
    end
  end
end
