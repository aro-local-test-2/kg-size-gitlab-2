# frozen_string_literal: true

module Groups
  module Settings
    class SecureController < Groups::ApplicationController
      layout 'group_settings'

      before_action :check_feature_availability
      before_action :authorize_admin_group!

      # The page gate allows Secrets Manager-only groups; update only touches the
      # dependency firewall, so it needs its own availability check.
      before_action :check_dependency_firewall_availability!, only: [:update]

      before_action only: [:show] do
        push_frontend_feature_flag(:secrets_manager_paid_experience, group.root_ancestor)
      end

      feature_category :dependency_firewall
      urgency :low

      def show; end

      def update
        if Groups::UpdateService.new(group, current_user, dependency_firewall_params).execute
          flash[:notice] = s_('DependencyFirewall|Dependency firewall settings were successfully updated.')
        else
          flash[:alert] = s_('DependencyFirewall|Failed to update the dependency firewall settings.')
        end

        redirect_to group_settings_secure_path(group, anchor: 'js-dependency-firewall-settings')
      end

      private

      def check_feature_availability
        render_404 unless group.secure_settings_available?
      end

      def check_dependency_firewall_availability!
        render_404 unless group.dependency_firewall_setting_available?
      end

      def dependency_firewall_params
        params.require(:group).permit(:dependency_firewall_enabled)
      end
    end
  end
end
