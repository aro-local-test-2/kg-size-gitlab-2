# frozen_string_literal: true

module SecretsHelper
  def project_secrets_app_data(project)
    root_namespace = project.root_ancestor

    {
      base_path: project_secrets_path(project),
      can_start_trial: can_start_secrets_manager_trial?(root_namespace).to_s,
      enrollment_settings_path: enrollment_settings_path(root_namespace),
      manage_permissions_path: edit_project_path(project, anchor: 'js-shared-permissions'),
      project_path: project.full_path,
      top_level_group_full_path: root_namespace.is_a?(Group) ? root_namespace.full_path : ''
    }
  end

  def group_secrets_app_data(group)
    root_namespace = group.root_ancestor

    {
      base_path: group_secrets_path(group),
      can_start_trial: can_start_secrets_manager_trial?(root_namespace).to_s,
      enrollment_settings_path: enrollment_settings_path(root_namespace),
      group_path: group.full_path,
      manage_permissions_path: group_manage_permissions_path(group),
      top_level_group_full_path: root_namespace.full_path
    }
  end

  def namespace_enrollment_data(namespace, user)
    {
      can_manage_secrets_manager: can?(user, :admin_group, namespace).to_s, # rubocop:disable Gitlab/Authz/PermissionCheck -- will iterate on this. provision_secrets_manager is a good fit but it needs to be fetched/updated dynamically on enrollment
      can_enroll_namespace: can?(user, :create_secrets_manager_enrollment, namespace).to_s,
      full_path: namespace.full_path,
      is_namespace_enrollable: (namespace.root? && Gitlab.com?).to_s, # rubocop:disable Gitlab/AvoidGitlabInstanceChecks -- testing SaaS behavior directly (feature is also available for self-managed, but enrollment behavior is different)
      top_level_group_full_path: namespace.root_ancestor.full_path
    }
  end

  private

  # Same ability as SecretsManagerStartTrial, so the button and the mutation agree.
  # Personal namespaces have no trial concept, so return false there.
  def can_start_secrets_manager_trial?(root_namespace)
    return false unless root_namespace.is_a?(Group)

    can?(current_user, :start_secrets_manager_trial, root_namespace)
  end

  def enrollment_settings_path(root_group)
    if allow_secrets_manager_instance_enrollment?
      general_admin_application_settings_path(anchor: 'js-secrets-manager-instance-enrollment-settings')
    else
      # The top-level group's Secrets Manager settings live under the Secure tab.
      group_settings_secure_path(root_group, anchor: 'js-secrets-manager-settings')
    end
  end

  # Subgroups keep their Secrets Manager settings under General; only the
  # top-level group moves to the Secure tab.
  def group_manage_permissions_path(group)
    if group.root?
      group_settings_secure_path(group, anchor: 'js-secrets-manager-settings')
    else
      edit_group_path(group, anchor: 'js-permissions-settings')
    end
  end
end
