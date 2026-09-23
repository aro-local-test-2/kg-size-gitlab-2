# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::ProvisionNamespaceService, feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  let_it_be_with_reload(:organization) { create(:organization) }
  let_it_be(:billing_group) { create(:group, organization: organization) }

  let(:slug) { 'my-slug' }
  let(:ar_namespace_id) { 'a1b2c3d4-0000-0000-0000-000000000000' }
  let(:ar_namespace) { instance_double(ArtifactRegistry::Namespace, id: ar_namespace_id) }
  let(:service_credential) { instance_double(ArtifactRegistry::ServiceCredential) }
  let(:client) { instance_double(ArtifactRegistry::Client) }

  subject(:execute) do
    described_class.new(organization: organization, slug: slug, service_credential: service_credential).execute
  end

  before do
    allow(ArtifactRegistry::Client).to receive(:new).with(service_credential: service_credential).and_return(client)
    allow(client).to receive(:provision_namespace).and_return(ar_namespace)
  end

  describe '#execute' do
    context 'with a valid slug and a single top-level group' do
      it 'calls AR with the slug and both derived anchors, then writes the mapping row', :aggregate_failures do
        expect { execute }.to change { organization.reload.artifact_registry_namespace_mapping }.from(nil)

        expect(client).to have_received(:provision_namespace).with(
          slug: slug,
          platform: 'gitlab',
          entity_type: 'organization',
          entity_id: organization.uuid,
          billing_entity_type: 'group',
          billing_entity_id: billing_group.id
        )

        mapping = organization.reload.artifact_registry_namespace_mapping
        expect(execute).to be_success
        expect(execute.payload[:namespace_mapping]).to eq(mapping)
        # The fetched namespace rides back on the payload so the caller reads its
        # status without a second AR call.
        expect(execute.payload[:ar_namespace]).to eq(ar_namespace)
        expect(mapping.ar_namespace_id).to eq(ar_namespace_id)
      end
    end

    context 'with the real client against a stubbed AR endpoint' do
      let(:base_url) { 'https://artifact-registry.example.test' }
      let(:service_token) { 'ar-service-token' }
      let(:service_credential) { ArtifactRegistry::ServiceCredential.new }
      let(:namespaces_url) { "#{base_url}/api/gitlab/v1/namespaces" }

      before do
        allow(ArtifactRegistry::Client).to receive(:new).and_call_original
        stub_config(artifact_registry: { api_url: base_url })
        allow(service_credential).to receive(:token).and_return(service_token)
      end

      it 'posts the derived anchors with the UUID owner id and writes the returned UUID', :aggregate_failures do
        request = stub_request(:post, namespaces_url)
          .with(
            headers: { ArtifactRegistry::Client::SERVICE_TOKEN_HEADER => service_token },
            body: hash_including(
              'slug' => slug,
              'platform' => 'gitlab',
              'entity_type' => 'organization',
              'entity_id' => organization.uuid,
              'billing_entity_type' => 'group',
              'billing_entity_id' => billing_group.id.to_s
            )
          )
          .to_return(
            status: 201,
            body: { 'id' => ar_namespace_id, 'slug' => slug }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        expect(execute).to be_success
        expect(request).to have_been_requested
        expect(organization.reload.artifact_registry_namespace_mapping.ar_namespace_id).to eq(ar_namespace_id)
      end

      # Criterion 2: an exact-anchor replay answers 200, not 201.
      it 'writes the row when AR replays with 200' do
        stub_request(:post, namespaces_url).to_return(
          status: 200,
          body: { 'id' => ar_namespace_id, 'slug' => slug }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

        expect(execute).to be_success
        expect(organization.reload.artifact_registry_namespace_mapping.ar_namespace_id).to eq(ar_namespace_id)
      end

      # Criterion 29 (service half): the real client reports before it raises.
      it 'lets the client report the typed exception before mapping the failure', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_request(:post, namespaces_url).to_return(status: 503)

        expect(execute).to be_error
        expect(execute.reason).to eq(:service_unavailable)
        expect(Gitlab::ErrorTracking).to have_received(:log_exception)
          .with(instance_of(ArtifactRegistry::Client::UnavailableError), anything)
      end

      # A malformed id casts to nil and fails presence on ar_namespace_id, not
      # organization uniqueness, so it must not be misread as a concurrency resolve.
      it 'raises rather than reporting :mapping_lost when AR returns a malformed id' do
        stub_request(:post, namespaces_url).to_return(
          status: 201,
          body: { 'id' => 'not-a-uuid', 'slug' => slug }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

        expect { execute }.to raise_error(ActiveRecord::RecordInvalid)
      end

      context 'when the service credential yields no token' do
        # The fail-closed ServiceCredential returns a nil token, so the client
        # raises AuthorizationError before any request; it must propagate.
        before do
          allow(service_credential).to receive(:token).and_return(nil)
        end

        it 'propagates the authorization error and issues no request', :aggregate_failures do
          request = stub_request(:post, namespaces_url)

          expect { execute }.to raise_error(ArtifactRegistry::Client::AuthorizationError)
          expect(request).not_to have_been_requested
        end
      end
    end

    # The second construction site takes the same default provider as the
    # CachesClient one, so both present the credential the deployment mounts
    # rather than disagreeing on what a service credential is.
    context 'with a real ServiceCredential reading the mounted secret' do
      let(:base_url) { 'https://artifact-registry.example.test' }
      let(:secret_file) { '/etc/gitlab/artifact-registry/.gitlab_artifact_registry_secret' }
      let(:namespaces_url) { "#{base_url}/api/gitlab/v1/namespaces" }
      let(:service_credential) { ArtifactRegistry::ServiceCredential.new }

      before do
        allow(ArtifactRegistry::Client).to receive(:new).and_call_original
        stub_config(artifact_registry: { api_url: base_url, service_token: { secret_file: secret_file } })
        stub_file_read(secret_file, content: "mounted-service-token\n")
      end

      it 'presents the mounted secret in the service-token header', :aggregate_failures do
        request = stub_request(:post, namespaces_url)
          .with(headers: { ArtifactRegistry::Client::SERVICE_TOKEN_HEADER => 'mounted-service-token' })
          .to_return(
            status: 201,
            body: { 'id' => ar_namespace_id, 'slug' => slug }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        expect(execute).to be_success
        expect(request).to have_been_requested
      end
    end

    context 'with no service credential injected' do
      it 'requires the keyword rather than inheriting a default provider' do
        expect { described_class.new(organization: organization, slug: slug) }
          .to raise_error(ArgumentError, /service_credential/)
      end
    end

    context 'when the organization already has a mapping' do
      let_it_be(:existing) { create(:artifact_registry_namespace_mapping, organization: organization) }

      it 'resolves to the existing mapping without calling AR', :aggregate_failures do
        expect { execute }.not_to change { ArtifactRegistry::NamespaceMapping.count }
        expect(execute).to be_success
        expect(execute.payload[:namespace_mapping]).to eq(existing)
        expect(client).not_to have_received(:provision_namespace)
      end

      context 'and the submitted slug is invalid' do
        let(:slug) { 'a' }

        it 'still resolves to the existing mapping rather than refusing the slug', :aggregate_failures do
          expect(execute).to be_success
          expect(execute.payload[:namespace_mapping]).to eq(existing)
          expect(client).not_to have_received(:provision_namespace)
        end
      end

      context 'and the organization now has several top-level groups' do
        before do
          create(:group, organization: organization)
        end

        it 'still resolves to the existing mapping rather than refusing the anchor', :aggregate_failures do
          expect(execute).to be_success
          expect(execute.payload[:namespace_mapping]).to eq(existing)
          expect(client).not_to have_received(:provision_namespace)
        end
      end
    end

    context 'when create! hits an already-persisted mapping' do
      # The model validation raises RecordInvalid on a sequential duplicate; the
      # DB index raises RecordNotUnique on a true race. The service must resolve
      # either to the stored row rather than erroring the caller.
      let_it_be(:winner) { create(:artifact_registry_namespace_mapping, organization: organization) }

      # A genuinely-invalid duplicate: validating it populates the
      # (:organization, :taken) error the service's rescue keys on.
      let(:duplicate) do
        build(:artifact_registry_namespace_mapping, organization: organization).tap(&:valid?)
      end

      let(:record_invalid) { ActiveRecord::RecordInvalid.new(duplicate) }
      let(:record_not_unique) { ActiveRecord::RecordNotUnique.new('duplicate key') }

      where(:case_name, :error) do
        [
          ['a sequential duplicate (RecordInvalid)', ref(:record_invalid)],
          ['a concurrent race (RecordNotUnique)', ref(:record_not_unique)]
        ]
      end

      with_them do
        before do
          # The initial association read saw no mapping, so the service reaches
          # create!; after it raises, reset re-reads and finds the stored row.
          allow(organization).to receive(:reset).and_return(organization)
          allow(organization).to receive(:artifact_registry_namespace_mapping).and_return(nil, winner)
          allow(ArtifactRegistry::NamespaceMapping).to receive(:create!).and_raise(error)
        end

        it 'resolves to the persisted row rather than erroring', :aggregate_failures do
          expect { execute }.not_to change { ArtifactRegistry::NamespaceMapping.count }
          expect(execute).to be_success
          expect(execute.payload[:namespace_mapping]).to eq(winner)
        end
      end
    end

    context 'when create! raises RecordInvalid for a reason other than the taken organization' do
      # A blank ar_namespace_id (e.g. a malformed AR id cast to nil) is a real
      # error, not a concurrency re-resolve, so it must not become :mapping_lost.
      let(:invalid_record) do
        build(:artifact_registry_namespace_mapping, organization: organization, ar_namespace_id: nil).tap(&:valid?)
      end

      before do
        allow(organization).to receive(:artifact_registry_namespace_mapping).and_return(nil)
        allow(ArtifactRegistry::NamespaceMapping).to receive(:create!)
          .and_raise(ActiveRecord::RecordInvalid.new(invalid_record))
      end

      it 're-raises rather than resolving' do
        expect { execute }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    context 'when the persisted row is gone before the post-conflict re-read' do
      before do
        # create! hits an existing row, but that row is deleted (e.g. a concurrent
        # deactivation) before reset re-reads, so the association reloads to nil.
        allow(ArtifactRegistry::NamespaceMapping).to receive(:create!)
          .and_raise(ActiveRecord::RecordNotUnique.new('duplicate key'))
        allow(organization).to receive_messages(reset: organization, artifact_registry_namespace_mapping: nil)
      end

      it 'returns a :mapping_lost error rather than a nil-mapping success', :aggregate_failures do
        expect(execute).to be_error
        expect(execute.reason).to eq(:mapping_lost)
      end
    end

    context 'when the slug breaks a syntactic rule' do
      let(:slug) { 'bad.slug' }

      it 'is refused with no client call', :aggregate_failures do
        expect(execute).to be_error
        expect(execute.reason).to eq(:invalid_slug)
        expect(client).not_to have_received(:provision_namespace)
        expect(ArtifactRegistry::NamespaceMapping.count).to eq(0)
      end
    end

    context 'when the organization has no top-level group' do
      let_it_be(:organization) { create(:organization) }

      it 'is refused with no client call', :aggregate_failures do
        expect(execute).to be_error
        expect(execute.reason).to eq(:no_billing_anchor)
        expect(client).not_to have_received(:provision_namespace)
      end
    end

    context 'when the organization has several top-level groups' do
      before do
        create(:group, organization: organization)
      end

      it 'is refused with no client call', :aggregate_failures do
        expect(execute).to be_error
        expect(execute.reason).to eq(:multiple_billing_anchors)
        expect(client).not_to have_received(:provision_namespace)
      end
    end

    context 'when AR returns a 409 conflict' do
      before do
        allow(client).to receive(:provision_namespace)
          .and_raise(ArtifactRegistry::Client::ApiError.new('slug already taken', status: 409, code: 'conflict'))
      end

      it 'surfaces the conflict and writes no row', :aggregate_failures do
        expect { execute }.not_to change { ArtifactRegistry::NamespaceMapping.count }
        expect(execute).to be_error
        expect(execute.reason).to eq(:conflict)
      end
    end

    context 'when AR returns a 422 validation error' do
      before do
        allow(client).to receive(:provision_namespace)
          .and_raise(ArtifactRegistry::Client::ApiError.new('entity_id is invalid', status: 422))
      end

      it 'surfaces the error and writes no row', :aggregate_failures do
        expect { execute }.not_to change { ArtifactRegistry::NamespaceMapping.count }
        expect(execute).to be_error
        expect(execute.reason).to eq(:unprocessable)
      end
    end

    context 'when AR returns another API error the client surfaces as ApiError' do
      # 400 is a reachable ApiError; the client routes 429 and 5xx to UnavailableError.
      before do
        allow(client).to receive(:provision_namespace)
          .and_raise(ArtifactRegistry::Client::ApiError.new('bad request', status: 400))
      end

      it 'falls back to :api_error and writes no row', :aggregate_failures do
        expect { execute }.not_to change { ArtifactRegistry::NamespaceMapping.count }
        expect(execute).to be_error
        expect(execute.reason).to eq(:api_error)
      end
    end

    context 'when AR is unavailable' do
      before do
        allow(client).to receive(:provision_namespace)
          .and_raise(ArtifactRegistry::Client::UnavailableError.new('service unavailable', status: 503))
      end

      it 'surfaces :service_unavailable and writes no row', :aggregate_failures do
        expect { execute }.not_to change { ArtifactRegistry::NamespaceMapping.count }
        expect(execute).to be_error
        expect(execute.reason).to eq(:service_unavailable)
      end
    end

    context 'when the client raises an authorization error' do
      before do
        allow(client).to receive(:provision_namespace)
          .and_raise(ArtifactRegistry::Client::AuthorizationError.new('no credential', status: 401))
      end

      # Deliberate: 401/403 propagate as a top-level error so the Step 5 mutation
      # renders resource-not-available per the S03 convention, rather than the
      # service swallowing them into a recoverable payload error.
      it 'lets the authorization error propagate and writes no row', :aggregate_failures do
        expect { execute }.to raise_error(ArtifactRegistry::Client::AuthorizationError)
        expect(ArtifactRegistry::NamespaceMapping.count).to eq(0)
      end
    end

    context 'when logging the request and the returned UUID' do
      let(:logger) { instance_double(ArtifactRegistry::Logger) }

      before do
        allow(ArtifactRegistry::Logger).to receive(:build).and_return(logger)
        allow(logger).to receive(:info)
      end

      it 'writes both entries with the standard fields, including the slug', :aggregate_failures do
        execute

        expect(logger).to have_received(:info).with(
          hash_including(
            message: 'provision_namespace request',
            slug: slug,
            Labkit::Fields::CLASS_NAME => described_class.name,
            Labkit::Fields::GL_ORGANIZATION_ID => organization.id,
            Labkit::Fields::GL_ROOT_NAMESPACE_ID => billing_group.id
          )
        )
        expect(logger).to have_received(:info).with(
          hash_including(
            message: 'provision_namespace response',
            Labkit::Fields::CLASS_NAME => described_class.name,
            Labkit::Fields::GL_ORGANIZATION_ID => organization.id,
            ar_namespace_id: ar_namespace_id
          )
        )
      end

      context 'when the row write then fails' do
        before do
          allow(ArtifactRegistry::NamespaceMapping).to receive(:create!)
            .and_raise(ActiveRecord::StatementInvalid, 'boom')
        end

        # Criterion 8: the request and returned-UUID logs are the lost-write
        # recovery record, so both must already be written when the write fails.
        it 'has written both entries before the failed write', :aggregate_failures do
          expect { execute }.to raise_error(ActiveRecord::StatementInvalid)

          expect(logger).to have_received(:info).with(hash_including(message: 'provision_namespace request'))
          expect(logger).to have_received(:info).with(hash_including(message: 'provision_namespace response'))
        end
      end
    end
  end
end
