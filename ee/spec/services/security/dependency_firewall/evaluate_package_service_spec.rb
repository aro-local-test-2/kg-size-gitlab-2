# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::DependencyFirewall::EvaluatePackageService, feature_category: :dependency_firewall do
  let_it_be_with_reload(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:current_user) { create(:user) }

  let(:ecosystem) { 'npm' }
  let(:name) { 'lodash' }
  let(:version) { '4.17.21' }
  let(:operation) { 'download' }
  let(:session_id) { nil }

  subject(:response) do
    described_class.new(
      project: project,
      current_user: current_user,
      ecosystem: ecosystem,
      name: name,
      version: version,
      operation: operation,
      session_id: session_id
    ).execute
  end

  # Mirrors the helper in enforcement_service_spec.rb: a Security::Policy of the
  # dependency_firewall type, linked to the project, plus its persisted rule rows.
  # `live_rules: false` soft-deletes the rule rows by giving them a negative rule_index, which is
  # how a policy ends up with nothing to evaluate: the content schema requires at least one rule.
  def create_firewall_policy(rules:, name: 'df-policy', enforcement_type: 'enforced', live_rules: true)
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
        rule_index: live_rules ? index : -1 - index,
        type: Security::DependencyFirewallPolicyRule.types[rule_hash[:type]],
        content: rule_hash.except(:type))
    end

    policy
  end

  describe '#execute' do
    # Validation runs before the availability pre-check, so bad input is reported as bad input
    # rather than being masked by the project's firewall state.
    context 'when the coordinate is invalid' do
      using RSpec::Parameterized::TableSyntax

      where(:case_name, :ecosystem, :name, :version) do
        'blank name'            | 'npm'      | ''       | '4.17.21'
        'blank version'         | 'npm'      | 'lodash' | ''
        'unsupported ecosystem' | 'not-real' | 'anyhow' | '1.0.0'
      end

      with_them do
        it "returns an error with the invalid_coordinate reason for #{params[:case_name]}",
          :aggregate_failures do
          expect(response).to be_error
          expect(response.reason).to eq(:invalid_coordinate)
        end
      end
    end

    context 'when the firewall is not enforced for the project' do
      it 'returns an error with the not_enforced reason', :aggregate_failures do
        expect(response).to be_error
        expect(response.reason).to eq(:not_enforced)
      end
    end

    context 'when the firewall is enforced for the project' do
      before do
        stub_licensed_features(dependency_firewall: true)
        stub_saas_features(dependency_firewall: true)
        settings = group.namespace_settings || group.create_namespace_settings!
        settings.update!(dependency_firewall_enabled: true)
      end

      # These ecosystems have no shared normalizer transform, so EnforcementService must
      # receive the ecosystem and name strings verbatim. golang is covered under
      # 'when a coordinate needs normalizing' below because its names are downcased.
      context 'with a pass-through ecosystem' do
        using RSpec::Parameterized::TableSyntax

        where(:ecosystem, :name) do
          'composer' | 'monolog/monolog'
          'conan'    | 'openssl'
          'nuget'    | 'Newtonsoft.Json'
          'cargo'    | 'serde'
          'swift'    | 'github.com/vapor/vapor'
          'pub'      | 'http'
        end

        with_them do
          it 'forwards the ecosystem to EnforcementService.firewall_check as pkg_type' do
            expect(Security::DependencyFirewall::EnforcementService)
              .to receive(:firewall_check)
              .with(hash_including(pkg_type: ecosystem, name: name, version: version))
              .and_return(ServiceResponse.success(payload: {
                status: Security::DependencyFirewall::EnforcementService::SUCCESS_ALLOWED
              }))

            expect(response).to be_success
            expect(response.payload[:outcome]).to eq(:allowed)
          end
        end
      end

      context 'when a policy denies the package' do
        before do
          create_firewall_policy(rules: [{ type: 'license', denied: [{ name: 'MIT' }] }])
          allow_next_instance_of(Security::DependencyFirewall::FetchPackageLicensesService) do |svc|
            allow(svc).to receive(:execute).and_return([{ name: 'MIT' }])
          end
        end

        it 'returns the blocked outcome with a reason naming the policy', :aggregate_failures do
          expect(response).to be_success
          expect(response.payload[:outcome]).to eq(:blocked)
          expect(response.payload[:reason]).to include('df-policy')
        end
      end

      context 'when a warn-mode policy matches the package' do
        before do
          create_firewall_policy(rules: [{ type: 'license', denied: [{ name: 'MIT' }] }],
            enforcement_type: 'warn')
          allow_next_instance_of(Security::DependencyFirewall::FetchPackageLicensesService) do |svc|
            allow(svc).to receive(:execute).and_return([{ name: 'MIT' }])
          end
        end

        it 'returns the warned outcome with a reason naming the policy', :aggregate_failures do
          expect(response).to be_success
          expect(response.payload[:outcome]).to eq(:warned)
          expect(response.payload[:reason]).to include('df-policy')
        end
      end

      context 'when an evaluated policy matches nothing' do
        before do
          create_firewall_policy(rules: [{ type: 'license', denied: [{ name: 'GPL-3.0' }] }])
          allow_next_instance_of(Security::DependencyFirewall::FetchPackageLicensesService) do |svc|
            allow(svc).to receive(:execute).and_return([{ name: 'MIT' }])
          end
        end

        it 'returns the allowed outcome with no reason', :aggregate_failures do
          expect(response).to be_success
          expect(response.payload[:outcome]).to eq(:allowed)
          expect(response.payload[:reason]).to be_nil
        end
      end

      # Each exception purl matches only if the supplied name was rewritten to the form the package
      # metadata database stores, so an allowed outcome is what proves normalization ran.
      context 'when a coordinate needs normalizing' do
        using RSpec::Parameterized::TableSyntax

        where(:case_name, :ecosystem, :name, :version, :exception_purl) do
          'a Maven colon form'                     | 'maven'  | 'com.example:trivial-lib'  | '1.0.0'  |
            'pkg:maven/com.example/trivial-lib@1.0.0'
          'a PyPI mixed case with underscores'     | 'pypi'   | 'Flask_Login'              | '0.6.3'  |
            'pkg:pypi/flask-login@0.6.3'
          'a golang mixed case module path'        | 'golang' | 'GitHub.com/Gin-Gonic/Gin' | 'v1.9.1' |
            'pkg:golang/github.com/gin-gonic/gin@v1.9.1'
        end

        with_them do
          before do
            create_firewall_policy(rules: [{
              type: 'license',
              denied: [{ name: 'MIT' }],
              exceptions: [{ purl: exception_purl }]
            }])
            allow_next_instance_of(Security::DependencyFirewall::FetchPackageLicensesService) do |svc|
              allow(svc).to receive(:execute).and_return([{ name: 'MIT' }])
            end
          end

          it "normalizes the name before evaluating #{params[:case_name]}" do
            expect(response.payload[:outcome]).to eq(:allowed)
          end
        end
      end

      context 'when a package-metadata lookup fails mid-evaluation' do
        before do
          create_firewall_policy(rules: [{ type: 'license', denied: [{ name: 'MIT' }] }])
          allow_next_instance_of(Security::DependencyFirewall::FetchPackageLicensesService) do |svc|
            allow(svc).to receive(:execute).and_raise(ActiveRecord::QueryCanceled, 'statement timeout')
          end
        end

        it 'returns an error with the evaluation_failed reason', :aggregate_failures do
          expect(response).to be_error
          expect(response.reason).to eq(:evaluation_failed)
        end

        it 'tracks the exception' do
          expect(::Gitlab::ErrorTracking).to receive(:track_exception)
            .with(instance_of(ActiveRecord::QueryCanceled), hash_including(project_id: project.id))

          response
        end
      end

      # Recording follows evaluation. The audit licence is enabled in both contexts below so the
      # negative assertion proves no rule ran, rather than passing because audit events were never
      # licensed in the first place.
      context 'when an evaluation is performed' do
        before do
          stub_licensed_features(dependency_firewall: true, audit_events: true)
          create_firewall_policy(rules: [{ type: 'license', denied: [{ name: 'MIT' }] }])
          allow_next_instance_of(Security::DependencyFirewall::FetchPackageLicensesService) do |svc|
            allow(svc).to receive(:execute).and_return([{ name: 'MIT' }])
          end
        end

        it 'writes an audit event' do
          expect { response }.to change { AuditEvents::ProjectAuditEvent.count }.by(1)
        end

        it 'logs the evaluation with its duration' do
          allow(::Gitlab::AppJsonLogger).to receive(:info)

          response

          expect(::Gitlab::AppJsonLogger).to have_received(:info).with(
            hash_including(
              'class_name' => described_class.name,
              'event' => 'dependency_firewall_evaluation',
              'gl_project_id' => project.id,
              'ecosystem' => 'npm',
              'operation' => 'download',
              'outcome' => 'blocked',
              'evaluation_duration_s' => kind_of(Float)
            )
          )
        end
      end

      context 'when a session id is supplied' do
        before do
          create_firewall_policy(rules: [{ type: 'license', denied: [{ name: 'GPL-3.0' }] }])
          allow_next_instance_of(Security::DependencyFirewall::FetchPackageLicensesService) do |svc|
            allow(svc).to receive(:execute).and_return([{ name: 'MIT' }])
          end
        end

        context 'when it conforms to the expected format' do
          let(:session_id) { 'run-abc-123' }

          it 'forwards it unchanged to the enforcement service' do
            expect(Security::DependencyFirewall::EnforcementService).to receive(:firewall_check)
              .with(hash_including(session_id: 'run-abc-123')).and_call_original

            response
          end
        end

        context 'when it does not conform to the expected format' do
          let(:session_id) { "invalid\xFF" }

          it 'forwards it unchanged for the enforcement service to sanitize' do
            expect(Security::DependencyFirewall::EnforcementService).to receive(:firewall_check)
              .with(hash_including(session_id: session_id)).and_call_original

            response
          end
        end

        context 'when absent' do
          let(:session_id) { nil }

          it 'forwards nil to the enforcement service' do
            expect(Security::DependencyFirewall::EnforcementService).to receive(:firewall_check)
              .with(hash_including(session_id: nil)).and_call_original

            response
          end
        end
      end

      # The audit operation label is what proves the string reached EnforcementService as
      # PACKAGE_UPLOAD rather than the download default.
      context 'when the operation is an upload' do
        let(:operation) { 'upload' }

        before do
          stub_licensed_features(dependency_firewall: true, audit_events: true)
          create_firewall_policy(rules: [{ type: 'license', denied: [{ name: 'MIT' }] }])
          allow_next_instance_of(Security::DependencyFirewall::FetchPackageLicensesService) do |svc|
            allow(svc).to receive(:execute).and_return([{ name: 'MIT' }])
          end
        end

        it 'evaluates and records the upload operation on the audit event', :aggregate_failures do
          expect { response }.to change { AuditEvents::ProjectAuditEvent.count }.by(1)

          expect(response.payload[:outcome]).to eq(:blocked)
          expect(AuditEvents::ProjectAuditEvent.last.details[:operation]).to eq('package upload')
        end

        it 'logs the operation' do
          allow(::Gitlab::AppJsonLogger).to receive(:info)

          response

          expect(::Gitlab::AppJsonLogger).to have_received(:info).with(
            hash_including('event' => 'dependency_firewall_evaluation', 'operation' => 'upload')
          )
        end
      end

      # The transport layer validates the operation against OPERATIONS.keys, so an unknown value
      # here is our bug, and it must surface as a 500 rather than an error the client acts on.
      context 'when the operation is not a supported value' do
        let(:operation) { 'push' }

        it 'raises rather than evaluating' do
          expect { response }.to raise_error(KeyError)
        end
      end

      # No policy, or a policy whose every rule is soft-deleted, means no rule ran. The verdict is
      # still allowed, but it is not a firewall decision, so nothing is audited.
      context 'when the project has nothing to evaluate against' do
        before do
          stub_licensed_features(dependency_firewall: true, audit_events: true)
        end

        shared_examples 'an allow that is not a firewall decision' do
          it 'allows the package without writing an audit event', :aggregate_failures do
            expect { response }.not_to change { AuditEvents::ProjectAuditEvent.count }

            expect(response).to be_success
            expect(response.payload[:outcome]).to eq(:allowed)
            expect(response.payload[:reason]).to be_nil
          end
        end

        context 'when no Dependency Firewall policy is linked to the project' do
          it_behaves_like 'an allow that is not a firewall decision'
        end

        context 'when the linked policy carries no live rule' do
          before do
            create_firewall_policy(rules: [{ type: 'license', denied: [{ name: 'MIT' }] }], live_rules: false)
          end

          it_behaves_like 'an allow that is not a firewall decision'
        end
      end

      # The rescue is deliberately narrow: an unexpected error is a defect and must surface as a
      # 500 and an alert, not as a transient-looking failure the client would fail closed on.
      context 'when the evaluation raises an unexpected error' do
        before do
          create_firewall_policy(rules: [{ type: 'license', denied: [{ name: 'MIT' }] }])
          allow_next_instance_of(Security::DependencyFirewall::FetchPackageLicensesService) do |svc|
            allow(svc).to receive(:execute).and_raise(NoMethodError, 'undefined method')
          end
        end

        it 'propagates the error rather than reporting evaluation_failed' do
          expect { response }.to raise_error(NoMethodError)
        end
      end
    end
  end
end
