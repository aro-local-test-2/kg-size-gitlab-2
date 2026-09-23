# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PullMirrors::ReenableConfigurationWorker, feature_category: :source_code_management do
  let_it_be(:project, freeze: false) { create(:project) }
  let_it_be(:mirror_state, freeze: false) { create(:import_state, :mirror, :failed, retry_count: 15, project: project) }
  let_it_be(:namespace) { project.namespace }

  let_it_be(:project_without_mirror, freeze: false) { create(:project, namespace: namespace) }
  let_it_be(:import_state) { create(:import_state, :failed, retry_count: 15, project: project_without_mirror) }

  let_it_be(:another_namespace_mirror_state) { create(:import_state, :mirror, :failed, retry_count: 15) }

  let(:data) { { namespace_id: namespace.id } }
  let(:subscription_started_event) { GitlabSubscriptions::RenewedEvent.new(data: data) }

  shared_examples 're-enables pull mirror configuration' do
    it 'resets the retry count for namespace mirrors only' do
      expect do
        consume_event(subscriber: described_class, event: event)
      end.to change { mirror_state.reload.retry_count }.to(0)
        .and not_change { import_state.reload.retry_count }
        .and not_change { another_namespace_mirror_state.reload.retry_count }
    end
  end

  it_behaves_like 'subscribes to event' do
    let(:event) { subscription_started_event }
  end

  it_behaves_like 're-enables pull mirror configuration' do
    let(:event) { subscription_started_event }
  end

  context 'when namespace id is missing' do
    let(:data) { { namespace_id: non_existing_record_id } }

    it { expect { consume_event(subscriber: described_class, event: subscription_started_event) }.not_to raise_error }
  end

  context 'with a RenewedCloudEvent payload' do
    let(:subscription) { instance_double(GitlabSubscription, id: 1, namespace_id: namespace.id) }

    it_behaves_like 're-enables pull mirror configuration' do
      let(:event) { GitlabSubscriptions::RenewedCloudEvent.build(subscription: subscription) }
    end
  end

  it_behaves_like 'worker with data consistency', described_class, data_consistency: :sticky
end
