# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::ServiceCredential, feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  subject(:credential) { described_class.new }

  let(:secret_file) { '/etc/gitlab/artifact-registry/.gitlab_artifact_registry_secret' }

  describe '#token' do
    it 'takes no arguments' do
      expect(described_class.instance_method(:token).arity).to eq(0)
    end

    context 'when secret_file is not configured' do
      before do
        stub_config(artifact_registry: { api_url: 'https://artifact-registry.example.com' })
      end

      it 'returns nil so the client fails closed' do
        expect(credential.token).to be_nil
      end

      it 'reads no file' do
        expect_file_not_to_read(secret_file)

        credential.token
      end
    end

    context 'when secret_file is configured' do
      before do
        stub_config(artifact_registry: {
          api_url: 'https://artifact-registry.example.com',
          service_token: { secret_file: secret_file }
        })
      end

      context 'when the file holds a secret' do
        before do
          stub_file_read(secret_file, content: "ar-service-token\n")
        end

        it 'returns the chomped contents' do
          expect(credential.token).to eq('ar-service-token')
        end

        it 'reads the file once per instance' do
          # An RSpec message expectation is exactly-once by default, so a second
          # read on the memoized call fails this.
          expect_file_read(secret_file, content: "ar-service-token\n")

          2.times { credential.token }
        end

        it 'reads the file again for a second instance' do
          # Pins the memoization as per-instance, not per-process: a rotated
          # secret is picked up by the next instance, one per request.
          expect(File).to receive(:read).with(secret_file).twice.and_return("ar-service-token\n")

          described_class.new.token
          described_class.new.token
        end
      end

      context 'when the configured file cannot be read' do
        # Fail-loud, not fail-closed: a broken mount is an operator mistake.
        # Re-raised as the client's typed AuthorizationError, with the Errno
        # chained as the cause, so the client's caching/503 machinery engages
        # instead of an untyped 500.
        [Errno::ENOENT, Errno::EACCES].each do |error|
          it "raises AuthorizationError caused by #{error} rather than resolving to nil" do
            allow(File).to receive(:read).with(secret_file).and_raise(error)

            expect { credential.token }.to raise_error(ArtifactRegistry::Client::AuthorizationError) do |raised|
              expect(raised.cause).to be_a(error)
            end
          end
        end
      end

      context 'when the file is empty' do
        before do
          stub_file_read(secret_file, content: "\n")
        end

        it 'returns nil rather than a blank credential' do
          expect(credential.token).to be_nil
        end
      end

      context 'when the file holds only whitespace' do
        before do
          stub_file_read(secret_file, content: "   \n")
        end

        it 'returns nil rather than a blank credential' do
          expect(credential.token).to be_nil
        end
      end

      # A wrong file mounted at the path: reject at the credential boundary
      # rather than send junk on the wire or raise opaquely inside Net::HTTP.
      context 'when the file holds characters invalid in an HTTP header' do
        where(:case_name, :content) do
          [
            ['a CR/LF', "tok\r\nX-Injected: 1\n"],
            ['an inner newline', "tok\nen\n"],
            ['a NUL byte', "tok\x00en\n"],
            ['a non-ASCII byte', "t\u00f6ken\n"]
          ]
        end

        with_them do
          before do
            stub_file_read(secret_file, content: content)
          end

          it 'raises AuthorizationError rather than returning the value' do
            expect { credential.token }
              .to raise_error(ArtifactRegistry::Client::AuthorizationError, /invalid characters/)
          end
        end
      end
    end
  end
end
