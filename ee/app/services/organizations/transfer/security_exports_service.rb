# frozen_string_literal: true

module Organizations
  module Transfer
    class SecurityExportsService
      include Organizations::Transfer::Concerns::OrganizationUpdater

      def initialize(group:, old_organization:, new_organization:)
        @group = group
        @old_organization = old_organization
        @new_organization = new_organization
      end

      def execute
        ::SecApplicationRecord.transaction do
          each_group_batch do |batch|
            transfer_exports_for(group_id: batch)
          end

          each_project_batch do |batch|
            transfer_exports_for(project_id: batch)
          end
        end
      end

      private

      attr_reader :group, :old_organization, :new_organization

      # rubocop:disable CodeReuse/ActiveRecord -- Query specific to this service
      def transfer_exports_for(scope)
        update_organization_id_for(::Vulnerabilities::Export) do |relation|
          relation.where(scope)
        end

        each_export_batch(::Dependencies::DependencyListExport, scope) do |export_ids|
          update_organization_id_for(::Dependencies::DependencyListExport::Part) do |relation|
            relation.where(dependency_list_export_id: export_ids)
          end
        end

        each_export_batch(::Vulnerabilities::Export, scope) do |export_ids|
          update_organization_id_for(::Vulnerabilities::Export::Part) do |relation|
            relation.where(vulnerability_export_id: export_ids)
          end
        end
      end

      def each_export_batch(export_class, scope)
        export_class.where(scope).each_batch(of: ApplicationRecord::MAX_PLUCK) do |batch|
          yield batch.limit(ApplicationRecord::MAX_PLUCK).pluck(:id)
        end
      end
      # rubocop:enable CodeReuse/ActiveRecord

      # rubocop:disable CodeReuse/ActiveRecord -- Batching because of cross-db queries
      def each_group_batch
        group.self_and_descendant_ids.each_batch(of: ApplicationRecord::MAX_PLUCK) do |batch|
          yield batch.limit(ApplicationRecord::MAX_PLUCK).pluck(:id)
        end
      end
      # rubocop:enable CodeReuse/ActiveRecord

      # rubocop:disable CodeReuse/ActiveRecord -- Batching because of cross-db queries
      def each_project_batch
        ::Project.in_namespace(group.self_and_descendant_ids(skope: ::Namespace))
          .each_batch(of: ApplicationRecord::MAX_PLUCK) do |batch|
          yield batch.limit(ApplicationRecord::MAX_PLUCK).pluck(:id)
        end
      end
      # rubocop:enable CodeReuse/ActiveRecord
    end
  end
end
