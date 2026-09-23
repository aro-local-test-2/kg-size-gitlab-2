# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Security::DependencyFirewall::Evaluations, feature_category: :dependency_firewall do
  let_it_be_with_reload(:group) { create(:group) }
  let_it_be_with_reload(:project) { create(:project, :private, group: group) }
  let_it_be(:user) { create(:user, reporter_of: project) }
  let_it_be(:pat) { create(:personal_access_token, user: user, scopes: %w[api]) }

  let(:path) { "/projects/#{project.id}/dependency_firewall/evaluate" }
  let(:params) { { ecosystem: 'npm', name: 'lodash', version: '4.17.21' } }

  # Mirrors the helper in evaluate_package_service_spec.rb.
  def create_firewall_policy(rules:, name: 'df-policy', enforcement_type: 'enforced')
    policy_config = create(:security_orchestration_policy_configuration, project: project)

    policy = create(:security_policy, :dependency_firewall_policy,
      security_orchestration_policy_configuration: policy_config,
      name: name,
      policy_index: 0,
      linked_projects: [project],
      content: {
        name: name,
        enabled: true,
        enforcement_type: enforcement_type,
        rules: rules,
        bypass_settings: { users: [], access_tokens: [] }
      })

    rules.each_with_index do |rule_hash, index|
      create(:dependency_firewall_policy_rule,
        security_policy: policy,
        rule_index: index,
        type: Security::DependencyFirewallPolicyRule.types[rule_hash[:type]],
        content: rule_hash.except(:type))
    end
  end

  def stub_licences_for(package)
    allow_next_instance_of(Security::DependencyFirewall::FetchPackageLicensesService) do |svc|
      allow(svc).to receive(:execute).and_return(package)
    end
  end

  before do
    stub_licensed_features(dependency_firewall: true)
    stub_saas_features(dependency_firewall: true)
    settings = group.namespace_settings || group.create_namespace_settings!
    settings.update!(dependency_firewall_enabled: true)
  end

  context 'when a policy denies the package' do
    before do
      create_firewall_policy(rules: [{ type: 'license', denied: [{ name: 'MIT' }] }])
      stub_licences_for([{ name: 'MIT' }])
    end

    it 'returns the blocked outcome and its reason' do
      post api(path, personal_access_token: pat), params: params

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['outcome']).to eq('blocked')
      expect(json_response['reason']).to include('df-policy')
    end

    # The reason the transport is REST rather than GraphQL: GraphQL's authenticator refuses job
    # tokens by design, so CI could not call it without widening a platform guarantee.
    it 'accepts a CI job token' do
      pipeline = create(:ci_pipeline, project: project)
      job = create(:ci_build, :running, pipeline: pipeline, project: project, user: user)

      post api(path, job_token: job.token), params: params

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['outcome']).to eq('blocked')
    end

    # Refused by Ci::JobToken::Scope before the endpoint runs, which is what the
    # `job_token_policies` route setting buys without any code of our own.
    it 'refuses a job token from a project outside the token scope' do
      other_project = create(:project, :private)
      pipeline = create(:ci_pipeline, project: other_project)
      job = create(:ci_build, :running, pipeline: pipeline, project: other_project, user: user)

      post api(path, job_token: job.token), params: params

      expect(response).to have_gitlab_http_status(:forbidden)
      expect(json_response['message']).to include('job token not allowed')
    end

    # The allowlist is not enough on its own. :read_package is public on a public project, so
    # without the self-referential check an inbound allowlist entry would let another project's
    # pipeline read this project's policy verdicts, and the verdict names the policy.
    it 'refuses an allowlisted job token from another project' do
      public_project = create(:project, :public)
      other_project = create(:project, :private)
      create(:ci_job_token_project_scope_link,
        source_project: public_project, target_project: other_project, direction: :inbound,
        job_token_policies: [:read_packages], default_permissions: false)
      pipeline = create(:ci_pipeline, project: other_project)
      job = create(:ci_build, :running, pipeline: pipeline, project: other_project,
        user: create(:user))

      post api("/projects/#{public_project.id}/dependency_firewall/evaluate", job_token: job.token),
        params: params

      expect(response).to have_gitlab_http_status(:forbidden)
      expect(json_response['message']).to include('can only evaluate packages for its own project')
    end

    it 'refuses an anonymous request' do
      post api(path), params: params

      expect(response).to have_gitlab_http_status(:unauthorized)
    end

    it 'returns not found for a caller with no access to the project' do
      other_pat = create(:personal_access_token, user: create(:user), scopes: %w[api])

      post api(path, personal_access_token: other_pat), params: params

      expect(response).to have_gitlab_http_status(:not_found)
    end

    # The firewall evaluates dependencies fetched from upstream registries, so the setting that
    # governs whether the project hosts packages on GitLab must not gate it. Before the dedicated
    # permission, the packages_disabled veto on :read_package made this a 403 for every role.
    it 'evaluates for a project with the package registry disabled' do
      project.update!(packages_enabled: false)

      post api(path, personal_access_token: pat), params: params

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['outcome']).to eq('blocked')
    end

    it 'refuses a guest' do
      guest_pat = create(:personal_access_token, user: create(:user, guest_of: project), scopes: %w[api])

      post api(path, personal_access_token: guest_pat), params: params

      expect(response).to have_gitlab_http_status(:forbidden)
    end

    # :read_package is public on a public project; the dedicated permission is membership-gated,
    # so a verdict (which names the policy that produced it) is not readable by arbitrary callers.
    it 'refuses a non-member on a public project' do
      public_project = create(:project, :public, group: group)
      non_member_pat = create(:personal_access_token, user: create(:user), scopes: %w[api])

      post api("/projects/#{public_project.id}/dependency_firewall/evaluate",
        personal_access_token: non_member_pat), params: params

      expect(response).to have_gitlab_http_status(:forbidden)
    end

    it 'returns not found when the feature flag is disabled' do
      stub_feature_flags(dependency_firewall_phase1: false)

      post api(path, personal_access_token: pat), params: params

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'rejects a blank name before evaluating' do
      post api(path, personal_access_token: pat), params: params.merge(name: '')

      expect(response).to have_gitlab_http_status(:bad_request)
      expect(json_response['message']).to include('Package name cannot be blank')
    end

    it 'rejects a blank version before evaluating' do
      post api(path, personal_access_token: pat), params: params.merge(version: '')

      expect(response).to have_gitlab_http_status(:bad_request)
      expect(json_response['message']).to include('Package version cannot be blank')
    end

    it 'rejects an ecosystem outside the supported values' do
      post api(path, personal_access_token: pat), params: params.merge(ecosystem: 'not-real')

      expect(response).to have_gitlab_http_status(:bad_request)
    end

    context 'with a pass-through ecosystem' do
      using RSpec::Parameterized::TableSyntax

      # Named coordinates only need to be plausible: the license fetch is stubbed, so the
      # firewall reaches PolicyEvaluator and the deny-MIT rule drives the blocked verdict.
      where(:ecosystem, :name, :version) do
        'composer' | 'monolog/monolog'          | '2.9.1'
        'conan'    | 'openssl'                  | '3.2.0'
        'golang'   | 'github.com/gin-gonic/gin' | 'v1.9.1'
        'nuget'    | 'Newtonsoft.Json'          | '13.0.3'
        'cargo'    | 'serde'                    | '1.0.203'
        'swift'    | 'github.com/vapor/vapor'   | '4.92.0'
        'pub'      | 'http'                     | '1.2.1'
      end

      with_them do
        it 'accepts and evaluates the ecosystem' do
          post api(path, personal_access_token: pat),
            params: { ecosystem: ecosystem, name: name, version: version }

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response['outcome']).to eq('blocked')
        end
      end
    end

    it 'rejects an operation outside the two supported values' do
      post api(path, personal_access_token: pat), params: params.merge(operation: 'push')

      expect(response).to have_gitlab_http_status(:bad_request)
    end

    # The audit operation label is the observable difference between the two operations, so it is
    # what proves the attribute reached the evaluation rather than being dropped at the transport.
    context 'with the audit licence enabled' do
      before do
        stub_licensed_features(dependency_firewall: true, audit_events: true)
      end

      it 'records an upload evaluation as a package upload', :aggregate_failures do
        post api(path, personal_access_token: pat), params: params.merge(operation: 'upload')

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['outcome']).to eq('blocked')
        expect(AuditEvents::ProjectAuditEvent.last.details[:operation]).to eq('package upload')
      end

      it 'records an evaluation without an operation as a package download', :aggregate_failures do
        post api(path, personal_access_token: pat), params: params

        expect(response).to have_gitlab_http_status(:ok)
        expect(AuditEvents::ProjectAuditEvent.last.details[:operation]).to eq('package download')
      end
    end

    it_behaves_like 'authorizing granular token permissions', :create_dependency_firewall_evaluation do
      let(:boundary_object) { project }
      let(:request) do
        post api(path, personal_access_token: pat), params: params
      end
    end
  end

  context 'when rate limited' do
    let_it_be(:other_project) { create(:project, :private, group: group) }
    let(:current_user) { user }

    before_all do
      other_project.add_reporter(user)
    end

    before do
      create_firewall_policy(rules: [{ type: 'license', denied: [{ name: 'MIT' }] }])
      stub_licences_for([{ name: 'MIT' }])
    end

    def request
      post api(path, personal_access_token: pat), params: params
    end

    # A second project proves the limit is scoped per project, not per caller alone.
    def request_with_second_scope
      post api("/projects/#{other_project.id}/dependency_firewall/evaluate",
        personal_access_token: pat), params: params
    end

    it_behaves_like 'rate limited endpoint', rate_limit_key: :dependency_firewall_evaluation
  end

  context 'when a warn-mode policy matches the package' do
    before do
      create_firewall_policy(rules: [{ type: 'license', denied: [{ name: 'MIT' }] }],
        enforcement_type: 'warn')
      stub_licences_for([{ name: 'MIT' }])
    end

    it 'returns the warned outcome' do
      post api(path, personal_access_token: pat), params: params

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['outcome']).to eq('warned')
    end
  end

  context 'when an evaluated policy matches nothing' do
    before do
      create_firewall_policy(rules: [{ type: 'license', denied: [{ name: 'GPL-3.0' }] }])
      stub_licences_for([{ name: 'MIT' }])
    end

    it 'returns the allowed outcome with no reason' do
      post api(path, personal_access_token: pat), params: params

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['outcome']).to eq('allowed')
      expect(json_response['reason']).to be_nil
    end
  end

  context 'when the firewall is not enforced for the project' do
    before do
      settings = group.namespace_settings || group.create_namespace_settings!
      settings.update!(dependency_firewall_enabled: false)
    end

    it 'returns 422 with the not-enforced code' do
      post api(path, personal_access_token: pat), params: params

      expect(response).to have_gitlab_http_status(:unprocessable_entity)
      expect(json_response['code']).to eq('dependency_firewall_not_enforced')
    end
  end

  # The licence is checked inside the service rather than at the transport layer, and it answers
  # 422 rather than the 404 the feature flag produces: an unlicensed project is a project where the
  # firewall is off, not a project where this endpoint does not exist.
  context 'when the licensed feature is unavailable' do
    before do
      stub_licensed_features(dependency_firewall: false)
      create_firewall_policy(rules: [{ type: 'license', denied: [{ name: 'MIT' }] }])
      stub_licences_for([{ name: 'MIT' }])
    end

    it 'returns 422 without evaluating the package' do
      expect(::Security::DependencyFirewall::EnforcementService).not_to receive(:firewall_check)

      post api(path, personal_access_token: pat), params: params

      expect(response).to have_gitlab_http_status(:unprocessable_entity)
      expect(json_response['code']).to eq('dependency_firewall_not_enforced')
    end
  end

  context 'when no policy is linked to the project' do
    it 'returns the allowed outcome with no reason', :aggregate_failures do
      post api(path, personal_access_token: pat), params: params

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['outcome']).to eq('allowed')
      expect(json_response['reason']).to be_nil
    end
  end

  context 'when the request carries a session id header' do
    let(:session_header) { described_class::SESSION_HEADER }

    before do
      create_firewall_policy(rules: [{ type: 'license', denied: [{ name: 'GPL-3.0' }] }])
      stub_licences_for([{ name: 'MIT' }])
    end

    it 'reaches the enforcement service with the conforming header value' do
      expect(Security::DependencyFirewall::EnforcementService).to receive(:firewall_check)
        .with(hash_including(session_id: 'run-abc-123')).and_call_original

      post api(path, personal_access_token: pat), params: params, headers: { session_header => 'run-abc-123' }
    end

    it 'reaches the enforcement service with nil when the header is absent' do
      expect(Security::DependencyFirewall::EnforcementService).to receive(:firewall_check)
        .with(hash_including(session_id: nil)).and_call_original

      post api(path, personal_access_token: pat), params: params
    end

    it 'returns the same status and outcome for an over-length header as for no header at all' do
      post api(path, personal_access_token: pat), params: params
      status_without_header = response.status
      outcome_without_header = json_response['outcome']

      post api(path, personal_access_token: pat), params: params,
        headers: { session_header => 'a' * 256 }

      expect(response).to have_gitlab_http_status(status_without_header)
      expect(json_response['outcome']).to eq(outcome_without_header)
    end

    it 'returns a verdict rather than a 500 for an invalid-UTF-8 header' do
      post api(path, personal_access_token: pat), params: params,
        headers: { session_header => "run-\xFF" }

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['outcome']).to eq('allowed')
    end

    # The upload event declares session_id in this MR, and this is the proof the declaration lands
    # together with a producer that can reach it: header in, upload operation in, session id on
    # the upload analytics event out.
    it 'records the session id on the analytics event for an upload evaluation' do
      expect do
        post api(path, personal_access_token: pat), params: params.merge(operation: 'upload'),
          headers: { session_header => 'run-abc-123' }
      end.to trigger_internal_events(
        'collect_dependency_firewall_metrics_on_package_upload_to_package_registry'
      ).with(user: user, project: project, namespace: project.namespace,
        category: 'Security::DependencyFirewall::CreateEventService',
        additional_properties: {
          label: 'allowed',
          property: '0',
          value: an_instance_of(Integer),
          purl: 'pkg:npm/lodash@4.17.21',
          session_id: 'run-abc-123'
        })
    end

    # The one unmocked proof of the whole chain: header in, blocked verdict out, session id on
    # the persisted audit event a compliance reviewer would read.
    it 'records the session id on the audit event for a blocked verdict', :aggregate_failures do
      stub_licensed_features(dependency_firewall: true, audit_events: true)
      stub_licences_for([{ name: 'GPL-3.0' }])

      post api(path, personal_access_token: pat), params: params,
        headers: { session_header => 'run-abc-123' }

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['outcome']).to eq('blocked')
      expect(AuditEvents::ProjectAuditEvent.last.details[:session_id]).to eq('run-abc-123')
    end
  end

  context 'when a package-metadata lookup fails mid-evaluation' do
    before do
      create_firewall_policy(rules: [{ type: 'license', denied: [{ name: 'MIT' }] }])
      allow_next_instance_of(Security::DependencyFirewall::FetchPackageLicensesService) do |svc|
        allow(svc).to receive(:execute).and_raise(ActiveRecord::QueryCanceled, 'statement timeout')
      end
    end

    it 'returns 503 with the evaluation-failed code' do
      post api(path, personal_access_token: pat), params: params

      expect(response).to have_gitlab_http_status(:service_unavailable)
      expect(json_response['code']).to eq('dependency_firewall_evaluation_failed')
    end
  end
end
