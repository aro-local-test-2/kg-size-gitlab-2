# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SecretsManagement::AuditLogWorker, :clean_gitlab_redis_shared_state,
  feature_category: :secrets_management do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }
  let_it_be(:group) { create(:group) }

  let(:openbao_request_id) { 'a9061af2-5e07-9d3f-6d31-b579e3a4be7d' }
  let(:raw_audit_log_json) do
    {
      "time" => "2025-09-27T15:01:27.13058Z",
      "type" => "response",
      "auth" => {
        "policies" => ["default", "project_#{project.id}/users/direct/user_#{user.id}"],
        "entity_id" => "60792534-ee8a-bdc5-6416-005af4303ac4",
        "metadata" => { "correlation_id" => "01K7KVMBNNDJK2YVC729B5ERF0",
                        "namespace_id" => project.namespace.id.to_s,
                        "project_id" => project.id.to_s,
                        "user_id" => user.id.to_s }
      },
      "request" => {
        "id" => openbao_request_id,
        "operation" => "read",
        "path" => "secrets/kv/data/explicit/my_test_secret",
        "namespace" => { "id" => "M0zDLE", "path" => "user_#{user.id}/project_#{project.id}/" },
        "remote_address" => "172.16.123.1"
      },
      "response" => {
        "mount_type" => "kv"
      }
    }.to_json
  end

  let(:raw_group_audit_log_json) do
    {
      "time" => "2025-09-27T15:01:27.13058Z",
      "type" => "response",
      "auth" => {
        "policies" => ["default", "group_#{group.id}/users/direct/user_#{user.id}"],
        "entity_id" => "60792534-ee8a-bdc5-6416-005af4303ac4",
        "metadata" => { "correlation_id" => "01K7KVMBNNDJK2YVC729B5ERF0",
                        "group_id" => group.id.to_s,
                        "user_id" => user.id.to_s }
      },
      "request" => {
        "id" => openbao_request_id,
        "operation" => "read",
        "path" => "secrets/kv/data/explicit/my_test_secret",
        "namespace" => { "id" => "M0zDLE", "path" => "user_#{user.id}/group_#{group.id}/" },
        "remote_address" => "172.16.123.1"
      },
      "response" => {
        "mount_type" => "kv"
      }
    }.to_json
  end

  describe '#perform' do
    subject(:perform) { described_class.new.perform(raw_audit_log_json) }

    it 'logs the audit event' do
      expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
        hash_including(
          name: :secrets_manager_read_project_secret,
          message: "Read project secret",
          ip_address: "172.16.123.1"
        )
      ).and_call_original

      perform
    end

    it 'invokes the billable event emitter with the audit log' do
      expect(SecretsManagement::BillableEvents::SecretsReadEmitter).to receive(:emit!)
        .with(an_instance_of(SecretsManagement::AuditLog))

      perform
    end

    describe 'done log metadata' do
      let(:worker) { described_class.new }
      let(:extra_prefix) { 'extra.secrets_management_audit_log_worker' }
      let(:project_path_key) { "#{extra_prefix}.gl_project_path" }
      let(:group_path_key) { "#{extra_prefix}.group_path" }

      it 'identifies the customer' do
        worker.perform(raw_audit_log_json)

        expect(worker.logging_extras).to include(project_path_key => project.full_path)
      end

      # The audit line carries the context, but a job that fails never writes one,
      # so the job hash is the only place left holding the customer.
      it 'identifies the customer even when the audit write raises' do
        allow(::Gitlab::Audit::Auditor).to receive(:audit).and_raise(StandardError, 'db error')

        expect { worker.perform(raw_audit_log_json) }.to raise_error(StandardError, 'db error')

        expect(worker.logging_extras).to include(project_path_key => project.full_path)
      end

      context 'when the secret belongs to a group' do
        let(:raw_audit_log_json) { raw_group_audit_log_json }

        it 'identifies the customer by group' do
          worker.perform(raw_audit_log_json)

          expect(worker.logging_extras).to include(group_path_key => group.full_path)
        end

        # `metadata_secret_scope` resolves a group event to the group alone, so the
        # project key must not appear alongside it.
        it 'does not log a project path' do
          worker.perform(raw_audit_log_json)

          expect(worker.logging_extras.keys).not_to include(project_path_key)
        end
      end
    end

    context 'when the audit write raises' do
      before do
        allow(::Gitlab::Audit::Auditor).to receive(:audit).and_raise(StandardError, 'db error')
      end

      it 'propagates the error so Sidekiq retries the job' do
        expect { perform }.to raise_error(StandardError, 'db error')
      end

      it 'does not mark the request id as processed, so a retry attempts the write again' do
        expect { perform }.to raise_error(StandardError, 'db error')

        expect { described_class.new.perform(raw_audit_log_json) }.to raise_error(StandardError, 'db error')
      end
    end

    context 'when the same OpenBao request is redelivered' do
      it 'writes the audit event only once' do
        expect(::Gitlab::Audit::Auditor).to receive(:audit).once.and_call_original

        2.times { described_class.new.perform(raw_audit_log_json) }
      end

      it 'still invokes the billable event emitter, which deduplicates downstream' do
        expect(SecretsManagement::BillableEvents::SecretsReadEmitter).to receive(:emit!)
          .with(an_instance_of(SecretsManagement::AuditLog)).twice

        2.times { described_class.new.perform(raw_audit_log_json) }
      end
    end

    context 'when the payload carries no OpenBao request id' do
      let(:raw_audit_log_json) do
        parsed = Gitlab::Json.safe_parse(super())
        parsed['request'].delete('id')
        parsed.to_json
      end

      it 'writes the audit event on every delivery' do
        expect(::Gitlab::Audit::Auditor).to receive(:audit).twice.and_call_original

        2.times { described_class.new.perform(raw_audit_log_json) }
      end
    end

    context 'when the billable event emitter raises' do
      before do
        allow(SecretsManagement::BillableEvents::SecretsReadEmitter)
          .to receive(:emit!).and_raise(StandardError, 'boom')
      end

      it 'tracks the exception and does not raise' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(an_instance_of(StandardError))

        expect { perform }.not_to raise_error
      end
    end

    it_behaves_like 'an idempotent worker' do
      let(:job_args) { [raw_audit_log_json] }

      it 'writes the audit event exactly once across executions' do
        expect(::Gitlab::Audit::Auditor).to receive(:audit).once.and_call_original

        perform_idempotent_work
      end
    end
  end
end
