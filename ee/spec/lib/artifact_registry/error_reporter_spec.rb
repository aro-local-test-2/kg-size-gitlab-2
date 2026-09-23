# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::ErrorReporter, feature_category: :artifact_registry do
  let(:origin) { 'https://artifact-registry.example.test' }
  let(:correlation_id) { 'corr-123' }
  let(:sentinel_token) { 'sentinel-bearer-token-value' }

  subject(:reporter) { described_class.new }

  before do
    allow(Gitlab::ErrorTracking).to receive(:log_exception)
  end

  describe '#report_terminal' do
    let(:terminal_arguments) do
      {
        error_class: ArtifactRegistry::Client::UnavailableError,
        message: 'Artifact Registry request failed',
        url: origin,
        method: :get,
        correlation_id: correlation_id,
        status: 503,
        request_id: 'req-1'
      }
    end

    it 'makes exactly one direct log_exception delivery' do
      reporter.report_terminal(**terminal_arguments)

      expect(Gitlab::ErrorTracking).to have_received(:log_exception).once.with(
        instance_of(ArtifactRegistry::Client::UnavailableError),
        { url: origin, method: :get, status: 503, request_id: 'req-1', correlation_id: correlation_id }
      )
    end

    it 'returns an operational exception sharing class, message, status and request_id', :aggregate_failures do
      result = reporter.report_terminal(**terminal_arguments)

      expect(result).to be_a(ArtifactRegistry::Client::UnavailableError)
      expect(result.message).to eq('Artifact Registry request failed')
      expect(result.status).to eq(503)
      expect(result.request_id).to eq('req-1')
    end

    it 'logs a frozen context with exactly the allowlisted keys', :aggregate_failures do
      reporter.report_terminal(**terminal_arguments)

      context = nil
      expect(Gitlab::ErrorTracking).to have_received(:log_exception) { |_e, ctx| context = ctx }
      expect(context).to be_frozen
      expect(context.keys).to match_array([:url, :method, :status, :request_id, :correlation_id])
    end

    it 'logs an instance distinct from the returned operational exception', :aggregate_failures do
      result = reporter.report_terminal(**terminal_arguments)

      logged = nil
      expect(Gitlab::ErrorTracking).to have_received(:log_exception) { |e, _ctx| logged = e }
      expect(logged).not_to equal(result)
      expect(logged.message).to eq(result.message)
      expect(logged.status).to eq(result.status)
      expect(logged.request_id).to eq(result.request_id)
      expect(logged.cause).to be_nil
    end

    context 'for a transport outcome with no status or request_id' do
      let(:terminal_arguments) do
        {
          error_class: ArtifactRegistry::Client::UnavailableError,
          message: 'Artifact Registry request failed',
          url: origin,
          method: :get,
          correlation_id: correlation_id
        }
      end

      it 'omits the status and request_id keys entirely' do
        reporter.report_terminal(**terminal_arguments)

        expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
          instance_of(ArtifactRegistry::Client::UnavailableError),
          { url: origin, method: :get, correlation_id: correlation_id }
        )
      end
    end

    it 'redacts a bearer credential from the delivered and returned messages', :aggregate_failures do
      result = reporter.report_terminal(
        error_class: ArtifactRegistry::Client::UnavailableError,
        message: "request with Bearer #{sentinel_token} failed",
        url: origin,
        method: :get,
        correlation_id: correlation_id
      )

      expect(result.message).not_to include(sentinel_token)
      expect(Gitlab::ErrorTracking).to have_received(:log_exception) do |exception, context|
        expect(exception.message).not_to include(sentinel_token)
        expect(context.values.join).not_to include(sentinel_token)
      end
    end
  end

  describe '#report_attempt' do
    let(:raw_cause) { StandardError.new("env leak with Bearer #{sentinel_token}") }

    let(:transport_exception) do
      begin
        raise raw_cause
      rescue StandardError
        raise Faraday::ConnectionFailed, "connect failed for Bearer #{sentinel_token}"
      end
    rescue Faraday::ConnectionFailed => e
      e
    end

    it 'logs a sanitized same-class exception with the allowlisted context', :aggregate_failures do
      reporter.report_attempt(transport_exception, url: origin, method: :get, correlation_id: correlation_id)

      expect(Gitlab::ErrorTracking).to have_received(:log_exception) do |exception, context|
        expect(exception).to be_a(Faraday::ConnectionFailed)
        expect(exception).not_to equal(transport_exception)
        expect(exception.cause).to be_nil
        expect(exception.message).not_to include(sentinel_token)
        expect(context).to be_frozen
        expect(context.keys).to match_array([:url, :method, :correlation_id])
        expect(context.values.join).not_to include(sentinel_token)
      end
    end
  end

  describe '#log' do
    let(:exception) { ArtifactRegistry::Client::ApiError.new('not found', status: 404, code: 'not_found') }

    it 'keeps the allowlisted context the caller assembled', :aggregate_failures do
      context = { uuid: 'uuid-1', correlation_id: correlation_id, request_id: 'req-1', status: 404 }

      reporter.log(exception, context)

      expect(Gitlab::ErrorTracking).to have_received(:log_exception)
        .with(instance_of(ArtifactRegistry::Client::ApiError), context)
    end

    it 'drops a context key outside the allowlist' do
      reporter.log(exception, { uuid: 'uuid-1', authorization: 'Bearer plain-token' })

      expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(anything, { uuid: 'uuid-1' })
    end

    it 'keeps the manifest digest, which a manifest read logs beside its image id' do
      reporter.log(exception, { id: 'img-1', digest: 'sha256:abc' })

      expect(Gitlab::ErrorTracking).to have_received(:log_exception)
        .with(anything, { id: 'img-1', digest: 'sha256:abc' })
    end

    it 'redacts a credential in the exception message' do
      poisoned = ArtifactRegistry::Client::Error.new('parse failed for Bearer plain-token')

      reporter.log(poisoned, { uuid: 'uuid-1' })

      expect(Gitlab::ErrorTracking).to have_received(:log_exception) do |logged, _context|
        expect(logged.message).to eq('parse failed for Bearer [REDACTED]')
      end
    end

    it 'preserves the typed attributes and the backtrace', :aggregate_failures do
      exception.set_backtrace(['ee/lib/artifact_registry/client.rb:1:in `run\''])

      reporter.log(exception, { uuid: 'uuid-1' })

      expect(Gitlab::ErrorTracking).to have_received(:log_exception) do |logged, _context|
        expect(logged.status).to eq(404)
        expect(logged.code).to eq('not_found')
        expect(logged.backtrace).to eq(exception.backtrace)
      end
    end
  end

  describe '#redact' do
    let(:service_token) { 'bare-service-token-value' }

    context 'with a service token to scrub' do
      subject(:reporter) { described_class.new(service_token: service_token) }

      it 'scrubs the bare service token an intermediary echoed back' do
        expect(reporter.redact("AR rejected #{service_token} on /namespaces"))
          .to eq('AR rejected [REDACTED] on /namespaces')
      end
    end

    context 'without a service token' do
      it 'still redacts a bearer credential' do
        expect(reporter.redact('request with Bearer leaked-bearer failed'))
          .to eq('request with Bearer [REDACTED] failed')
      end
    end

    context 'with a JWT-shaped token' do
      it 'redacts a three-segment token with 16+ chars per segment' do
        jwt = 'not-a-real-jwt-000.not-a-real-jwt-111.not-a-real-jwt-222'

        expect(reporter.redact("token #{jwt} rejected")).to eq('token [REDACTED] rejected')
      end
    end

    context 'with the dotted content an AR error is made of' do
      # These are the modal shapes of a package-registry error, and none is a
      # credential. Redacting them was the over-match the JWT length floor removes.
      it 'leaves versioned filenames, versions, coordinates, hostnames, and IPs alone', :aggregate_failures do
        {
          'artifact mylib-1.2.3.jar not found' => 'artifact mylib-1.2.3.jar not found',
          'package numpy-1.26.4-cp311-none-any.whl rejected' => 'package numpy-1.26.4-cp311-none-any.whl rejected',
          'requires v1.2.3 or later' => 'requires v1.2.3 or later',
          'requires 1.2.3.RELEASE' => 'requires 1.2.3.RELEASE',
          'package com.example.my-lib not found' => 'package com.example.my-lib not found',
          'could not reach artifact-registry.example.test' => 'could not reach artifact-registry.example.test',
          'upstream 10.0.0.1.nip.io refused' => 'upstream 10.0.0.1.nip.io refused',
          'see file.name.txt for details' => 'see file.name.txt for details'
        }.each do |input, expected|
          expect(reporter.redact(input)).to eq(expected)
        end
      end
    end

    context 'with a service token that AR echoes percent-encoded' do
      # A real token may hold spaces, slashes, and plus signs (VALID_TOKEN_CHARS),
      # which AR percent-encodes when it echoes the credential back. Both the raw
      # and the encoded form are scrubbed by exact match.
      subject(:reporter) { described_class.new(service_token: 'svc token/value+x') }

      it 'redacts the token in its raw and percent-encoded forms', :aggregate_failures do
        expect(reporter.redact('AR rejected svc token/value+x here')).to eq('AR rejected [REDACTED] here')
        expect(reporter.redact('AR rejected svc%20token%2Fvalue%2Bx here')).to eq('AR rejected [REDACTED] here')
      end

      it 'leaves a first-party encoded URL path intact' do
        expect(reporter.redact('logged https://ar.test/v1/foo%2Fbar%20baz/repositories done'))
          .to eq('logged https://ar.test/v1/foo%2Fbar%20baz/repositories done')
      end
    end
  end
end
