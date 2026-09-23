# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SecretsManagement::Concerns::OpenbaoWarningHandling, feature_category: :secrets_management do
  let(:klass) do
    Class.new do
      include SecretsManagement::Concerns::OpenbaoWarningHandling
      def namespace
        "test/ns"
      end
    end
  end

  let(:object) { klass.new }

  def body(warnings)
    { "warnings" => Array(warnings) }
  end

  it "logs and continues on safe warnings" do
    expect(Gitlab::AppLogger).to receive(:warn).with(hash_including(:safe_warnings))
    expect do
      object.send(
        :handle_openbao_warnings!,
        body(
          "token max ttl is greater than the system or backend mount's maximum TTL value; " \
            "issued tokens' max TTL value will be truncated"
        ),
        endpoint: "sys/health",
        namespace: "n",
        method: :get
      )
    end.not_to raise_error
  end

  it "raises on critical warnings" do
    expect do
      object.send(:handle_openbao_warnings!, body("namespace not found"), endpoint: "kv/data/x", namespace: "n",
        method: :post)
    end.to raise_error(described_class::WarningError, /namespace not found/i)
  end

  it "raises on unknown warnings by default" do
    expect do
      object.send(:handle_openbao_warnings!, body("weird condition observed"), endpoint: "kv/data/x", namespace: "n",
        method: :get)
    end.to raise_error(described_class::WarningError)
  end

  it "can be relaxed if block-unknown disabled" do
    allow(object).to receive(:block_action_due_to_unknown_warning?).and_return(false)
    expect do
      object.send(:handle_openbao_warnings!, body("weird condition observed"), endpoint: "kv/data/x", namespace: "n",
        method: :get)
    end.not_to raise_error
  end

  context "when warning is method-specific" do
    it "treats 'requested namespace does not exist' as safe for read methods" do
      expect(Gitlab::AppLogger).to receive(:warn).with(hash_including(:safe_warnings))
      expect do
        object.send(:handle_openbao_warnings!, body("requested namespace does not exist"),
          endpoint: "sys/policies/acl", namespace: "n", method: :get)
      end.not_to raise_error
    end

    it "treats 'requested namespace does not exist' as safe for delete (idempotent)" do
      expect(Gitlab::AppLogger).to receive(:warn).with(hash_including(:safe_warnings))
      expect do
        object.send(:handle_openbao_warnings!, body("requested namespace does not exist"),
          endpoint: "sys/namespaces/user_1", namespace: "n", method: :delete)
      end.not_to raise_error
    end

    it "treats 'requested namespace does not exist' as critical for write methods" do
      expect do
        object.send(:handle_openbao_warnings!, body("requested namespace does not exist"),
          endpoint: "sys/namespaces/user_1", namespace: "n", method: :post)
      end.to raise_error(described_class::WarningError, /requested namespace does not exist/)
    end
  end

  describe "Sentry reporting" do
    # track_and_raise_exception is (exception, extra, tags), all positional. The
    # third slot is deliberately left empty: tags_payload runs no scrubbing, and
    # every other call site in the repo puts its context in extra.
    it "reports blocking warnings in the extra position and raises" do
      expect(Gitlab::ErrorTracking).to receive(:track_and_raise_exception) do |ex, extra, tags|
        expect(ex).to be_a(described_class::WarningError)
        expect(ex.message).to match(/namespace not found/i)
        expect(tags).to be_nil

        expect(extra).to include(
          subsystem: "openbao",
          operation: "kv/data",
          method: "post",
          namespace: "n",
          safe_warnings: be_a(Array),
          critical_warnings: be_a(Array),
          unknown_warnings: be_a(Array)
        )

        in_critical = extra[:critical_warnings].any? { |w| w =~ /namespace not found/i }
        in_unknown  = extra[:unknown_warnings].any? { |w| w =~ /namespace not found/i }
        expect(in_critical || in_unknown).to be(true)

        raise ex
      end

      expect do
        object.handle_openbao_warnings!(
          body("namespace not found"),
          endpoint: "kv/data/x",
          namespace: "n",
          method: :post
        )
      end.to raise_error(described_class::WarningError, /namespace not found/i)
    end

    it "keeps the secret name out of both the Sentry payload and the log line", :aggregate_failures do
      logged = nil
      tracked = nil
      tracked_tags = nil

      allow(Gitlab::AppLogger).to receive(:warn) { |payload| logged = payload }
      allow(Gitlab::ErrorTracking).to receive(:track_and_raise_exception) do |ex, extra, tags|
        tracked = extra
        tracked_tags = tags
        raise ex
      end

      expect do
        object.handle_openbao_warnings!(
          body("namespace not found"),
          endpoint: "user_1/secrets/kv/data/explicit/MY_DB_PASSWORD",
          namespace: "n",
          method: :post
        )
      end.to raise_error(described_class::WarningError)

      expect(logged.to_s).not_to include("MY_DB_PASSWORD")
      expect(tracked.to_s).not_to include("MY_DB_PASSWORD")
      expect(tracked_tags).to be_nil
      expect(logged).to include(operation: "kv/data")
      expect(tracked).to include(operation: "kv/data")
      expect(logged).to include(::Labkit::Fields::LOG_MESSAGE => "[OpenBao] warnings")
    end
  end
end
