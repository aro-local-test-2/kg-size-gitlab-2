# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CloudConnector::StatusChecks::Probes::DuoAgentPlatformProbe, feature_category: :duo_setting do
  let(:user) { build(:user) }
  let(:cloud_host) { 'duo-workflow-svc.runway.gitlab.net:443' }
  let(:self_hosted_host) { 'localhost:50052' }
  let(:self_hosted) { false }
  let(:secure) { true }
  let(:probe) { described_class.new(user, deployment: deployment) }
  let(:duo_workflow_client) { instance_double(Ai::DuoWorkflow::DuoWorkflowService::Client) }
  let(:feature_setting) { CloudConnector::StatusChecks::Probes::DuoAgentPlatformProbe::MockFeatureSetting.new(self_hosted) }

  before do
    allow(Ai::DuoWorkflow::DuoWorkflowService::Client).to receive(:new).and_return(duo_workflow_client)
    allow(Gitlab::DuoWorkflow::Client).to receive(:cloud_connected_url).with(user: user).and_return(cloud_host)
    allow(Gitlab::DuoWorkflow::Client).to receive_messages(self_hosted_url: self_hosted_host, secure?: secure)
  end

  shared_examples 'a successful probe' do
    before do
      allow(duo_workflow_client).to receive(:list_tools).and_return(status: :success)
    end

    it 'returns a successful result with the expected message' do
      result = probe.execute

      expect(result).to be_a(CloudConnector::StatusChecks::Probes::ProbeResult)
      expect(result.success?).to be(true)
      expect(result.message).to eq(expected_success_message)
    end

    it 'calls list_tools only once' do
      expect(duo_workflow_client).to receive(:list_tools).once.and_return(status: :success)

      probe.execute
    end

    it 'invokes DuoWorkflowService::Client with the resolved host, secure flag, and feature setting' do
      probe.execute

      expect(Ai::DuoWorkflow::DuoWorkflowService::Client).to have_received(:new).with(
        duo_workflow_service_url: host,
        current_user: user,
        secure: secure,
        feature_setting: feature_setting
      )
      expect(duo_workflow_client).to have_received(:list_tools)
    end

    it 'resolves the secure flag for the deployment' do
      probe.execute

      expect(Gitlab::DuoWorkflow::Client).to have_received(:secure?).with(
        feature_setting: have_attributes(self_hosted?: self_hosted)
      )
    end
  end

  shared_examples 'a failed probe' do
    before do
      allow(duo_workflow_client).to receive(:list_tools).and_return(status: :error, message: 'Connection failed')
    end

    it 'returns a failed result with the not-reachable message' do
      result = probe.execute

      expect(result).to be_a(CloudConnector::StatusChecks::Probes::ProbeResult)
      expect(result.success?).to be(false)
      expect(result.message).to eq(expected_failure_message)
    end

    it 'calls list_tools only once' do
      expect(duo_workflow_client).to receive(:list_tools).once.and_return(
        status: :error, message: 'Connection failed'
      )

      probe.execute
    end
  end

  describe '#execute' do
    context 'when deployment is cloud-connected' do
      let(:deployment) { :cloud_connected }
      let(:host) { cloud_host }
      let(:expected_success_message) do
        "The cloud-connected GitLab Duo Agent Platform service at #{host} is operational."
      end

      let(:expected_failure_message) do
        "The cloud-connected GitLab Duo Agent Platform service at #{host} is not reachable."
      end

      it_behaves_like 'a successful probe'
      it_behaves_like 'a failed probe'

      it 'resolves the host from the cloud-connected URL' do
        allow(duo_workflow_client).to receive(:list_tools).and_return(status: :success)

        probe.execute

        expect(Gitlab::DuoWorkflow::Client).to have_received(:cloud_connected_url).with(user: user)
      end
    end

    context 'when deployment is self-hosted' do
      let(:deployment) { :self_hosted }
      let(:host) { self_hosted_host }
      let(:self_hosted) { true }
      let(:expected_success_message) do
        "The self-hosted GitLab Duo Agent Platform service at #{host} is operational."
      end

      let(:expected_failure_message) do
        "The self-hosted GitLab Duo Agent Platform service at #{host} is not reachable."
      end

      it_behaves_like 'a successful probe'
      it_behaves_like 'a failed probe'

      it 'resolves the host from the self-hosted URL' do
        allow(duo_workflow_client).to receive(:list_tools).and_return(status: :success)

        probe.execute

        expect(Gitlab::DuoWorkflow::Client).to have_received(:self_hosted_url)
      end

      context 'when list_tools fails with a TLS mismatch error and secure is enabled' do
        let(:secure) { true }
        let(:error_response) do
          {
            status: :error,
            message: 'Ssl handshake failed (TSI_PROTOCOL_FAILURE): ' \
              'SSL_ERROR_SSL: error:100000f7:' \
              'SSL routines:OPENSSL_internal:WRONG_VERSION_NUMBER'
          }
        end

        before do
          allow(duo_workflow_client).to receive(:list_tools).and_return(error_response)
        end

        it 'appends TLS guidance to the failure message' do
          result = probe.execute

          expect(result.success?).to be(false)
          expect(result.message).to include("The self-hosted GitLab Duo Agent Platform service at #{host} is not " \
            "reachable.")
          expect(result.message).to include('It fails with a TLS mismatch error.')
          expect(result.message).to include('turn off TLS connection to the GitLab Duo Agent Platform service')
        end
      end

      context 'when list_tools fails with a TLS mismatch error but secure is disabled' do
        let(:secure) { false }

        before do
          allow(duo_workflow_client).to receive(:list_tools).and_return(
            status: :error,
            message: 'tls handshake error'
          )
        end

        it 'returns the plain failure message without TLS guidance' do
          result = probe.execute

          expect(result.success?).to be(false)
          expect(result.message).to eq("The self-hosted GitLab Duo Agent Platform service at #{host} is not reachable.")
        end
      end
    end
  end
end
