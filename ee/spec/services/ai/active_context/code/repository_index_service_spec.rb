# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::ActiveContext::Code::RepositoryIndexService, feature_category: :global_search do
  let_it_be(:project) { create(:project) }
  let_it_be(:other_project) { create(:project) }
  let_it_be(:repository) { create(:ai_active_context_code_repository, state: :pending, project: project) }

  describe '.enqueue_pending_jobs' do
    before do
      allow(::Ai::ActiveContext::Code::Repository).to receive_message_chain(:pending, :with_active_connection)
        .and_return(::Ai::ActiveContext::Code::Repository.all)
    end

    it 'enqueues RepositoryIndexWorker jobs for eligible repositories' do
      expect(Ai::ActiveContext::Code::RepositoryIndexWorker).to receive(:perform_async).with(repository.id)

      described_class.enqueue_pending_jobs
    end

    it 'respects the batch limit' do
      stub_const("#{described_class}::BATCH_LIMIT", 0)

      expect(Ai::ActiveContext::Code::RepositoryIndexWorker).not_to receive(:perform_async)

      described_class.enqueue_pending_jobs
    end
  end

  describe '.enqueue_retry_jobs' do
    let_it_be(:active_connection) { create(:ai_active_context_connection, active: true) }
    let_it_be(:enabled_namespace) do
      create(:ai_active_context_code_enabled_namespace, connection_id: active_connection.id)
    end

    let_it_be(:pending_retry_repository) do
      create(:ai_active_context_code_repository,
        state: :pending_retry, project: project, enabled_namespace: enabled_namespace,
        connection_id: active_connection.id)
    end

    let_it_be(:other_state_repository) do
      create(:ai_active_context_code_repository,
        state: :pending, project: other_project, enabled_namespace: enabled_namespace,
        connection_id: active_connection.id)
    end

    let_it_be(:inactive_connection) { create(:ai_active_context_connection, :inactive) }
    let_it_be(:inactive_namespace) do
      create(:ai_active_context_code_enabled_namespace, connection_id: inactive_connection.id)
    end

    let_it_be(:inactive_repository) do
      create(:ai_active_context_code_repository,
        state: :pending_retry, project: project, enabled_namespace: inactive_namespace,
        connection_id: inactive_connection.id)
    end

    it 'enqueues RepositoryIndexWorker jobs for eligible repositories' do
      expect(Ai::ActiveContext::Code::RepositoryIndexWorker).to receive(:perform_async)
        .with(pending_retry_repository.id)

      described_class.enqueue_retry_jobs
    end

    it 'respects the batch limit' do
      stub_const("#{described_class}::BATCH_LIMIT", 0)

      expect(Ai::ActiveContext::Code::RepositoryIndexWorker).not_to receive(:perform_async)

      described_class.enqueue_retry_jobs
    end

    it 'ignores repositories in other states' do
      expect(Ai::ActiveContext::Code::RepositoryIndexWorker).not_to receive(:perform_async)
        .with(other_state_repository.id)

      described_class.enqueue_retry_jobs
    end

    it 'ignores repositories with an inactive connection' do
      expect(Ai::ActiveContext::Code::RepositoryIndexWorker).not_to receive(:perform_async)
        .with(inactive_repository.id)

      described_class.enqueue_retry_jobs
    end
  end

  describe '.enqueue_pending_deletion_jobs' do
    let_it_be(:deletion_repository) do
      create(:ai_active_context_code_repository, state: :pending_deletion, project: project)
    end

    before do
      allow(::Ai::ActiveContext::Code::Repository).to receive_message_chain(:pending_deletion, :with_active_connection)
        .and_return(::Ai::ActiveContext::Code::Repository.where(state: :pending_deletion))
    end

    it 'enqueues RepositoryDeleteWorker jobs for eligible repositories' do
      expect(Ai::ActiveContext::Code::RepositoryDeleteWorker).to receive(:perform_async).with(deletion_repository.id)

      described_class.enqueue_pending_deletion_jobs
    end

    it 'respects the batch limit' do
      stub_const("#{described_class}::BATCH_LIMIT", 0)

      expect(Ai::ActiveContext::Code::RepositoryDeleteWorker).not_to receive(:perform_async)

      described_class.enqueue_pending_deletion_jobs
    end
  end
end
