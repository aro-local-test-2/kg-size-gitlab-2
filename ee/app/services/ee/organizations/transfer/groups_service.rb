# frozen_string_literal: true

module EE
  module Organizations
    module Transfer
      module GroupsService
        extend ::Gitlab::Utils::Override
        include ::Gitlab::Utils::StrongMemoize

        override :perform_transfer
        def perform_transfer
          super

          transfer_subscriptions
          transfer_ai_catalog_items
          transfer_custom_dashboards
          transfer_security_export_uploads
          schedule_security_exports_transfer
          transfer_upcoming_reconciliations
          transfer_scim_tokens
        end

        private

        def transfer_subscriptions
          update_organization_id_for(::GitlabSubscriptions::AddOnPurchase) { |relation| relation.by_namespace(group) }
          update_organization_id_for(::GitlabSubscriptions::SeatAssignment) { |relation| relation.by_namespace(group) }

          update_organization_id_for(::GitlabSubscriptions::UserAddOnAssignment) do |relation|
            relation.for_add_on_purchases(add_on_purchases_relation)
          end

          update_organization_id_for(::GitlabSubscriptions::UserAddOnAssignmentVersion) do |relation|
            relation.for_add_on_purchases(add_on_purchases_relation)
          end
        end

        def add_on_purchases_relation
          ::GitlabSubscriptions::AddOnPurchase.by_namespace(group)
        end
        strong_memoize_attr :add_on_purchases_relation

        # rubocop:disable CodeReuse/ActiveRecord -- Query specific to this service
        def transfer_ai_catalog_items
          update_organization_id_for(::Ai::Catalog::Item) do |relation|
            relation.where(project_id: projects)
          end
        end
        # rubocop:enable CodeReuse/ActiveRecord

        def transfer_custom_dashboards
          # Dashboards scoped to a namespace in the transferred group move with
          # it; organization-scoped dashboards (namespace_id: nil) stay with the
          # old organization. The dashboards subquery filters on namespace_id
          # only, so it stays valid after the parent update below.
          dashboards = ::Analytics::CustomDashboards::Dashboard.by_namespace(descendant_namespace_ids)

          update_organization_id_for(::Analytics::CustomDashboards::Dashboard) do |relation|
            relation.by_namespace(descendant_namespace_ids)
          end

          update_organization_id_for(::Analytics::CustomDashboards::SearchData) do |relation|
            relation.for_custom_dashboards(dashboards)
          end

          update_organization_id_for(::Analytics::CustomDashboards::DashboardVersion) do |relation|
            relation.for_custom_dashboards(dashboards)
          end
        end

        # rubocop:disable CodeReuse/ActiveRecord -- Query specific to this service

        # Phase 1: Synchronous transfer of upload tables (gitlab_main_org)
        # and their associated state tables (trigger-fire pattern).
        #
        # Upload partition tables use model_id to reference their parent
        # (Part or Export) on gitlab_sec. We load parent IDs into Ruby
        # to avoid cross-database subqueries.
        def transfer_security_export_uploads
          transfer_dep_part_uploads
          transfer_vuln_export_uploads
          transfer_vuln_part_uploads
        end

        def transfer_dep_part_uploads
          part_ids = dep_list_export_part_ids
          return if part_ids.empty?

          transfer_uploads_and_fire_trigger(
            ::Geo::DependencyListExportPartUpload,
            ::Geo::DependencyListExportPartUploadState,
            :dependency_list_export_part_upload_id,
            part_ids
          )
        end

        def transfer_vuln_export_uploads
          export_ids = vuln_export_ids
          return if export_ids.empty?

          transfer_uploads_and_fire_trigger(
            ::Geo::VulnerabilityExportUpload,
            ::Geo::VulnerabilityExportUploadState,
            :vulnerability_export_upload_id,
            export_ids
          )
        end

        def transfer_vuln_part_uploads
          part_ids = vuln_export_part_ids
          return if part_ids.empty?

          transfer_uploads_and_fire_trigger(
            ::Geo::VulnerabilityExportPartUpload,
            ::Geo::VulnerabilityExportPartUploadState,
            :vulnerability_export_part_upload_id,
            part_ids
          )
        end

        # rubocop:disable Database/AvoidUsingPluckWithoutLimit -- bounded by model_id_batch (at most batch_size parent IDs)
        def transfer_uploads_and_fire_trigger(upload_class, state_class, parent_fk, parent_model_ids)
          batch_size = ::Organizations::Transfer::Concerns::OrganizationUpdater::ORGANIZATION_ID_UPDATE_BATCH_SIZE

          parent_model_ids.each_slice(batch_size) do |model_id_batch|
            scoped = upload_class.where(model_id: model_id_batch, organization_id: old_organization.id)
            upload_ids = scoped.pluck(:id)
            next if upload_ids.empty?

            upload_class.where(id: upload_ids)
              .update_all(organization_id: new_organization.id)

            state_class
              .where(parent_fk => upload_ids)
              .where(organization_id: old_organization.id)
              .update_all(organization_id: nil)
          end
        end
        # rubocop:enable Database/AvoidUsingPluckWithoutLimit

        # Load IDs from gitlab_sec into Ruby to avoid cross-database
        # subqueries between gitlab_main_org and gitlab_sec.
        # rubocop:disable Database/AvoidUsingPluckWithoutLimit -- cross-DB workaround, bounded by group hierarchy
        def descendant_group_ids
          group.self_and_descendant_ids.pluck(:id)
        end
        strong_memoize_attr :descendant_group_ids

        def descendant_project_ids
          ::Project.in_namespace(group.self_and_descendant_ids(skope: ::Namespace)).pluck(:id)
        end
        strong_memoize_attr :descendant_project_ids

        def dep_list_export_ids
          ::Dependencies::DependencyListExport
            .where(group_id: descendant_group_ids)
            .or(::Dependencies::DependencyListExport.where(project_id: descendant_project_ids))
            .pluck(:id)
        end
        strong_memoize_attr :dep_list_export_ids

        def dep_list_export_part_ids
          return [] if dep_list_export_ids.empty?

          ::Dependencies::DependencyListExport::Part
            .where(dependency_list_export_id: dep_list_export_ids)
            .pluck(:id)
        end
        strong_memoize_attr :dep_list_export_part_ids

        def vuln_export_ids
          ::Vulnerabilities::Export
            .where(group_id: descendant_group_ids)
            .or(::Vulnerabilities::Export.where(project_id: descendant_project_ids))
            .pluck(:id)
        end
        strong_memoize_attr :vuln_export_ids

        def vuln_export_part_ids
          return [] if vuln_export_ids.empty?

          ::Vulnerabilities::Export::Part
            .where(vulnerability_export_id: vuln_export_ids)
            .pluck(:id)
        end
        strong_memoize_attr :vuln_export_part_ids
        # rubocop:enable Database/AvoidUsingPluckWithoutLimit

        # rubocop:enable CodeReuse/ActiveRecord

        # Phase 2: Async transfer of export parts tables (gitlab_sec)
        def schedule_security_exports_transfer
          group_id = group.id
          old_org_id = old_organization.id
          new_org_id = new_organization.id

          group.run_after_commit_or_now do
            ::Organizations::Transfer::SecurityExportsWorker.perform_async(group_id, old_org_id, new_org_id)
          end
        end

        def transfer_upcoming_reconciliations
          update_organization_id_for(::GitlabSubscriptions::UpcomingReconciliation) do |relation|
            relation.by_namespace_ids(descendant_namespace_ids)
          end
        end

        # rubocop:disable CodeReuse/ActiveRecord -- Query specific to this service
        def transfer_scim_tokens
          update_organization_id_for(::ScimOauthAccessToken) do |relation|
            relation.where(group_id: descendant_namespace_ids)
          end
        end
        # rubocop:enable CodeReuse/ActiveRecord

        def descendant_namespace_ids
          group.self_and_descendant_ids(skope: ::Namespace)
        end
        strong_memoize_attr :descendant_namespace_ids
      end
    end
  end
end
