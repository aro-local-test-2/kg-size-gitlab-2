# frozen_string_literal: true

RSpec.shared_examples 'active_context pause-controlled worker' do
  it 'is a pause_control worker' do
    expect(described_class.get_pause_control).to eq(:active_context)
  end

  it 'checks the Ai::ActiveContext.paused?', :sidekiq_inline do
    # we return false value since we don't need to do any further tests
    # around the worker's actual `perform` method
    expect(::Ai::ActiveContext).to receive(:paused?).at_least(:once).and_return(false)

    described_class.perform_async(*worker_params)
  end

  it 'diverts to the pause_control waiting queue when active_context indexing is paused' do
    allow(::ActiveContext).to receive(:indexing?).and_return(true)
    stub_application_setting(active_context_pause_indexing: true)

    expect { described_class.perform_async(*worker_params) }
      .to change { Gitlab::SidekiqMiddleware::PauseControl::PauseControlService.queue_size(described_class.name) }.by(1)
  end

  it 'does not divert when active_context indexing is not paused' do
    allow(::ActiveContext).to receive(:indexing?).and_return(true)
    stub_application_setting(active_context_pause_indexing: false)

    expect { described_class.perform_async(*worker_params) }
      .not_to change { Gitlab::SidekiqMiddleware::PauseControl::PauseControlService.queue_size(described_class.name) }
  end
end
