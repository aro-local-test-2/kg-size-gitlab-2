# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::CodeSuggestions::SelfHostedBillingTracker, feature_category: :code_suggestions do
  let_it_be(:current_user) { create(:user) }
  let(:feature_setting) { instance_double(Ai::FeatureSetting, self_hosted?: true, feature: 'code_suggestions') }

  subject(:tracker) do
    described_class.new(current_user: current_user, feature_setting: feature_setting)
  end

  describe '#track' do
    context 'when self-hosted DAP billing is enabled' do
      before do
        allow(Ai::SelfHostedDapBilling).to receive(:should_bill?).with(feature_setting).and_return(true)
        allow_next_instance_of(Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
          allow(client).to receive(:track_self_hosted_client_event)
            .and_return(ServiceResponse.success(message: "Billing event tracked"))
        end
      end

      it 'returns a success response' do
        expect(tracker.track).to be_success
      end

      it 'calls the gRPC client with correct arguments' do
        expect_next_instance_of(Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
          expect(client).to receive(:track_self_hosted_client_event).with(
            request_id: anything,
            feature_qualified_name: described_class::FEATURE_QUALIFIED_NAME,
            feature_ai_catalog_item: false
          ).and_return(ServiceResponse.success(message: "Billing event tracked"))
        end

        tracker.track
      end

      it 'builds the client with the cloud-connected URL, secure flag, and feature setting' do
        expect(Ai::DuoWorkflow::DuoWorkflowService::Client).to receive(:new).with(
          duo_workflow_service_url: Gitlab::DuoWorkflow::Client.cloud_connected_url(user: current_user),
          current_user: current_user,
          secure: Gitlab::DuoWorkflow::Client.secure?,
          feature_setting: feature_setting
        ).and_call_original

        tracker.track
      end

      context 'when the gRPC call fails' do
        before do
          allow_next_instance_of(Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
            allow(client).to receive(:track_self_hosted_client_event)
              .and_return(ServiceResponse.error(message: "connection refused"))
          end
        end

        it 'returns an error response' do
          expect(tracker.track).to be_error
        end

        it 'surfaces the error message' do
          expect(tracker.track.message).to eq("connection refused")
        end
      end

      context 'when an unexpected exception is raised' do
        before do
          allow_next_instance_of(Ai::DuoWorkflow::DuoWorkflowService::Client) do |client|
            allow(client).to receive(:track_self_hosted_client_event).and_raise(RuntimeError, "unexpected")
          end
        end

        it 'tracks the exception and returns an error response' do
          expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
            instance_of(RuntimeError),
            hash_including(feature: feature_setting.feature)
          )

          expect(tracker.track).to be_error
        end
      end
    end

    context 'when self-hosted DAP billing is disabled' do
      before do
        allow(Ai::SelfHostedDapBilling).to receive(:should_bill?).with(feature_setting).and_return(false)
      end

      it 'returns a success response without calling the gRPC client' do
        expect(Ai::DuoWorkflow::DuoWorkflowService::Client).not_to receive(:new)

        expect(tracker.track).to be_success
      end
    end
  end
end
