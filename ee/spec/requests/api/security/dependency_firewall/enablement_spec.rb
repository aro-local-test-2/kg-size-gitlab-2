# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Security::DependencyFirewall::Enablement, feature_category: :dependency_firewall do
  let_it_be_with_reload(:group) { create(:group) }
  let_it_be(:project) { create(:project, :private, group: group) }
  let_it_be(:public_project) { create(:project, :public, group: group) }
  let_it_be(:user) { create(:user, reporter_of: project) }
  let_it_be(:guest) { create(:user, guest_of: project) }
  let_it_be(:non_member) { create(:user) }

  let_it_be(:pat) { create(:personal_access_token, user: user, scopes: %w[read_api]) }
  let_it_be(:guest_pat) { create(:personal_access_token, user: guest, scopes: %w[read_api]) }
  let_it_be(:non_member_pat) { create(:personal_access_token, user: non_member, scopes: %w[read_api]) }

  let(:path) { "/projects/#{project.id}/dependency_firewall/enablement" }

  before_all do
    settings = group.namespace_settings || group.create_namespace_settings!
    settings.update!(dependency_firewall_enabled: true)
  end

  before do
    stub_licensed_features(dependency_firewall: true)
    stub_saas_features(dependency_firewall: true)
  end

  # The three conditions behind the answer, across both places the setting can live. The `saas`
  # column selects which one Availability reads, and each row sets the other source to the opposite
  # value, so a row also fails if the wrong source is consulted.
  describe 'the enablement matrix' do
    using RSpec::Parameterized::TableSyntax

    where(:saas, :flag, :licence, :setting, :status, :enabled) do
      true  | true  | true  | true  | :ok        | true
      true  | false | true  | true  | :not_found | false
      true  | true  | false | true  | :ok        | false
      true  | true  | true  | false | :ok        | false
      false | true  | true  | true  | :ok        | true
      false | false | true  | true  | :not_found | false
      false | true  | false | true  | :ok        | false
      false | true  | true  | false | :ok        | false
    end

    with_them do
      before do
        stub_saas_features(dependency_firewall: saas)
        stub_licensed_features(dependency_firewall: licence)
        stub_feature_flags(dependency_firewall_phase1: flag)

        group.namespace_settings.update!(dependency_firewall_enabled: saas ? setting : !setting)
        stub_application_setting(dependency_firewall_enabled: saas ? !setting : setting)
      end

      it 'answers with the expected status and enablement' do
        get api(path, personal_access_token: pat)

        expect(response).to have_gitlab_http_status(status)
        expect(json_response['enabled']).to be(enabled)
      end
    end
  end

  # Two properties the matrix cannot express, both about the shape of the response rather than its
  # value, and both load-bearing for the documented client contract.
  describe 'the shape of a not-enabled answer' do
    it 'says nothing about which condition produced it' do
      group.namespace_settings.update!(dependency_firewall_enabled: false)

      get api(path, personal_access_token: pat)

      expect(json_response.keys).to eq(['enabled'])
    end

    # A flag-off 404 carries `enabled`; an unreadable project's does not. A client tells the two
    # apart on exactly that, so both halves are pinned here.
    it 'carries the answer in a flag-off not-found, unlike an unreadable project' do
      stub_feature_flags(dependency_firewall_phase1: false)

      get api(path, personal_access_token: pat)

      expect(response).to have_gitlab_http_status(:not_found)
      expect(json_response).to eq({ 'enabled' => false })

      get api(path, personal_access_token: non_member_pat)

      expect(response).to have_gitlab_http_status(:not_found)
      expect(json_response).not_to have_key('enabled')
      expect(json_response['message']).to include('Project')
    end
  end

  context 'without authentication' do
    # Anonymous callers can read a public project, so refusing here is what keeps the firewall's
    # rollout across public projects from being externally observable.
    it 'refuses the request even for a public project' do
      get api("/projects/#{public_project.id}/dependency_firewall/enablement")

      expect(response).to have_gitlab_http_status(:unauthorized)
    end
  end

  context 'when the caller cannot read the project' do
    it 'returns not found, which the client distinguishes from a not-enabled answer' do
      get api(path, personal_access_token: non_member_pat)

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  # Reading whether the firewall is on is authorized by project read access alone. These two pin
  # that boundary, which is wider than the Developer-level ability the firewall's GraphQL fields
  # use: without them, narrowing the endpoint's ability would still pass every other scenario.
  context 'when the caller only has project read access' do
    it 'answers a Guest member of the private project' do
      get api(path, personal_access_token: guest_pat)

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['enabled']).to be(true)
    end

    it 'answers an authenticated non-member on a public project' do
      get api("/projects/#{public_project.id}/dependency_firewall/enablement",
        personal_access_token: non_member_pat)

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['enabled']).to be(true)
    end
  end

  describe 'supported credential types' do
    let_it_be(:project_bot) { create(:user, :project_bot) }
    let_it_be(:group_bot) { create(:user, :project_bot) }
    let_it_be(:project_access_token) { create(:personal_access_token, user: project_bot, scopes: %w[read_api]) }
    let_it_be(:group_access_token) { create(:personal_access_token, user: group_bot, scopes: %w[read_api]) }
    let_it_be(:oauth_token) { create(:oauth_access_token, user: user, scopes: [:read_api]) }

    before_all do
      project.add_reporter(project_bot)
      group.add_reporter(group_bot)
    end

    it 'answers a personal access token' do
      get api(path, personal_access_token: pat)

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['enabled']).to be(true)
    end

    it 'answers a project access token' do
      get api(path, personal_access_token: project_access_token)

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['enabled']).to be(true)
    end

    it 'answers a group access token' do
      get api(path, personal_access_token: group_access_token)

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['enabled']).to be(true)
    end

    it 'answers an OAuth token' do
      get api(path, oauth_access_token: oauth_token)

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['enabled']).to be(true)
    end

    # The reason the transport is REST rather than GraphQL: GraphQL's authenticator refuses job
    # tokens by design, so CI could not call it without widening a platform guarantee.
    it 'answers a CI job token' do
      pipeline = create(:ci_pipeline, project: project)
      job = create(:ci_build, :running, pipeline: pipeline, project: project, user: user)

      get api(path, job_token: job.token)

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['enabled']).to be(true)
    end

    # A job token refused by the target's inbound scope gets 403, not the 404 a user-credential
    # caller would get, so the documented not-found contract has to exclude this path.
    it 'refuses a job token from a project outside the target token scope' do
      other_project = create(:project, :private)
      pipeline = create(:ci_pipeline, project: other_project)
      job = create(:ci_build, :running, pipeline: pipeline, project: other_project, user: user)

      get api(path, job_token: job.token)

      expect(response).to have_gitlab_http_status(:forbidden)
      expect(json_response['message']).to include('job token')
    end
  end

  # A job token is confined to its own project. The inbound allowlist would otherwise let a token
  # from an allowlisted project read this, so the case that matters is an allowlisted cross-project
  # token: the framework would admit it, and this endpoint must not.
  describe 'a job token from another project' do
    let_it_be(:job_project) { create(:project, :private) }

    def job_token
      pipeline = create(:ci_pipeline, project: job_project)
      create(:ci_build, :running, pipeline: pipeline, project: job_project, user: user).token
    end

    it 'is refused even when allowlisted inbound with full permissions' do
      create(:ci_job_token_project_scope_link,
        source_project: project,
        target_project: job_project,
        direction: :inbound,
        default_permissions: true)

      get api(path, job_token: job_token)

      expect(response).to have_gitlab_http_status(:forbidden)
      expect(json_response['message']).to include('its own project')
    end

    it 'is refused when not allowlisted at all' do
      get api(path, job_token: job_token)

      expect(response).to have_gitlab_http_status(:forbidden)
    end
  end

  describe 'rate limiting' do
    let_it_be(:other_reader) { create(:user, reporter_of: project) }
    let_it_be(:other_pat) { create(:personal_access_token, user: other_reader, scopes: %w[read_api]) }

    let(:current_user) { user }

    def request
      get api(path, personal_access_token: pat)
    end

    # The limit is keyed on the caller, not the project, so a different caller is what proves the
    # scope. A second project would share this caller's budget.
    def request_with_second_scope
      get api(path, personal_access_token: other_pat)
    end

    it_behaves_like 'rate limited endpoint', rate_limit_key: :dependency_firewall_enablement
  end

  it_behaves_like 'authorizing granular token permissions', :read_project,
    legacy_token_scopes: %w[read_api] do
    let(:boundary_object) { project }
    let(:request) do
      get api(path, personal_access_token: pat)
    end
  end

  # A second invocation on a public boundary, so the shared example's public-access-bypass case
  # runs instead of skipping. The private invocation above still covers the other scenarios.
  it_behaves_like 'authorizing granular token permissions', :read_project,
    legacy_token_scopes: %w[read_api] do
    let(:boundary_object) { public_project }
    let(:request) do
      get api("/projects/#{public_project.id}/dependency_firewall/enablement", personal_access_token: pat)
    end
  end
end
