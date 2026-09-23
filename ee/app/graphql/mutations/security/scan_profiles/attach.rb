# frozen_string_literal: true

module Mutations
  module Security
    module ScanProfiles
      class Attach < BaseMutation
        graphql_name 'SecurityScanProfileAttach'

        include Gitlab::InternalEventsTracking
        include Mutations::Security::ScanProfiles::SharedScopeResolution

        argument :security_scan_profile_id, Types::GlobalIDType[::Security::ScanProfile],
          required: true,
          description: 'Security scan profile ID to attach.',
          prepare: ->(global_id, _ctx) { global_id.model_id }

        argument :project_ids, [Types::GlobalIDType[::Project]],
          required: false,
          default_value: [],
          description: 'Project IDs to attach the profile to.',
          prepare: ->(global_ids, _ctx) { global_ids.map(&:model_id) }

        argument :group_ids, [Types::GlobalIDType[::Group]],
          required: false,
          default_value: [],
          description: 'Group IDs to attach the profile to.',
          prepare: ->(global_ids, _ctx) { global_ids.map(&:model_id) }

        def self.authorization_scopes
          super + [:ai_workflows]
        end

        def resolve(security_scan_profile_id:, project_ids:, group_ids:)
          validate_id_limit!(project_ids, group_ids)

          root_namespace = shared_root_namespace!(project_ids, group_ids)

          authorized_projects = load_and_authorize_projects!(project_ids)
          authorized_groups = load_and_authorize_groups!(group_ids)
          profile = resolve_profile!(security_scan_profile_id, root_namespace)

          result = attach_to_projects(profile, authorized_projects)
          schedule_group_workers(authorized_groups, profile)

          track_internal_event(
            "attach_scan_profile",
            user: current_user,
            namespace: root_namespace
          )

          { errors: result[:errors] }
        end

        private

        def resolve_profile!(security_scan_profile_id, root_namespace)
          result =  ::Security::ScanProfiles::FindOrCreateService.execute(
            namespace: root_namespace,
            identifier: security_scan_profile_id
          )

          return result.payload[:scan_profile] if result.success?

          raise_resource_not_available_error!
        end

        def attach_to_projects(profile, projects)
          return { errors: [] } if projects.empty?

          ::Security::ScanProfiles::ProjectAttachService.execute(
            profile: profile,
            projects: projects,
            current_user: current_user
          )
        end

        def schedule_group_workers(groups, profile)
          return if groups.empty?

          operation_id = create_background_operation(groups.size, profile)
          # rubocop:disable CodeReuse/Worker -- This should schedule async workers
          ::Security::ScanProfiles::AttachWorker.bulk_perform_async_with_contexts(
            groups,
            arguments_proc: ->(group) { [group.id, profile.id, current_user.id, operation_id, true] },
            context_proc: ->(group) { { namespace: group, user: current_user } }
          )
          # rubocop:enable CodeReuse/Worker
        end

        def create_background_operation(groups_count, profile)
          Gitlab::BackgroundOperations::RedisStore.create_operation(
            operation_type: 'profile_attach',
            user_id: current_user.id,
            total_items: groups_count,
            parameters: { profile_id: profile.id }
          )
        end
      end
    end
  end
end
