# frozen_string_literal: true

module Types
  module Sbom
    module DependencyInterface
      include Types::BaseInterface
      include Types::Sbom::Concerns::LicenseOverrideable

      field :id, ::Types::GlobalIDType,
        null: false, description: 'ID of the dependency.'

      field :name, GraphQL::Types::String,
        null: false, description: 'Name of the dependency.'

      field :version, GraphQL::Types::String,
        null: true,
        description: 'Version of the dependency.',
        deprecated: { reason: 'Replaced by component_version', milestone: '18.1' }

      field :component_version, Types::Sbom::ComponentVersionType,
        null: true, description: 'Version of the dependency.'

      field :packager, Types::Sbom::PackageManagerEnum,
        null: true, description: 'Description of the tool used to manage the dependency.'

      field :location, Types::Sbom::LocationType,
        null: true, description: 'Information about where the dependency is located.'

      field :licenses, [Types::Sbom::LicenseType],
        null: true, description: 'Licenses associated to the dependency.'

      field :reachability, Types::Sbom::ReachabilityEnum,
        null: true, description: 'Information about reachability of a dependency.'

      field :malware, GraphQL::Types::Boolean,
        null: true,
        experiment: { milestone: '19.1' },
        description: 'Indicates whether the dependency is a malware package. ' \
          'Returns `true` if a malware package is identified. ' \
          'Returns `false` if the package is not a malware package. ' \
          'Returns `null` when malware detection is not enabled for the project.'

      field :vulnerability_count, GraphQL::Types::Int,
        null: false, description: 'Number of vulnerabilities within the dependency.'

      field :vulnerabilities, Types::VulnerabilityType.connection_type,
        null: true,
        resolver: ::Resolvers::Sbom::DependencyVulnerabilitiesResolver,
        description: 'Vulnerabilities associated with the dependency.'

      field :dependency_paths, ::Types::Sbom::DependencyPathPage,
        null: true, experiment: { milestone: '18.2' },
        authorize: :read_dependency,
        description: 'Ancestor dependency paths for a dependency. ' \
          'Returns `null` if `dependency_graph_graphql` feature flag is disabled.' do
        argument :after, String, required: false,
          description: "Fetch paths after the cursor."
        argument :before, String, required: false,
          description: "Fetch paths before the cursor."
        argument :limit, Integer, required: false,
          description: "Number of paths to fetch."
      end

      # Returns nil when the value is not in the predefined PACKAGE_MANAGERS list
      # This will prevent GraphQL type errors for projects with unknown package managers
      def packager
        packager = object.packager
        ::Sbom::DependenciesFinder::FILTER_PACKAGE_MANAGERS_VALUES.include?(packager) ? packager : nil
      end

      def licenses
        return [] unless object.licenses.present?

        base_licenses = object.licenses.map do |license|
          license.merge('project_id' => object.project_id, 'occurrence_uuid' => object.uuid)
        end

        apply_license_overrides(base_licenses)
      end

      # Batched so a page of dependencies costs one advisory lookup rather than one per node.
      def malware
        return unless malware_field_enabled?

        ::BatchLoader::GraphQL.for(object).batch do |occurrences, loader|
          ::Sbom::MalwareAdvisoriesPreloader.new(occurrences).execute

          occurrences.each { |occurrence| loader.call(occurrence, occurrence.malware_status) }
        end
      end

      def dependency_paths(**args)
        # Inject the occurrence argument with the current object's ID
        args[:occurrence] = object.to_global_id
        ::Resolvers::Sbom::DependencyPathsResolver.new(object: object.project, context: context,
          field: nil).resolve(**args)
      end

      private

      def malware_field_enabled?
        object.project.dependency_malware_detection_feature_flag_enabled?
      end
    end
  end
end
