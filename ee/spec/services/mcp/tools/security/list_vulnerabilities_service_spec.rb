# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Security::ListVulnerabilitiesService, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }

  let(:service) { described_class.new(name: 'list_vulnerabilities') }

  before do
    service.set_cred(current_user: user)
  end

  describe '.available_versions' do
    subject { described_class.available_versions }

    it { is_expected.to contain_exactly('0.1.0') }
  end

  describe '#annotations' do
    subject { service.annotations }

    it { is_expected.to eq({ readOnlyHint: true }) }
  end

  describe 'class configuration' do
    it 'is registered as an EE GraphQL tool' do
      expect(::EE::Mcp::Tools::Manager::EE_GRAPHQL_TOOLS).to include('list_vulnerabilities' => described_class)
    end

    it 'includes project_full_path in the description' do
      description = described_class.version_metadata('0.1.0')[:description]

      expect(description).to include('project_full_path')
    end
  end

  describe 'input schema' do
    it 'locks the full input schema for version 0.1.0' do
      expect(described_class.version_metadata('0.1.0')[:input_schema]).to eq({
        type: 'object',
        required: ['project_full_path'],
        properties: {
          project_full_path: {
            type: 'string',
            description: 'Full path of the project (e.g., "namespace/project" or "group/subgroup/project").'
          },
          severity: {
            type: 'array',
            description: 'Filter by severity level. Omit to include vulnerabilities of any severity.',
            items: {
              type: 'string',
              enum: %w[CRITICAL HIGH MEDIUM LOW INFO UNKNOWN]
            }
          },
          report_type: {
            type: 'array',
            description: 'Filter by security report type. Omit to include all report types.',
            items: {
              type: 'string',
              enum: %w[SAST DEPENDENCY_SCANNING CONTAINER_SCANNING DAST SECRET_DETECTION
                COVERAGE_FUZZING API_FUZZING CLUSTER_IMAGE_SCANNING CONTAINER_SCANNING_FOR_REGISTRY
                SARIF GENERIC]
            }
          },
          state: {
            type: 'array',
            description: 'Filter by vulnerability state. Omit to include vulnerabilities in any state.',
            items: {
              type: 'string',
              enum: %w[CONFIRMED DETECTED DISMISSED RESOLVED]
            }
          },
          first: {
            type: 'integer',
            description: 'Number of vulnerabilities to return after the cursor (forward pagination). ' \
              'Max 100.',
            minimum: 1,
            maximum: 100
          },
          after: {
            type: 'string',
            description: 'Cursor for forward pagination of vulnerabilities. ' \
              'Use pageInfo.endCursor from a previous response.'
          }
        }
      })
    end
  end

  describe '#execute' do
    let(:request) { instance_double(ActionDispatch::Request) }

    context 'when current_user is not set' do
      before do
        service.set_cred(current_user: nil)
      end

      it 'returns an error response' do
        result = service.execute(request: request, params: { arguments: {} })

        expect(result).to include(isError: true)
        expect(result[:content].first[:text]).to include('current_user is not set')
      end
    end

    context 'when project does not exist' do
      it 'returns a not found error' do
        result = service.execute(
          request: request,
          params: { arguments: { project_full_path: 'nonexistent/project' } }
        )

        expect(result).to include(isError: true)
        expect(result[:content].first[:text]).to include('Project not found')
      end
    end

    context 'when project exists and user has access' do
      let_it_be(:vulnerability) { create(:vulnerability, :detected, :with_findings, project: project, severity: :high) }

      before_all do
        project.add_developer(user)
      end

      before do
        stub_licensed_features(security_dashboard: true)
      end

      it 'returns a list of vulnerabilities', :aggregate_failures do
        result = service.execute(
          request: request,
          params: { arguments: { project_full_path: project.full_path } }
        )

        expect(result[:isError]).to be(false)
        nodes = result[:structuredContent]['nodes']
        expect(nodes).not_to be_empty
        expect(nodes.first).to include('title', 'severity', 'state', 'reportType')
      end

      context 'when filtering by severity' do
        let_it_be(:critical_vulnerability) do
          create(:vulnerability, :detected, :critical_severity, :with_findings, project: project)
        end

        it 'returns only vulnerabilities matching the severity filter' do
          result = service.execute(
            request: request,
            params: { arguments: { project_full_path: project.full_path, severity: ['CRITICAL'] } }
          )

          expect(result[:isError]).to be(false)
          nodes = result[:structuredContent]['nodes']
          expect(nodes.map { |v| v['severity'] }).to all(eq('CRITICAL'))
        end
      end

      context 'when filtering by report_type' do
        it 'returns only vulnerabilities matching the report type filter' do
          result = service.execute(
            request: request,
            params: { arguments: { project_full_path: project.full_path, report_type: ['SAST'] } }
          )

          expect(result[:isError]).to be(false)
          nodes = result[:structuredContent]['nodes']
          expect(nodes.map { |v| v['reportType'] }).to all(eq('SAST'))
        end
      end

      context 'when filtering by a single state' do
        let_it_be(:confirmed_vulnerability) do
          create(:vulnerability, :confirmed, :with_findings, project: project)
        end

        it 'returns only vulnerabilities matching the state filter' do
          result = service.execute(
            request: request,
            params: { arguments: { project_full_path: project.full_path, state: ['CONFIRMED'] } }
          )

          expect(result[:isError]).to be(false)
          nodes = result[:structuredContent]['nodes']
          expect(nodes).not_to be_empty
          expect(nodes.map { |v| v['state'] }).to all(eq('CONFIRMED'))
        end
      end

      context 'when filtering by multiple states' do
        let_it_be(:confirmed_vulnerability) do
          create(:vulnerability, :confirmed, :with_findings, project: project)
        end

        it 'returns only vulnerabilities matching any of the state filters' do
          result = service.execute(
            request: request,
            params: { arguments: { project_full_path: project.full_path, state: %w[CONFIRMED DETECTED] } }
          )

          expect(result[:isError]).to be(false)
          nodes = result[:structuredContent]['nodes']
          expect(nodes).not_to be_empty
          states = nodes.map { |v| v['state'] }
          expect(states).to all(be_in(%w[CONFIRMED DETECTED]))
          expect(states).to include('CONFIRMED', 'DETECTED')
        end
      end

      context 'when using pagination' do
        it 'respects the first parameter' do
          result = service.execute(
            request: request,
            params: { arguments: { project_full_path: project.full_path, first: 1 } }
          )

          expect(result[:isError]).to be(false)
          expect(result[:structuredContent]['nodes'].length).to be <= 1
        end
      end
    end

    context 'when user does not have access to the project' do
      let_it_be(:private_project) { create(:project, :private) }

      it 'returns a not found error' do
        result = service.execute(
          request: request,
          params: { arguments: { project_full_path: private_project.full_path } }
        )

        expect(result).to include(isError: true)
        expect(result[:content].first[:text]).to include('Project not found')
      end
    end

    context 'when user has project access but security_dashboard feature is not available' do
      let_it_be(:vulnerability) { create(:vulnerability, :detected, :with_findings, project: project, severity: :high) }

      before_all do
        project.add_developer(user)
      end

      before do
        stub_licensed_features(security_dashboard: false)
      end

      it 'returns an empty list of vulnerabilities' do
        result = service.execute(
          request: request,
          params: { arguments: { project_full_path: project.full_path } }
        )

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent]['nodes']).to be_empty
      end
    end
  end
end
