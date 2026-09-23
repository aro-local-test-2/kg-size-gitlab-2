# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Cd::Rollouts, feature_category: :continuous_delivery do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:application) { create(:cd_application, organization: organization) }
  let_it_be(:version_set) { create(:cd_version_set, application: application) }
  let_it_be(:environment) { create(:cd_environment, organization: organization, name: 'production') }
  let_it_be(:cd_service) { create(:cd_service, application: application, name: 'web') }
  let_it_be(:driver_binding) { create(:cd_environment_driver_binding, environment: environment) }

  let(:jwt_secret) { SecureRandom.random_bytes(Gitlab::JwtAuthenticatable::SECRET_LENGTH) }

  let(:rollout) do
    create(:cd_rollout, application: application, version_set: version_set, state: :in_progress,
      workflow_ref: 'wk:1/abc')
  end

  let(:idempotency_key) { SecureRandom.uuid }
  let(:headers) do
    { 'Authorization' => "Bearer #{Cd::Rollouts::CallbackToken.encode(rollout)}", 'Idempotency-Key' => idempotency_key }
  end

  before do
    allow(Gitlab::Kas).to receive(:secret).and_return(jwt_secret)
  end

  describe 'POST /rollouts/:id', :sidekiq_inline do
    subject(:request) { post api("/rollouts/#{rollout.id}"), params: params, headers: headers }

    let(:params) do
      { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.step_started',
        data: { position: [1], step_type: 'com.gitlab.cd.steps.wait' } }
    end

    context 'when no callback token is given' do
      let(:headers) { {} }

      it 'returns unauthorized' do
        request

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'when the callback token was issued for a different rollout' do
      let(:other_rollout) do
        create(:cd_rollout, application: application, version_set: version_set, state: :cancelled)
      end

      let(:headers) { { 'Authorization' => "Bearer #{Cd::Rollouts::CallbackToken.encode(other_rollout)}" } }

      it 'returns unauthorized' do
        request

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'when the callback token is malformed' do
      let(:headers) { { 'Authorization' => 'Bearer not-a-real-jwt' } }

      it 'returns unauthorized' do
        request

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'when the callback token has expired' do
      let(:headers) do
        travel_to(Cd::Rollouts::CallbackToken::EXPIRE_IN.ago - 1.minute) do
          { 'Authorization' => "Bearer #{Cd::Rollouts::CallbackToken.encode(rollout)}" }
        end
      end

      it 'returns unauthorized' do
        request

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'when the rollout does not exist' do
      subject(:request) { post api("/rollouts/#{non_existing_record_id}"), params: params, headers: headers }

      it 'returns unauthorized, the same as an existing rollout with a non-matching token' do
        request

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'when the event topic is not recognised' do
      let(:params) do
        { topic: 'com.gitlab.cd.something_unknown', type: 'com.gitlab.cd.step_started', data: { position: [0] } }
      end

      it 'returns bad_request' do
        request

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    context 'when an event other than rollout_succeeded omits its position' do
      let(:params) do
        { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.step_started',
          data: { step_type: 'com.gitlab.cd.steps.wait' } }
      end

      it 'returns bad_request' do
        request

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    context 'when the event type is not recognised' do
      let(:params) do
        { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.something_unknown', data: { position: [0] } }
      end

      it 'returns accepted' do
        request

        expect(response).to have_gitlab_http_status(:accepted)
      end
    end

    it 'enqueues the event for async processing instead of processing it on the request thread' do
      expect(Cd::Rollouts::ProcessWorkflowEventWorker).to receive(:perform_async)
        .with(an_instance_of(Integer), a_hash_including('type' => 'com.gitlab.cd.step_started'))
        .and_call_original

      request

      expect(response).to have_gitlab_http_status(:accepted)
    end

    context 'when the Idempotency-Key header is missing' do
      let(:headers) { { 'Authorization' => "Bearer #{Cd::Rollouts::CallbackToken.encode(rollout)}" } }

      it 'returns bad_request' do
        request

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end

    it 'claims the event by (rollout, Idempotency-Key) before enqueuing it' do
      expect { request }.to change { rollout.incoming_events.count }.by(1)

      expect(rollout.incoming_events.last.idempotency_key).to eq(idempotency_key)
    end

    context 'when the same Idempotency-Key is redelivered' do
      it 'claims the event once and does not process it again' do
        request

        expect { post api("/rollouts/#{rollout.id}"), params: params, headers: headers }
          .not_to change { rollout.incoming_events.count }

        expect(response).to have_gitlab_http_status(:accepted)
      end
    end

    context 'with a step_started event outside any stage' do
      it 'acknowledges the event and returns accepted without opening an approval gate', :aggregate_failures do
        request

        expect(response).to have_gitlab_http_status(:accepted)
        expect(rollout.reload.open_approval_gate?).to be(false)
      end
    end

    context 'with a step_started event for an approval step' do
      let(:params) do
        { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.step_started',
          data: { stage_name: 'production', position: [0, 0], step_type: 'com.gitlab.cd.steps.approval' } }
      end

      it 'opens an approval gate, returns accepted, and records a request_approval transition',
        :aggregate_failures do
        request

        expect(response).to have_gitlab_http_status(:accepted)
        expect(rollout.reload.open_approval_gate?).to be(true)
        expect(rollout.rollout_transitions.last).to have_attributes(
          event: 'request_approval',
          from_state: rollout.state,
          to_state: rollout.state,
          principal: 'system:autoflow'
        )
      end

      context 'when retried after already opening the gate' do
        it 'treats the retry as a no-op and does not duplicate the transition' do
          post api("/rollouts/#{rollout.id}"), params: params, headers: headers

          expect { request }.not_to change { rollout.rollout_transitions.count }
          expect(response).to have_gitlab_http_status(:accepted)
        end
      end

      context 'when the rollout already reached a terminal state' do
        before do
          rollout.cancel!
        end

        it 'does not open an approval gate on the stale/late-arriving event' do
          expect { request }.not_to change { rollout.rollout_transitions.count }

          expect(response).to have_gitlab_http_status(:accepted)
          expect(rollout.reload.open_approval_gate?).to be(false)
        end
      end
    end

    context 'with an approval_requested event' do
      let(:params) do
        { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.approval_requested',
          data: { position: [0, 1], stage_name: 'production', step_type: 'com.gitlab.cd.steps.approval',
                  reason: 'Please can we deploy to prod?', reply: 'approval-channel' },
          channel_tokens: [{ channel_name: 'approval-channel', token: 'a-token' }] }
      end

      it 'accepts the event, opens an approval gate, and records the reason' do
        request

        expect(response).to have_gitlab_http_status(:accepted)
        expect(rollout.reload.open_approval_gate?).to be(true)
        expect(rollout.rollout_transitions.last).to have_attributes(
          event: 'request_approval', reason: 'Please can we deploy to prod?'
        )
      end

      context 'when data[reason] is missing' do
        before do
          params[:data].delete(:reason)
        end

        it 'returns bad_request' do
          request

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end

      context 'when data[reply] is missing' do
        before do
          params[:data].delete(:reply)
        end

        it 'returns bad_request' do
          request

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end

      context 'when channel_tokens is missing entirely' do
        before do
          params.delete(:channel_tokens)
        end

        it 'returns bad_request' do
          request

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end

      context 'when channel_tokens has no entry matching data[reply]' do
        before do
          params[:channel_tokens] = [{ channel_name: 'a-different-channel', token: 'a-token' }]
        end

        it 'returns bad_request' do
          request

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end
    end

    context 'with a step_started event inside a stage' do
      let!(:rollout_environment) do
        create(:cd_rollout_environment, rollout: rollout, environment: environment,
          driver_binding: driver_binding, state: :in_progress)
      end

      let(:params) do
        { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.step_started',
          data: { stage_name: 'production', position: [0, 0], step_type: 'com.gitlab.cd.argo.canary.deploy' } }
      end

      it 'acknowledges the event without changing the rollout environment' do
        request

        expect(response).to have_gitlab_http_status(:accepted)
        expect(rollout_environment.reload.state).to eq('in_progress')
      end
    end

    context 'with a step_started event that names its environment' do
      let!(:rollout_environment) do
        create(:cd_rollout_environment, rollout: rollout, environment: environment,
          driver_binding: driver_binding, state: :pending)
      end

      let(:params) do
        { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.step_started',
          data: { stage_name: 'production', environment: 'production', position: [0, 0],
                  step_type: 'com.gitlab.cd.argo.canary.deploy' } }
      end

      it 'transitions the named rollout environment to in_progress' do
        request

        expect(response).to have_gitlab_http_status(:accepted)
        expect(rollout_environment.reload.state).to eq('in_progress')
      end
    end

    context 'with a step_succeeded event that names its environment' do
      let!(:rollout_environment) do
        create(:cd_rollout_environment, rollout: rollout, environment: environment,
          driver_binding: driver_binding, state: :in_progress)
      end

      let(:params) do
        { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.step_succeeded',
          data: { stage_name: 'production', environment: 'production', position: [0, 0],
                  step_type: 'com.gitlab.cd.argo.canary.deploy' } }
      end

      it 'transitions the named rollout environment to completed' do
        request

        expect(response).to have_gitlab_http_status(:accepted)
        expect(rollout_environment.reload.state).to eq('completed')
      end
    end

    context 'with a stage_started event' do
      let!(:rollout_environment) do
        create(:cd_rollout_environment, rollout: rollout, environment: environment,
          driver_binding: driver_binding, state: :pending)
      end

      let(:params) do
        { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.stage_started',
          data: { stage_name: 'production', environment: 'production', position: [0] } }
      end

      it 'transitions the named rollout environment to in_progress and returns accepted' do
        request

        expect(response).to have_gitlab_http_status(:accepted)
        expect(rollout_environment.reload.state).to eq('in_progress')
      end

      context 'when retried after already being applied' do
        it 'treats the retry as a no-op and returns accepted' do
          post api("/rollouts/#{rollout.id}"), params: params, headers: headers

          request

          expect(response).to have_gitlab_http_status(:accepted)
          expect(rollout_environment.reload.state).to eq('in_progress')
        end
      end

      context 'when the environment does not match any rollout environment' do
        let(:params) do
          { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.stage_started',
            data: { stage_name: 'production', environment: 'unknown-environment', position: [0] } }
        end

        it 'returns accepted without changing any rollout environment' do
          request

          expect(response).to have_gitlab_http_status(:accepted)
          expect(rollout_environment.reload.state).to eq('pending')
        end
      end

      context 'when the event carries a stage_name but no environment' do
        let(:params) do
          { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.stage_started',
            data: { stage_name: 'production', position: [0] } }
        end

        it 'acknowledges the event without changing any rollout environment' do
          request

          expect(response).to have_gitlab_http_status(:accepted)
          expect(rollout_environment.reload.state).to eq('pending')
        end
      end

      context 'when the stage has more than one environment' do
        let(:environment_eu) { create(:cd_environment, organization: organization, name: 'production-eu') }
        let!(:rollout_environment_eu) do
          create(:cd_rollout_environment, rollout: rollout, environment: environment_eu, state: :pending)
        end

        let(:params_eu) do
          { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.stage_started',
            data: { stage_name: 'production', environment: 'production-eu', position: [0] } }
        end

        it 'resolves the rollout environment by the exact environment name, not the shared stage name' do
          post api("/rollouts/#{rollout.id}"), params: params_eu, headers: headers

          expect(response).to have_gitlab_http_status(:accepted)
          expect(rollout_environment_eu.reload.state).to eq('in_progress')
          expect(rollout_environment.reload.state).to eq('pending')
        end
      end
    end

    context 'with a stage_succeeded event' do
      let!(:rollout_environment) do
        create(:cd_rollout_environment, rollout: rollout, environment: environment,
          driver_binding: driver_binding, state: :in_progress)
      end

      let(:params) do
        { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.stage_succeeded',
          data: { stage_name: 'production', environment: 'production', position: [0] } }
      end

      it 'transitions the named rollout environment to completed and returns accepted' do
        request

        expect(response).to have_gitlab_http_status(:accepted)
        expect(rollout_environment.reload.state).to eq('completed')
      end
    end

    context 'with a step_failed event that names a stage' do
      let!(:rollout_environment) do
        create(:cd_rollout_environment, rollout: rollout, environment: environment,
          driver_binding: driver_binding, state: :in_progress)
      end

      let(:params) do
        { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.step_failed',
          data: { stage_name: 'production', environment: 'production', position: [0, 0],
                  step_type: 'com.gitlab.cd.argo.canary.deploy',
                  error: 'environment 42 not found in environments' } }
      end

      it 'transitions the named rollout environment to failed and returns accepted' do
        request

        expect(response).to have_gitlab_http_status(:accepted)
        expect(rollout_environment.reload.state).to eq('failed')
      end
    end

    context 'with a step_failed event outside any stage' do
      let!(:rollout_environment) do
        create(:cd_rollout_environment, rollout: rollout, environment: environment,
          driver_binding: driver_binding, state: :in_progress)
      end

      let(:params) do
        { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.step_failed',
          data: { position: [1], step_type: 'com.gitlab.cd.steps.wait',
                  error: 'unsupported step type: com.gitlab.cd.steps.wait' } }
      end

      it 'acknowledges the event without changing any rollout environment' do
        request

        expect(response).to have_gitlab_http_status(:accepted)
        expect(rollout_environment.reload.state).to eq('in_progress')
      end
    end

    context 'with a rollout_succeeded event' do
      # Posted as JSON rather than form params, which drop an empty nested hash and so
      # would exercise a missing `data` instead of the empty one this event carries.
      subject(:request) do
        post api("/rollouts/#{rollout.id}"), params: params.to_json,
          headers: headers.merge('Content-Type' => 'application/json')
      end

      let!(:rollout_environment) do
        create(:cd_rollout_environment, rollout: rollout, environment: environment,
          driver_binding: driver_binding, state: :completed)
      end

      let(:params) do
        { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.rollout_succeeded', data: {} }
      end

      # The orchestrator fails the flow when a report is not accepted, so refusing the
      # terminal event for its empty payload would abort a deploy that had succeeded.
      it 'accepts the empty payload, completes the rollout, and returns accepted' do
        request

        expect(response).to have_gitlab_http_status(:accepted)
        expect(rollout.reload.state).to eq('completed')
        expect(rollout_environment.reload.state).to eq('completed')
      end
    end

    context 'when a stale event arrives after the environment already finished' do
      let!(:rollout_environment) do
        create(:cd_rollout_environment, rollout: rollout, environment: environment,
          driver_binding: driver_binding, state: :completed)
      end

      let(:params) do
        { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.stage_started',
          data: { stage_name: 'production', environment: 'production', position: [0] } }
      end

      it 'leaves the already-terminal rollout environment unchanged' do
        request

        expect(response).to have_gitlab_http_status(:accepted)
        expect(rollout_environment.reload.state).to eq('completed')
      end
    end

    context 'when a step_started event names a rollout step' do
      let!(:rollout_step) { create(:cd_rollout_step, rollout: rollout, path: '1', state: :pending) }

      let(:params) do
        { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.step_started',
          data: { position: [1], step_type: 'com.gitlab.cd.steps.wait' } }
      end

      it 'transitions the rollout step to running' do
        request

        expect(response).to have_gitlab_http_status(:accepted)
        expect(rollout_step.reload.state).to eq('running')
      end
    end

    context 'when a step_succeeded event completes the only step in the rollout' do
      let!(:rollout_step) { create(:cd_rollout_step, rollout: rollout, path: '0', state: :running) }

      let(:params) do
        { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.step_succeeded',
          data: { position: [0], step_type: 'com.gitlab.cd.steps.wait' } }
      end

      it 'completes the rollout step but leaves the rollout in progress until rollout_succeeded arrives' do
        request

        expect(response).to have_gitlab_http_status(:accepted)
        expect(rollout_step.reload.state).to eq('success')
        expect(rollout.reload.state).to eq('in_progress')
      end
    end

    context 'when a step_failed event names a rollout step' do
      let!(:rollout_step) { create(:cd_rollout_step, rollout: rollout, path: '0', state: :running) }
      let!(:other_step) { create(:cd_rollout_step, rollout: rollout, path: '1', state: :pending) }

      let(:params) do
        { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.step_failed',
          data: { position: [0], step_type: 'com.gitlab.cd.steps.wait', error: 'boom' } }
      end

      it 'fails the rollout step, records the error, and fails the rollout immediately' do
        request

        expect(response).to have_gitlab_http_status(:accepted)
        expect(rollout_step.reload).to have_attributes(state: 'failed', error: 'boom')
        expect(other_step.reload.state).to eq('pending')
        expect(rollout.reload.state).to eq('failed')
      end
    end

    context 'when a stage_failed event names the stage step' do
      let!(:stage_step) { create(:cd_rollout_step, rollout: rollout, path: '0', state: :running) }

      let(:params) do
        { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.stage_failed',
          data: { stage_name: 'production', position: [0] } }
      end

      it 'fails the stage step and the rollout' do
        request

        expect(response).to have_gitlab_http_status(:accepted)
        expect(stage_step.reload.state).to eq('failed')
        expect(rollout.reload.state).to eq('failed')
      end
    end

    context 'with a stage_failed event that names its environment' do
      let!(:rollout_environment) do
        create(:cd_rollout_environment, rollout: rollout, environment: environment,
          driver_binding: driver_binding, state: :in_progress)
      end

      let(:params) do
        { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.stage_failed',
          data: { stage_name: 'production', environment: 'production', position: [0] } }
      end

      it 'transitions the named rollout environment to failed' do
        request

        expect(response).to have_gitlab_http_status(:accepted)
        expect(rollout_environment.reload.state).to eq('failed')
      end
    end

    context 'with a service_started event that names its environment and service' do
      let!(:rollout_environment) do
        create(:cd_rollout_environment, rollout: rollout, environment: environment,
          driver_binding: driver_binding, state: :in_progress)
      end

      let!(:deployment) do
        create(:cd_deployment, service: cd_service, rollout_environment: rollout_environment, state: :pending)
      end

      let(:params) do
        { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.service_started',
          data: { stage_name: 'production', environment: 'production', service: 'web', position: [0, 0] } }
      end

      it 'transitions the named deployment to deploying, returns accepted, and records the transition',
        :aggregate_failures do
        request

        expect(response).to have_gitlab_http_status(:accepted)
        expect(deployment.reload.state).to eq('deploying')
        expect(deployment.deployment_transitions.last).to have_attributes(
          event: 'start_deploying', from_state: 'pending', to_state: 'deploying', principal: 'system:autoflow'
        )
      end

      context 'when retried after already being applied' do
        it 'treats the retry as a no-op and does not duplicate the transition' do
          post api("/rollouts/#{rollout.id}"), params: params, headers: headers

          expect { request }.not_to change { deployment.reload.deployment_transitions.count }
          expect(response).to have_gitlab_http_status(:accepted)
        end
      end
    end

    context 'with a service_succeeded event that names its environment and service' do
      let!(:rollout_environment) do
        create(:cd_rollout_environment, rollout: rollout, environment: environment,
          driver_binding: driver_binding, state: :in_progress)
      end

      let!(:deployment) do
        create(:cd_deployment, service: cd_service, rollout_environment: rollout_environment, state: :deploying)
      end

      let(:params) do
        { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.service_succeeded',
          data: { stage_name: 'production', environment: 'production', service: 'web', position: [0, 0] } }
      end

      it 'transitions the named deployment to healthy' do
        request

        expect(response).to have_gitlab_http_status(:accepted)
        expect(deployment.reload.state).to eq('healthy')
      end
    end

    context 'with a service_failed event that names its environment and service' do
      let!(:rollout_environment) do
        create(:cd_rollout_environment, rollout: rollout, environment: environment,
          driver_binding: driver_binding, state: :in_progress)
      end

      let!(:deployment) do
        create(:cd_deployment, service: cd_service, rollout_environment: rollout_environment, state: :deploying)
      end

      let(:params) do
        { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.service_failed',
          data: { stage_name: 'production', environment: 'production', service: 'web', position: [0, 0],
                  error: 'sync timed out' } }
      end

      it 'transitions the named deployment to failed and records the error as the reason' do
        request

        expect(response).to have_gitlab_http_status(:accepted)
        expect(deployment.reload.state).to eq('failed')
        expect(deployment.deployment_transitions.last.reason).to eq('sync timed out')
      end
    end

    context 'when a service_started event names no matching service' do
      let!(:rollout_environment) do
        create(:cd_rollout_environment, rollout: rollout, environment: environment,
          driver_binding: driver_binding, state: :in_progress)
      end

      let(:params) do
        { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.service_started',
          data: { stage_name: 'production', environment: 'production', service: 'unknown-service',
                  position: [0, 0] } }
      end

      it 'acknowledges the event without changing any deployment' do
        request

        expect(response).to have_gitlab_http_status(:accepted)
      end
    end

    context 'with a post_value envelope' do
      def value_for(payload)
        Gitlab::Json::SafeParser.parse(Gitlab::Kas::Autoflow::ValueConverter.to_value(payload).to_json)
      end

      let(:event_payload) do
        { topic: 'com.gitlab.cd.deployment', type: 'com.gitlab.cd.step_started',
          data: { position: [1], step_type: 'com.gitlab.cd.steps.wait' } }
      end

      let(:params) { { value: value_for(event_payload) } }

      it 'decodes the value and processes it like a flat event' do
        request

        expect(response).to have_gitlab_http_status(:accepted)
      end

      context 'with channel_tokens' do
        let(:params) do
          { value: value_for(event_payload),
            channel_tokens: [{ channel_name: 'approval', token: 'a-token' }] }
        end

        it 'persists a channel token keyed to the rollout' do
          expect { request }.to change { rollout.rollout_channel_tokens.count }.by(1)

          expect(response).to have_gitlab_http_status(:accepted)
          expect(rollout.rollout_channel_tokens.last).to have_attributes(channel_name: 'approval', token: 'a-token')
        end

        context 'when re-posted for the same channel_name' do
          it 'overwrites the existing token rather than conflicting' do
            post api("/rollouts/#{rollout.id}"), params: params, headers: headers

            new_params = { value: value_for(event_payload),
                           channel_tokens: [{ channel_name: 'approval', token: 'a-new-token' }] }
            new_headers = headers.merge('Idempotency-Key' => SecureRandom.uuid)

            expect do
              post api("/rollouts/#{rollout.id}"), params: new_params, headers: new_headers
            end.not_to change { rollout.rollout_channel_tokens.count }

            expect(response).to have_gitlab_http_status(:accepted)
            expect(rollout.rollout_channel_tokens.last.token).to eq('a-new-token')
          end
        end
      end

      context 'without channel_tokens' do
        it 'does not require them' do
          request

          expect(response).to have_gitlab_http_status(:accepted)
          expect(rollout.rollout_channel_tokens).to be_empty
        end
      end

      context 'with an approval_requested event carrying a reply channel' do
        # channel_value has no Ruby counterpart on the `to_value` side (Rails never
        # emits it), so value_for can't build this - it's written as the raw
        # protojson AutoFlow itself would send.
        let(:params) do
          { value: {
              dict_value: { key_values: [
                { key: { string_value: 'topic' }, val: { string_value: 'com.gitlab.cd.deployment' } },
                { key: { string_value: 'type' }, val: { string_value: 'com.gitlab.cd.approval_requested' } },
                { key: { string_value: 'data' }, val: { dict_value: { key_values: [
                  { key: { string_value: 'position' },
                    val: { list_value: { values: [{ integer_value: '0' }, { integer_value: '1' }] } } },
                  { key: { string_value: 'stage_name' }, val: { string_value: 'production' } },
                  { key: { string_value: 'step_type' }, val: { string_value: 'com.gitlab.cd.steps.approval' } },
                  { key: { string_value: 'reason' }, val: { string_value: 'Please can we deploy to prod?' } },
                  { key: { string_value: 'reply' },
                    val: { channel_value: { name: '__autocore_internal:ch:1' } } }
                ] } } }
              ] }
            },
            channel_tokens: [{ channel_name: '__autocore_internal:ch:1', token: 'a-jwt-token' }] }
        end

        it 'decodes the channel_value reply, opens an approval gate, and persists the channel token' do
          request

          expect(response).to have_gitlab_http_status(:accepted)
          expect(rollout.reload.open_approval_gate?).to be(true)
          expect(rollout.rollout_channel_tokens.last).to have_attributes(
            channel_name: '__autocore_internal:ch:1', token: 'a-jwt-token'
          )
        end
      end

      context 'when value is malformed protojson' do
        let(:params) { { value: { not_a_real_oneof_field: 'x' } } }

        it 'returns bad_request' do
          request

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end

      context 'when value decodes but is missing topic/type/data' do
        let(:params) { { value: value_for('just a string') } }

        it 'returns bad_request' do
          request

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end

      context 'when both data and value are given' do
        let(:params) { { data: event_payload[:data], value: value_for(event_payload) } }

        it 'returns bad_request' do
          request

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end
    end
  end
end
