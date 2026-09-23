# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Messaging::WebhookDeliveryWorker, feature_category: :duo_agent_platform do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user) }
  let_it_be(:workflow) { create(:duo_workflows_workflow, project: project, user: user) }

  # Reloadable: one example clears the capability flag.
  let_it_be_with_reload(:hook) { create(:group_hook, group: group, duo_flow_callback_enabled: true) }

  let(:base_payload) do
    {
      'object_kind' => 'duo_workflow',
      'version' => '1',
      'event' => 'flow.started',
      'event_id' => 'ffffffff-1111-2222-3333-444444444444'
    }
  end

  describe '#perform' do
    context 'when the hook no longer exists' do
      it 'does not call WebHookService' do
        expect(WebHookService).not_to receive(:new)

        described_class.new.perform(non_existing_record_id, workflow.id, base_payload)
      end
    end

    context 'when the queued payload is missing a required key' do
      described_class::REQUIRED_PAYLOAD_KEYS.each do |key|
        it "drops the delivery and logs the missing #{key}", :aggregate_failures do
          expect(WebHookService).not_to receive(:new)
          expect(Gitlab::AppLogger).to receive(:warn).with(
            hash_including(missing_keys: [key], hook_id: hook.id)
          )

          described_class.new.perform(hook.id, workflow.id, base_payload.except(key))
        end
      end
    end

    context 'when the instance is in silent mode' do
      before do
        stub_application_setting(silent_mode_enabled: true)
      end

      it 'drops the event instead of burning the retry budget', :aggregate_failures do
        logger = instance_double(Gitlab::WebHooks::Logger)
        allow(Gitlab::WebHooks::Logger).to receive(:build).and_return(logger)

        expect(WebHookService).not_to receive(:new)
        expect(described_class).not_to receive(:perform_at)
        expect(logger).to receive(:error).with(
          hash_including(
            hook_id: hook.id,
            action: 'duo_flow_callback_dropped',
            Labkit::Fields::LOG_MESSAGE => 'silent_mode',
            Labkit::Fields::GL_ORGANIZATION_ID => hook.parent.organization_id,
            Labkit::Fields::DUO_WORKFLOW_ID => workflow.id
          )
        )

        expect { described_class.new.perform(hook.id, workflow.id, base_payload) }.not_to raise_error
      end
    end

    context 'when the hook was switched off after the job was queued' do
      it 'does not call WebHookService' do
        hook.update!(duo_flow_callback_enabled: false)

        expect(WebHookService).not_to receive(:new)

        described_class.new.perform(hook.id, workflow.id, base_payload)
      end
    end

    context 'when delivery succeeds' do
      it 'refetches record data from the workflow id and builds the full payload', :aggregate_failures do
        expect(WebHookService).to receive(:new) do |received_hook, payload, hook_name, idempotency_key:|
          expect(received_hook).to eq(hook)
          expect(hook_name).to eq(described_class::HOOK_NAME)
          expect(idempotency_key).to eq(base_payload['event_id'])
          expect(payload['event']).to eq('flow.started')
          expect(payload['project']).to eq(project.hook_attrs.deep_stringify_keys)
          expect(payload['user']).to eq(user.hook_attrs.deep_stringify_keys)
          expect(payload['workflow']).to eq(
            'id' => workflow.id, 'status' => workflow.status_name.to_s, 'web_url' => workflow.web_url
          )

          instance_double(WebHookService).tap do |service|
            allow(service).to receive(:execute)
              .and_return(ServiceResponse.success(payload: { http_status: 200, response_category: :ok }))
          end
        end

        expect { described_class.new.perform(hook.id, workflow.id, base_payload) }.not_to raise_error
      end

      it 'omits record data when no workflow id is given' do
        expect(WebHookService).to receive(:new) do |_hook, payload, _name, **_opts|
          expect(payload.keys).not_to include('project', 'user', 'workflow')

          instance_double(WebHookService).tap do |service|
            allow(service).to receive(:execute)
              .and_return(ServiceResponse.success(payload: { http_status: 200, response_category: :ok }))
          end
        end

        described_class.new.perform(hook.id, nil, base_payload)
      end
    end

    context 'when the request never reached the receiver' do
      it 'raises so Sidekiq retries the job' do
        expect_next_instance_of(
          WebHookService, hook, anything, described_class::HOOK_NAME, idempotency_key: base_payload['event_id']
        ) do |service|
          expect(service).to receive(:execute).and_return(ServiceResponse.error(message: 'connection refused'))
        end

        expect { described_class.new.perform(hook.id, workflow.id, base_payload) }
          .to raise_error(described_class::DeliveryError, /connection refused/)
      end
    end

    # Runs against the real WebHookService on purpose. It returns a successful
    # ServiceResponse for any request that completed, so stubbing the response
    # would hide whether the worker inspects the status at all.
    context 'when the receiver responds' do
      where(:http_status, :retries) do
        200 | false
        201 | false
        204 | false
        301 | false
        400 | true
        404 | true
        500 | true
        503 | true
      end

      with_them do
        before do
          stub_full_request(hook.url, method: :post).to_return(status: http_status, body: '')
        end

        it 'retries only when the receiver rejected the delivery' do
          deliver = -> { described_class.new.perform(hook.id, workflow.id, base_payload) }

          if retries
            expect { deliver.call }.to raise_error(described_class::DeliveryError)
          else
            expect { deliver.call }.not_to raise_error
          end
        end
      end
    end

    context 'when the hook is in an auto-disable window' do
      let(:logger) { instance_double(Gitlab::WebHooks::Logger) }

      before do
        allow(Gitlab::WebHooks::Logger).to receive(:build).and_return(logger)
        allow(logger).to receive(:error)
      end

      context 'when temporarily disabled' do
        let(:resume_at) { 10.minutes.from_now.change(nsec: 123456789) }

        before do
          hook.update!(recent_failures: 5, disabled_until: resume_at)
        end

        it 'waits for the window to close instead of delivering', :aggregate_failures do
          expect(WebHookService).not_to receive(:new)
          # Postgres truncates to microseconds, so assert on the persisted value the worker
          # reads rather than the in-memory one.
          expect(described_class).to receive(:perform_at)
            .with(hook.reload.disabled_until, hook.id, workflow.id, base_payload, 1)

          described_class.new.perform(hook.id, workflow.id, base_payload)
        end

        it 'gives up once the wait budget is spent', :aggregate_failures do
          expect(described_class).not_to receive(:perform_at)
          expect(logger).to receive(:error).with(
            hash_including(
              Labkit::Fields::LOG_MESSAGE => 'wait_exhausted',
              Labkit::Fields::GL_ORGANIZATION_ID => hook.parent.organization_id,
              Labkit::Fields::DUO_WORKFLOW_ID => workflow.id
            )
          )

          described_class.new.perform(hook.id, workflow.id, base_payload, described_class::MAX_DISABLED_REQUEUES)
        end

        context 'and auto-disabling is switched off' do
          before do
            stub_feature_flags(auto_disabling_web_hooks: false)
          end

          it 'delivers rather than deferring, because the hook counts as executable' do
            expect(described_class).not_to receive(:perform_at)
            expect_next_instance_of(
              WebHookService, hook, anything, described_class::HOOK_NAME, idempotency_key: base_payload['event_id']
            ) do |service|
              expect(service).to receive(:execute)
                .and_return(ServiceResponse.success(payload: { http_status: 200, response_category: :ok }))
            end

            described_class.new.perform(hook.id, workflow.id, base_payload)
          end
        end
      end

      context 'when temporarily disabled without a disabled_until' do
        before do
          hook.update!(recent_failures: 5, disabled_until: nil)
        end

        it 'falls back to the shortest backoff rather than crashing' do
          expect(described_class).to receive(:perform_at)
            .with(
              be_within(1.second).of(WebHooks::AutoDisabling::INITIAL_BACKOFF.from_now),
              hook.id, workflow.id, base_payload, 1
            )

          described_class.new.perform(hook.id, workflow.id, base_payload)
        end
      end

      context 'when permanently disabled' do
        before do
          hook.update!(recent_failures: 100)
        end

        it 'drops the event immediately and logs it', :aggregate_failures do
          expect(described_class).not_to receive(:perform_at)
          expect(WebHookService).not_to receive(:new)
          expect(logger).to receive(:error).with(
            hash_including(
              Labkit::Fields::LOG_MESSAGE => 'hook_disabled',
              Labkit::Fields::GL_ORGANIZATION_ID => hook.parent.organization_id,
              Labkit::Fields::DUO_WORKFLOW_ID => workflow.id
            )
          )

          described_class.new.perform(hook.id, workflow.id, base_payload)
        end
      end
    end

    describe 'sidekiq_retries_exhausted' do
      it 'logs the dropped terminal event' do
        logger = instance_double(Gitlab::WebHooks::Logger)
        allow(Gitlab::WebHooks::Logger).to receive(:build).and_return(logger)

        expect(logger).to receive(:error).with(
          hash_including(
            hook_id: hook.id,
            action: 'duo_flow_callback_dropped',
            Labkit::Fields::LOG_MESSAGE => 'retries_exhausted',
            Labkit::Fields::GL_ORGANIZATION_ID => hook.parent.organization_id,
            Labkit::Fields::DUO_WORKFLOW_ID => workflow.id,
            event: 'flow.started',
            Labkit::Fields::ERROR_MESSAGE => 'boom'
          )
        )

        described_class.sidekiq_retries_exhausted_block.call(
          { 'args' => [hook.id, workflow.id, base_payload] }, StandardError.new('boom')
        )
      end
    end

    it_behaves_like 'an idempotent worker' do
      let(:job_args) { [hook.id, workflow.id, base_payload] }

      before do
        stub_full_request(hook.url, method: :post).to_return(status: 200, body: '')
      end
    end

    describe 'DeliveryError' do
      it 'inherits RetryError so expected retries stay out of Sentry' do
        expect(described_class::DeliveryError.ancestors).to include(::Gitlab::SidekiqMiddleware::RetryError)
      end
    end
  end
end
