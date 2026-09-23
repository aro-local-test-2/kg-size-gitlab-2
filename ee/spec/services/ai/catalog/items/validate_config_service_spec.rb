# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::Items::ValidateConfigService, feature_category: :workflow_catalog do
  let_it_be(:project) { create(:project, :in_group) }
  let_it_be(:current_user) { create(:user, maintainer_of: project) }

  let(:definition_hash) do
    {
      'version' => 'v1',
      'environment' => 'ambient',
      'yaml_definition' => "version: v1\nenvironment: ambient\n"
    }
  end

  subject(:service) { described_class.new(project: project, current_user: current_user) }

  describe '#execute' do
    context 'when the definition is present' do
      let(:dws_client) { instance_double(::Ai::DuoWorkflow::DuoWorkflowService::Client) }

      before do
        allow(::Ai::DuoWorkflow::DuoWorkflowService::Client).to receive(:new).and_return(dws_client)
      end

      it 'validates the config with the yaml_definition stripped out' do
        expect(dws_client).to receive(:validate_flow_config)
          .with(flow_config: { 'version' => 'v1', 'environment' => 'ambient' })
          .and_return(ServiceResponse.success)

        expect(service.execute(definition_hash)).to be_success
      end

      it 'builds the DWS client with the project as the container' do
        allow(dws_client).to receive(:validate_flow_config).and_return(ServiceResponse.success)

        expect(::Ai::DuoWorkflow::DuoWorkflowService::Client).to receive(:new)
          .with(hash_including(current_user: current_user, container: project))
          .and_return(dws_client)

        service.execute(definition_hash)
      end

      context 'when DWS returns validation errors' do
        it 'passes through the error and its reason' do
          allow(dws_client).to receive(:validate_flow_config)
            .and_return(ServiceResponse.error(
              message: ['Component missing input variables: goal'],
              reason: ::Ai::DuoWorkflow::DuoWorkflowService::Client::ERROR_REASON_INVALID_FLOW_CONFIG
            ))

          result = service.execute(definition_hash)

          expect(result).to be_error
          expect(result.message).to eq(['Component missing input variables: goal'])
          expect(result.reason).to eq(::Ai::DuoWorkflow::DuoWorkflowService::Client::ERROR_REASON_INVALID_FLOW_CONFIG)
        end
      end

      context 'when DWS is unavailable' do
        it 'passes through the error and its reason' do
          allow(dws_client).to receive(:validate_flow_config)
            .and_return(
              ServiceResponse.error(
                message: 'Unable to validate flow configuration. Duo Workflow Service is currently unavailable.',
                reason: ::Ai::DuoWorkflow::DuoWorkflowService::Client::ERROR_REASON_SERVICE_UNAVAILABLE
              )
            )

          result = service.execute(definition_hash)

          expect(result).to be_error
          expect(result.message).to eq(
            'Unable to validate flow configuration. Duo Workflow Service is currently unavailable.'
          )
          expect(result.reason).to eq(::Ai::DuoWorkflow::DuoWorkflowService::Client::ERROR_REASON_SERVICE_UNAVAILABLE)
        end
      end
    end
  end
end
