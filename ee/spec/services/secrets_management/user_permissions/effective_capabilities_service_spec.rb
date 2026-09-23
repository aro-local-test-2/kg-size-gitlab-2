# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SecretsManagement::UserPermissions::EffectiveCapabilitiesService,
  feature_category: :secrets_management do
  # Concrete subclass used to exercise the base class without a live OpenBao.
  let(:concrete_service_class) do
    Class.new(described_class) do
      attr_writer :stubbed_client

      private

      def user_scoped_client
        @stubbed_client
      end
    end
  end

  let_it_be(:project) { create(:project) }
  let_it_be(:secrets_manager) { create(:project_secrets_manager, project: project) }
  let_it_be(:current_user) { create(:user) }

  let(:client_double) { instance_double(SecretsManagement::SecretsManagerClient) }

  let(:data_path) { secrets_manager.ci_full_path('*') }
  let(:detailed_metadata_path) { secrets_manager.detailed_metadata_path('*') }

  subject(:service) do
    svc = concrete_service_class.new(
      secrets_manager: secrets_manager,
      current_user: current_user,
      resource: project
    )
    svc.stubbed_client = client_double
    svc
  end

  # OpenBao returns the per-path capability map under the "data" envelope.
  # readMetadata is derived from `list` on the detailed-metadata path, which is
  # the path the secrets list service actually reads.
  def stub_capabilities_self(data_caps:, detailed_metadata_caps:)
    allow(client_double).to receive(:capabilities_self)
      .with(paths: [data_path, detailed_metadata_path])
      .and_return(capabilities_response(data_caps: data_caps, detailed_metadata_caps: detailed_metadata_caps))
  end

  def capabilities_response(data_caps:, detailed_metadata_caps:)
    { "data" => { data_path => data_caps, detailed_metadata_path => detailed_metadata_caps } }
  end

  describe '#execute' do
    # Isolate the OpenBao-only mapping tests from the entitlement layer.
    # Contexts that specifically exercise the entitlement gates re-enable the
    # flag explicitly.
    before do
      stub_feature_flags(secrets_manager_paid_experience: false)
    end

    context 'when the user has no grant (empty capabilities)' do
      before do
        stub_capabilities_self(data_caps: ['deny'], detailed_metadata_caps: ['deny'])
      end

      it 'returns false for all capabilities' do
        result = service.execute

        expect(result).to eq('read_metadata' => false, 'create' => false, 'update' => false, 'delete' => false)
      end
    end

    context 'when the user has a read-only grant' do
      before do
        stub_capabilities_self(data_caps: [], detailed_metadata_caps: %w[list])
      end

      it 'returns read=true and others false' do
        result = service.execute

        expect(result).to eq('read_metadata' => true, 'create' => false, 'update' => false, 'delete' => false)
      end
    end

    context 'when the user has a read+write grant' do
      before do
        stub_capabilities_self(data_caps: %w[create update], detailed_metadata_caps: %w[list])
      end

      it 'returns read/create/update=true and delete=false' do
        result = service.execute

        expect(result).to eq('read_metadata' => true, 'create' => true, 'update' => true, 'delete' => false)
      end
    end

    context 'when the user has a full-access grant' do
      before do
        stub_capabilities_self(data_caps: %w[create update delete], detailed_metadata_caps: %w[list])
      end

      it 'returns true for all capabilities' do
        result = service.execute

        expect(result).to eq('read_metadata' => true, 'create' => true, 'update' => true, 'delete' => true)
      end
    end

    context 'when capabilities_self returns nil (no policies)' do
      before do
        allow(client_double).to receive(:capabilities_self)
          .with(paths: [data_path, detailed_metadata_path])
          .and_return(nil)
      end

      it 'returns false for all capabilities' do
        result = service.execute

        expect(result).to eq('read_metadata' => false, 'create' => false, 'update' => false, 'delete' => false)
      end
    end

    context 'when OpenBao raises ApiError' do
      before do
        allow(client_double).to receive(:capabilities_self).and_raise(
          SecretsManagement::SecretsManagerClient::ApiError, 'connection refused'
        )
      end

      it 'returns false for all capabilities (fail closed)' do
        result = service.execute

        expect(result).to eq('read_metadata' => false, 'create' => false, 'update' => false, 'delete' => false)
      end
    end

    context 'when OpenBao raises ConnectionError' do
      before do
        allow(client_double).to receive(:capabilities_self).and_raise(
          SecretsManagement::SecretsManagerClient::ConnectionError, 'timeout'
        )
      end

      it 'returns false for all capabilities (fail closed)' do
        result = service.execute

        expect(result).to eq('read_metadata' => false, 'create' => false, 'update' => false, 'delete' => false)
      end
    end

    context 'when OpenBao raises ServiceUnavailableError' do
      before do
        allow(client_double).to receive(:capabilities_self).and_raise(
          SecretsManagement::SecretsManagerClient::ServiceUnavailableError, 'service unavailable'
        )
      end

      it 'returns false for all capabilities (fail closed)' do
        result = service.execute

        expect(result).to eq('read_metadata' => false, 'create' => false, 'update' => false, 'delete' => false)
      end
    end

    context 'when OpenBao raises AuthenticationError' do
      before do
        allow(client_double).to receive(:capabilities_self).and_raise(
          SecretsManagement::SecretsManagerClient::AuthenticationError, 'auth failed'
        )
      end

      it 'returns false for all capabilities (fail closed)' do
        result = service.execute

        expect(result).to eq('read_metadata' => false, 'create' => false, 'update' => false, 'delete' => false)
      end
    end

    describe 'Sentry reporting' do
      def stub_capabilities_error(error_class, message)
        allow(client_double).to receive(:capabilities_self).and_raise(error_class, message)
      end

      # The factory leaves the secrets manager in its initial `provisioning`
      # state, so reporting has to be opted into here.
      before do
        allow(secrets_manager).to receive(:active?).and_return(true)
      end

      context 'when the secrets manager is still provisioning' do
        before do
          allow(secrets_manager).to receive(:active?).and_return(false)
          stub_capabilities_error(
            SecretsManagement::SecretsManagerClient::ApiError, 'openbao is unreachable'
          )
        end

        it 'stays quiet, because the user auth mount does not exist yet' do
          expect(::SecretsManagement::ThrottledErrorTracking).not_to receive(:track_exception)

          expect(service.execute).to eq(
            'read_metadata' => false, 'create' => false, 'update' => false, 'delete' => false
          )
        end
      end

      [
        SecretsManagement::SecretsManagerClient::ApiError,
        SecretsManagement::SecretsManagerClient::ConnectionError,
        SecretsManagement::SecretsManagerClient::ServiceUnavailableError,
        SecretsManagement::SecretsManagerClient::AuthenticationError
      ].each do |error_class|
        context "when OpenBao raises #{error_class}" do
          before do
            stub_capabilities_error(error_class, 'openbao is unreachable')
          end

          # Throttled: the sidebar re-runs this rescue on every page render while OpenBao is down.
          it 'reports the failure through the throttled tracker, and still fails closed' do
            expect(::SecretsManagement::ThrottledErrorTracking).to receive(:track_exception).with(
              an_instance_of(error_class),
              throttle_key: :effective_capabilities_fail_closed,
              gl_namespace_id: project.root_ancestor.id
            )

            expect(service.execute).to eq(
              'read_metadata' => false, 'create' => false, 'update' => false, 'delete' => false
            )
          end
        end
      end

      # Every CEL refusal branch is a JWT or role mismatch. A user who simply has
      # no grant is not one of them: OpenBao answers that with a successful
      # response listing `deny`, which never reaches this rescue.
      context 'when the CEL login is refused' do
        before do
          stub_capabilities_error(
            SecretsManagement::SecretsManagerClient::ApiError,
            "error executing cel program: CEL role 'project_7/users/direct/app' " \
              'blocked authorization with message: audience validation failed'
          )
        end

        it 'reports it' do
          expect(::SecretsManagement::ThrottledErrorTracking).to receive(:track_exception).with(
            an_instance_of(SecretsManagement::SecretsManagerClient::ApiError),
            hash_including(gl_namespace_id: project.root_ancestor.id)
          )

          service.execute
        end
      end
    end

    context 'when data path has delete without create or update' do
      before do
        stub_capabilities_self(data_caps: %w[delete], detailed_metadata_caps: %w[list])
      end

      it 'returns delete=true, create=false, update=false, read=true' do
        result = service.execute

        expect(result).to eq('read_metadata' => true, 'create' => false, 'update' => false, 'delete' => true)
      end
    end

    context 'when data path has update without create' do
      before do
        stub_capabilities_self(data_caps: %w[update], detailed_metadata_caps: %w[list])
      end

      it 'returns update=true, create=false, delete=false, read=true' do
        result = service.execute

        expect(result).to eq('read_metadata' => true, 'create' => false, 'update' => true, 'delete' => false)
      end
    end

    context 'when response contains unknown/extra capabilities (sudo, root)' do
      before do
        stub_capabilities_self(data_caps: %w[create sudo root], detailed_metadata_caps: %w[list root])
      end

      it 'ignores unknown capabilities and only maps the four known booleans' do
        result = service.execute

        expect(result).to eq('read_metadata' => true, 'create' => true, 'update' => false, 'delete' => false)
      end
    end

    context 'when response contains list on the data path' do
      before do
        stub_capabilities_self(data_caps: %w[create list], detailed_metadata_caps: %w[list])
      end

      it 'does not leak list on data path into the read boolean' do
        result = service.execute

        # read is derived from the detailed-metadata path only; list on data_path is ignored
        expect(result).to eq('read_metadata' => true, 'create' => true, 'update' => false, 'delete' => false)
      end
    end

    context 'when response is missing the detailed-metadata path key' do
      before do
        allow(client_double).to receive(:capabilities_self)
          .with(paths: [data_path, detailed_metadata_path])
          .and_return({ "data" => { data_path => %w[create update delete] } })
      end

      it 'returns read=false and data caps resolved from data path' do
        result = service.execute

        expect(result).to eq('read_metadata' => false, 'create' => true, 'update' => true, 'delete' => true)
      end
    end

    context 'when response is missing the data path key' do
      before do
        allow(client_double).to receive(:capabilities_self)
          .with(paths: [data_path, detailed_metadata_path])
          .and_return({ "data" => { detailed_metadata_path => %w[list] } })
      end

      it 'returns read=true and all data caps false' do
        result = service.execute

        expect(result).to eq('read_metadata' => true, 'create' => false, 'update' => false, 'delete' => false)
      end
    end

    context 'when the entitlement layer denies writes but permits reads (:blocked)' do
      # Guards against the "button shown for an action the user can't perform"
      # regression: OpenBao may grant write capability but the mutation-side
      # `EnforcesWriteEntitlement` will reject it, so we must not report those
      # writes as available on `userPermissions`. `:blocked` still permits
      # reads so `read_metadata` stays true.
      let_it_be(:root_group) { create(:group) }
      let_it_be(:project) { create(:project, group: root_group) }
      let_it_be(:secrets_manager) { create(:project_secrets_manager, project: project) }

      before do
        stub_feature_flags(secrets_manager_paid_experience: true)
        stub_capabilities_self(data_caps: %w[create update delete], detailed_metadata_caps: %w[list])
        allow(::SecretsManagement::Entitlement).to receive(:for).and_return(
          ::SecretsManagement::Entitlement.new(state: :blocked, blocked_reason: :grace)
        )
      end

      it 'zeroes out create and update while leaving reads and deletes intact' do
        result = service.execute

        expect(result).to eq(
          'read_metadata' => true,
          'create' => false,
          'update' => false,
          'delete' => true
        )
      end
    end

    context 'when the beta cohort window has closed (trial_eligible after the beta program ended)' do
      let_it_be(:root_group) { create(:group) }
      let_it_be(:project) { create(:project, group: root_group) }
      let_it_be(:secrets_manager) { create(:project_secrets_manager, project: project) }

      before do
        stub_feature_flags(secrets_manager_paid_experience: true)
        stub_capabilities_self(data_caps: %w[create update delete], detailed_metadata_caps: %w[list])
        allow(::SecretsManagement::Entitlement).to receive(:for).and_return(
          ::SecretsManagement::Entitlement.new(
            state: :trial_eligible, beta_window_eligible: true, beta_program_ended: true
          )
        )
      end

      it 'keeps reads and deletes so the cohort can clean up' do
        expect(service.execute).to eq(
          'read_metadata' => true,
          'create' => false,
          'update' => false,
          'delete' => true
        )
      end
    end

    context 'when the entitlement is trial_eligible outside the beta cohort' do
      let_it_be(:root_group) { create(:group) }
      let_it_be(:project) { create(:project, group: root_group) }
      let_it_be(:secrets_manager) { create(:project_secrets_manager, project: project) }

      before do
        stub_feature_flags(secrets_manager_paid_experience: true)
        stub_capabilities_self(data_caps: %w[create update delete], detailed_metadata_caps: %w[list])
        allow(::SecretsManagement::Entitlement).to receive(:for).and_return(
          ::SecretsManagement::Entitlement.new(state: :trial_eligible)
        )
      end

      # The policy hides projects in this state, so this only matters for root groups
      # showing the trial call to action, where deletes follow reads.
      it 'keeps deletes with reads while denying create and update' do
        expect(service.execute).to eq(
          'read_metadata' => true,
          'create' => false,
          'update' => false,
          'delete' => true
        )
      end
    end

    context 'when the database is read-only (strict read-only mode)' do
      let_it_be(:root_group) { create(:group) }
      let_it_be(:project) { create(:project, group: root_group) }
      let_it_be(:secrets_manager) { create(:project_secrets_manager, project: project) }

      before do
        stub_capabilities_self(data_caps: %w[create update delete], detailed_metadata_caps: %w[list])
        allow(::Gitlab::Database).to receive(:read_only?).and_return(true)
      end

      it 'zeroes out every write including delete while leaving reads intact' do
        result = service.execute

        expect(result).to eq(
          'read_metadata' => true,
          'create' => false,
          'update' => false,
          'delete' => false
        )
      end

      it 'wins over a paid entitlement' do
        stub_feature_flags(secrets_manager_paid_experience: true)
        allow(::SecretsManagement::Entitlement).to receive(:for).and_return(
          ::SecretsManagement::Entitlement.new(state: :paid)
        )

        expect(service.execute).to eq(
          'read_metadata' => true,
          'create' => false,
          'update' => false,
          'delete' => false
        )
      end
    end

    context 'when the entitlement layer denies reads (:ineligible)' do
      # :ineligible is the one state where `permits_read?` is false. The policy
      # layer already prevents the secrets list query there, so `read_metadata`
      # must not claim the list is readable even when a leftover OpenBao grant
      # exists.
      let_it_be(:root_group) { create(:group) }
      let_it_be(:project) { create(:project, group: root_group) }
      let_it_be(:secrets_manager) { create(:project_secrets_manager, project: project) }

      before do
        stub_feature_flags(secrets_manager_paid_experience: true)
        stub_capabilities_self(data_caps: %w[create update delete], detailed_metadata_caps: %w[list])
        allow(::SecretsManagement::Entitlement).to receive(:for).and_return(
          ::SecretsManagement::Entitlement.new(state: :ineligible)
        )
      end

      it 'returns false for all capabilities' do
        result = service.execute

        expect(result).to eq(
          'read_metadata' => false,
          'create' => false,
          'update' => false,
          'delete' => false
        )
      end
    end

    context 'when the entitlement layer permits reads and writes' do
      let_it_be(:root_group) { create(:group) }
      let_it_be(:project) { create(:project, group: root_group) }
      let_it_be(:secrets_manager) { create(:project_secrets_manager, project: project) }

      before do
        stub_feature_flags(secrets_manager_paid_experience: true)
        stub_capabilities_self(data_caps: %w[create update delete], detailed_metadata_caps: %w[list])
        allow(::SecretsManagement::Entitlement).to receive(:for).and_return(
          ::SecretsManagement::Entitlement.new(state: :paid)
        )
      end

      it 'returns the OpenBao capabilities unchanged' do
        result = service.execute

        expect(result).to eq(
          'read_metadata' => true,
          'create' => true,
          'update' => true,
          'delete' => true
        )
      end
    end

    # The controller and the GraphQL resolver run in separate requests, so these
    # exercise a second service instance rather than a second call on one.
    context 'when caching the OpenBao lookup', :use_clean_rails_memory_store_caching do
      let_it_be(:other_user) { create(:user) }

      let(:other_client_double) { instance_double(SecretsManagement::SecretsManagerClient) }

      let(:cache_key) do
        [
          'secrets_management', 'effective_capabilities', described_class::CACHE_VERSION,
          'project', secrets_manager.id, current_user.id
        ]
      end

      def build_service(user: current_user, client: client_double, manager: secrets_manager, resource: project)
        svc = concrete_service_class.new(
          secrets_manager: manager,
          current_user: user,
          resource: resource
        )
        svc.stubbed_client = client
        svc
      end

      it 'queries OpenBao once and serves the second instance from the cache', :aggregate_failures do
        expect(client_double).to receive(:capabilities_self).once
          .with(paths: [data_path, detailed_metadata_path])
          .and_return(capabilities_response(data_caps: %w[create], detailed_metadata_caps: %w[list]))

        first = build_service.execute
        second = build_service.execute

        expect(first).to eq('read_metadata' => true, 'create' => true, 'update' => false, 'delete' => false)
        expect(second).to eq(first)
      end

      it 'stores the pre-entitlement OpenBao capabilities under a key scoped to the resource and user' do
        stub_capabilities_self(data_caps: [], detailed_metadata_caps: %w[list])

        build_service.execute

        expect(Rails.cache.read(cache_key)).to eq(
          'read_metadata' => true, 'create' => false, 'update' => false, 'delete' => false
        )
      end

      it 'queries OpenBao again once the entry has expired' do
        expect(client_double).to receive(:capabilities_self).twice
          .with(paths: [data_path, detailed_metadata_path])
          .and_return(capabilities_response(data_caps: [], detailed_metadata_caps: %w[list]))

        build_service.execute

        travel_to(described_class::CACHE_TTL.from_now + 1.second) do
          build_service.execute
        end
      end

      it 'does not cache a failed lookup', :aggregate_failures do
        allow(client_double).to receive(:capabilities_self).and_raise(
          SecretsManagement::SecretsManagerClient::ConnectionError, 'timeout'
        )

        expect(build_service.execute).to eq(
          'read_metadata' => false, 'create' => false, 'update' => false, 'delete' => false
        )
        expect(Rails.cache.read(cache_key)).to be_nil
      end

      it 'does not serve one user the capabilities of another', :aggregate_failures do
        allow(client_double).to receive(:capabilities_self)
          .and_return(capabilities_response(data_caps: %w[create], detailed_metadata_caps: %w[list]))
        allow(other_client_double).to receive(:capabilities_self)
          .and_return(capabilities_response(data_caps: [], detailed_metadata_caps: []))

        expect(build_service.execute).to eq(
          'read_metadata' => true, 'create' => true, 'update' => false, 'delete' => false
        )
        expect(build_service(user: other_user, client: other_client_double).execute).to eq(
          'read_metadata' => false, 'create' => false, 'update' => false, 'delete' => false
        )
      end

      it 'does not serve a project manager entry to a group manager with the same ID', :aggregate_failures do
        # Group and project secrets managers live in separate tables, so their IDs can
        # collide in production. Both also resolve the same OpenBao paths, leaving
        # `scope_name` in the cache key as the only thing keeping their entries apart.
        group = create(:group)
        group_manager = create(:group_secrets_manager, group: group)
        allow(group_manager).to receive(:id).and_return(secrets_manager.id)

        group_client_double = instance_double(SecretsManagement::SecretsManagerClient)
        group_service = build_service(client: group_client_double, manager: group_manager, resource: group)

        allow(client_double).to receive(:capabilities_self)
          .and_return(capabilities_response(data_caps: %w[create], detailed_metadata_caps: %w[list]))
        allow(group_client_double).to receive(:capabilities_self)
          .and_return(capabilities_response(data_caps: [], detailed_metadata_caps: []))

        expect(build_service.execute).to eq(
          'read_metadata' => true, 'create' => true, 'update' => false, 'delete' => false
        )
        expect(group_service.execute).to eq(
          'read_metadata' => false, 'create' => false, 'update' => false, 'delete' => false
        )
      end

      context 'when the entitlement changes while the entry is still cached' do
        before do
          stub_feature_flags(secrets_manager_paid_experience: true)
        end

        it 're-applies the entitlement without a second OpenBao lookup' do
          expect(client_double).to receive(:capabilities_self).once
            .with(paths: [data_path, detailed_metadata_path])
            .and_return(capabilities_response(data_caps: %w[create update delete], detailed_metadata_caps: %w[list]))

          allow(::SecretsManagement::Entitlement).to receive(:for).and_return(
            ::SecretsManagement::Entitlement.new(state: :paid)
          )

          expect(build_service.execute).to eq(
            'read_metadata' => true, 'create' => true, 'update' => true, 'delete' => true
          )

          allow(::SecretsManagement::Entitlement).to receive(:for).and_return(
            ::SecretsManagement::Entitlement.new(state: :blocked, blocked_reason: :grace)
          )

          expect(build_service.execute).to eq(
            'read_metadata' => true, 'create' => false, 'update' => false, 'delete' => true
          )
        end
      end
    end
  end

  describe '.expire_for_user', :use_clean_rails_memory_store_caching, :request_store do
    let(:key) { described_class.cache_key_for(secrets_manager: secrets_manager, user_id: current_user.id) }
    let(:other_key) { described_class.cache_key_for(secrets_manager: secrets_manager, user_id: current_user.id + 1) }

    before do
      stub_feature_flags(secrets_manager_paid_experience: false)
    end

    it 'drops both cache layers for that user and manager only' do
      Rails.cache.write(key, { 'read_metadata' => false })
      ::Gitlab::SafeRequestStore.write(key, { 'read_metadata' => false })
      Rails.cache.write(other_key, { 'read_metadata' => true })

      described_class.expire_for_user(secrets_manager: secrets_manager, user_id: current_user.id)

      expect(Rails.cache.read(key)).to be_nil
      expect(::Gitlab::SafeRequestStore.read(key)).to be_nil
      expect(Rails.cache.read(other_key)).to eq('read_metadata' => true)
    end

    it 'makes the next lookup ask OpenBao again' do
      expect(client_double).to receive(:capabilities_self).twice
        .and_return({ "data" => { data_path => [], detailed_metadata_path => %w[list] } })

      service.execute
      described_class.expire_for_user(secrets_manager: secrets_manager, user_id: current_user.id)
      service.execute
    end
  end
end
