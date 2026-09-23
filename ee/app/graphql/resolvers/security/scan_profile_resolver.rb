# frozen_string_literal: true

module Resolvers
  module Security
    class ScanProfileResolver < BaseResolver
      include Gitlab::Graphql::Authorize::AuthorizeResource

      type Types::Security::ScanProfileType, null: true
      authorize :read_security_scan_profiles
      description 'Resolves security scan profiles.'

      argument :id, ::Types::GlobalIDType[::Security::ScanProfile],
        required: true,
        description: 'Global ID of the security scan profile.'

      def resolve(id:)
        model_id = id.model_id
        return find_default_profile(model_id) if ::Security::DefaultScanProfiles.virtual_identifier?(model_id)

        profile = preload_trigger_configurations(authorized_find!(id: id))
        # Global ID resolution is unscoped, so a soft-deleted profile still loads; hide it.
        raise_resource_not_available_error! if profile.deleted?

        profile
      end

      private

      def find_default_profile(model_id)
        profile = ::Security::DefaultScanProfiles.find_by_preset_key(model_id)
        raise_resource_not_available_error! unless profile
        profile
      end

      # Preload triggers and their configurations so ScanProfileType#trigger_settings and
      # #configuration don't N+1 on this single-record path.
      def preload_trigger_configurations(profile)
        return profile unless profile

        ActiveRecord::Associations::Preloader.new(
          records: [profile],
          associations: { scan_profile_triggers: :configuration }
        ).call

        profile
      end
    end
  end
end
