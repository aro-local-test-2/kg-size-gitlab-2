# frozen_string_literal: true

module Mutations
  module Security
    module ScanProfiles
      class Detach < BaseMutation
        graphql_name 'SecurityScanProfileDetach'

        include Gitlab::InternalEventsTracking
        include Mutations::Security::ScanProfiles::SharedScopeResolution

        argument :security_scan_profile_id, Types::GlobalIDType[::Security::ScanProfile],
          required: true,
          description: 'Security scan profile ID to detach.',
          prepare: ->(global_id, _ctx) { global_id.model_id }

        argument :project_ids, [Types::GlobalIDType[::Project]],
          required: false,
          default_value: [],
          description: 'Project IDs to detach the profile from.',
          prepare: ->(global_ids, _ctx) { global_ids.map(&:model_id) }

        argument :group_ids, [Types::GlobalIDType[::Group]],
          required: false,
          default_value: [],
          description: 'Group IDs to detach the profile from.',
          prepare: ->(global_ids, _ctx) { global_ids.map(&:model_id) }

        def resolve(security_scan_profile_id:, project_ids:, group_ids:)
          validate_id_limit!(project_ids, group_ids)

          root_namespace = shared_root_namespace!(project_ids, group_ids)

          authorized_projects = load_and_authorize_projects!(project_ids)
          authorized_groups = load_and_authorize_groups!(group_ids)
          profile = find_profile!(security_scan_profile_id, root_namespace)

          result = detach_from_projects(profile, authorized_projects)
          schedule_group_workers(authorized_groups, profile)

          track_internal_event(
            "detach_scan_profile",
            user: current_user,
            namespace: root_namespace
          )

          { errors: result[:errors] }
        end

        private

        def find_profile!(security_scan_profile_id, root_namespace)
          profile = ::Security::ScanProfile.not_deleted.by_namespace(root_namespace).id_in(security_scan_profile_id).first
          return profile if profile.present?

          raise_resource_not_available_error!
        end

        def detach_from_projects(profile, projects)
          return { errors: [] } if projects.empty?

          ::Security::ScanProfiles::ProjectDetachService.execute(
            profile: profile,
            projects: projects,
            current_user: current_user
          )
        end

        def schedule_group_workers(groups, profile)
          return if groups.empty?

          operation_id = create_background_operation(groups.size, profile)

          # rubocop:disable CodeReuse/Worker -- This should schedule async workers
          ::Security::ScanProfiles::DetachWorker.bulk_perform_async_with_contexts(
            groups,
            arguments_proc: ->(group) { [group.id, profile.id, current_user.id, operation_id, true] },
            context_proc: ->(group) { { namespace: group, user: current_user } }
          )
          # rubocop:enable CodeReuse/Worker
        end

        def create_background_operation(groups_count, profile)
          Gitlab::BackgroundOperations::RedisStore.create_operation(
            operation_type: 'profile_detach',
            user_id: current_user.id,
            total_items: groups_count,
            parameters: { profile_id: profile.id }
          )
        end
      end
    end
  end
end
