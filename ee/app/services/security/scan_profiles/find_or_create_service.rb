# frozen_string_literal: true

module Security
  module ScanProfiles
    class FindOrCreateService
      UNIQUE_INDEX = :index_security_scan_profiles_unique_name_not_deleted

      def self.execute(...)
        new(...).execute
      end

      def initialize(namespace:, identifier:)
        @namespace = namespace
        @identifier = identifier.to_s
      end

      def execute
        return error_response('Namespace must be a root namespace') unless namespace.root?

        profile = find_or_create_profile
        return error_response('Could not find a default scan profile for this type') unless profile

        success_response(profile)
      rescue ActiveRecord::StatementInvalid, ActiveRecord::RecordInvalid => e
        error_response("Failed to create scan profile: #{e.message}")
      end

      private

      attr_reader :namespace, :identifier

      def find_or_create_profile
        if ::Security::DefaultScanProfiles.virtual_identifier?(identifier)
          find_or_create_default_profile
        else
          ::Security::ScanProfile.not_deleted.by_namespace(namespace).id_in(identifier).first
        end
      end

      def find_or_create_default_profile
        default_profile = Security::DefaultScanProfiles.find_by_preset_key(identifier)
        return unless default_profile
        return unless preset_available?(default_profile)

        Security::ScanProfile.transaction do
          upsert_profile(default_profile)
          profile = fetch_persisted_profile(default_profile)
          create_missing_triggers(profile, default_profile)
          profile.reset
        end
      end

      def preset_available?(default_profile)
        return true unless default_profile.triage_and_remediation?

        Feature.enabled?(:triage_and_remediation_profile, namespace)
      end

      def upsert_profile(default_profile)
        Security::ScanProfile.upsert(
          {
            namespace_id: namespace.id,
            gitlab_recommended: true,
            scan_type: default_profile.scan_type,
            name: default_profile.name,
            description: default_profile.description
          },
          # The partial unique index covers (namespace_id, scan_type, lower(name)) WHERE
          # deleted_at IS NULL; Rails includes that predicate in the ON CONFLICT target. Inserts
          # always set deleted_at to NULL, so conflicts resolve against it.
          unique_by: UNIQUE_INDEX
        )
      end

      def fetch_persisted_profile(default_profile)
        Security::ScanProfile.by_namespace(namespace).by_type(default_profile.scan_type)
          .by_name(default_profile.name).by_gitlab_recommended.first
      end

      def create_missing_triggers(profile, default_profile)
        existing_types = profile.scan_profile_triggers.map(&:trigger_type)

        default_profile.scan_profile_triggers.each do |default_trigger|
          next if existing_types.include?(default_trigger.trigger_type)

          profile.scan_profile_triggers.create!(
            namespace: namespace,
            trigger_type: default_trigger.trigger_type,
            configuration: build_configuration(profile, default_trigger)
          )
        end
      end

      def build_configuration(profile, default_trigger)
        overrides = default_trigger.configuration&.configuration
        return if overrides.blank?

        Security::ScanProfiles::Configuration.new(
          scan_profile: profile, namespace: namespace, configuration: overrides,
          trigger_type: default_trigger.trigger_type
        )
      end

      def success_response(profile)
        ServiceResponse.success(payload: { scan_profile: profile })
      end

      def error_response(message)
        ServiceResponse.error(message: message)
      end
    end
  end
end
