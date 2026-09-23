# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'gitlab:audit_events:streaming:nats rake tasks', :silence_stdout, feature_category: :audit_events do
  before do
    Rake.application.rake_require 'tasks/gitlab/audit_events/streaming/nats'
  end

  describe 'ensure_stream' do
    context 'when NATS is reachable' do
      let(:provisioner) do
        instance_double(
          AuditEvents::Streaming::NatsStreamProvisioner,
          ensure!: AuditEvents::Streaming::NatsStreamProvisioner::Result.new(:created, nil)
        )
      end

      before do
        allow(AuditEvents::Streaming::NatsStreamProvisioner).to receive(:new).and_return(provisioner)
      end

      it 'ensures the stream' do
        expect(provisioner).to receive(:ensure!)

        run_rake_task('gitlab:audit_events:streaming:nats:ensure_stream')
      end
    end

    context 'when the NATS server is unreachable' do
      before do
        provisioner = instance_double(AuditEvents::Streaming::NatsStreamProvisioner)
        allow(AuditEvents::Streaming::NatsStreamProvisioner).to receive(:new).and_return(provisioner)
        allow(provisioner).to receive(:ensure!).and_raise(::Gitlab::Nats::Client::ConnectionError, 'refused')
      end

      it 'aborts with a friendly message instead of a raw backtrace' do
        expect { run_rake_task('gitlab:audit_events:streaming:nats:ensure_stream') }
          .to raise_error(SystemExit)
          .and output(/Could not reach the NATS server/).to_stderr
      end
    end
  end

  describe 'stream_info' do
    it 'prints the stream info' do
      provisioner = instance_double(AuditEvents::Streaming::NatsStreamProvisioner, info: nil)
      allow(AuditEvents::Streaming::NatsStreamProvisioner).to receive(:new).and_return(provisioner)

      expect { run_rake_task('gitlab:audit_events:streaming:nats:stream_info') }.not_to raise_error
    end

    context 'when the NATS server is unreachable' do
      before do
        provisioner = instance_double(AuditEvents::Streaming::NatsStreamProvisioner)
        allow(AuditEvents::Streaming::NatsStreamProvisioner).to receive(:new).and_return(provisioner)
        allow(provisioner).to receive(:info).and_raise(::Gitlab::Nats::Client::ConnectionError, 'refused')
      end

      it 'aborts with a friendly message instead of a raw backtrace' do
        expect { run_rake_task('gitlab:audit_events:streaming:nats:stream_info') }
          .to raise_error(SystemExit)
          .and output(/Could not reach the NATS server/).to_stderr
      end
    end
  end
end
