# frozen_string_literal: true

module API
  module Entities
    class Dependency < Grape::Entity
      expose :name, documentation: { type: 'String' }
      expose :version, documentation: { type: 'String' }
      expose :package_manager, documentation: { type: 'String' }
      expose :input_file_path, as: :dependency_file_path, documentation: { type: 'String' }
      expose :vulnerabilities, using: DependencyEntity::VulnerabilityEntity,
        if: ->(_, opts) { can_read_vulnerabilities?(opts[:user], opts[:project]) }
      expose :licenses, using: DependencyEntity::LicenseEntity,
        if: ->(_, opts) { can_read_licenses?(opts[:user], opts[:project]) }
      expose :malware,
        documentation: {
          type: 'Boolean',
          desc: 'Malware status: true if the package version matches a malware advisory, ' \
            'false otherwise. Omitted when malware detection is not enabled for the project.'
        },
        if: ->(_, opts) {
          can_read_vulnerabilities?(opts[:user], opts[:project]) &&
            opts[:project].dependency_malware_detection_feature_flag_enabled?
        } do |occurrence, _opts|
        occurrence.malware_status
      end

      private

      def can_read_vulnerabilities?(user, project)
        Ability.allowed?(user, :read_security_resource, project)
      end

      def can_read_licenses?(user, project)
        Ability.allowed?(user, :read_licenses, project)
      end
    end
  end
end
