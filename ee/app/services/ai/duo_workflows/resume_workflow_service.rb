# frozen_string_literal: true

module Ai
  module DuoWorkflows
    class ResumeWorkflowService < StartWorkflowService
      # Emitted by git_environment_variables only on some paths, so a plain merge would
      # leave the previous job's behind: FF_GIT_URLS_WITHOUT_TOKENS when the flag was on
      # then off, and the higher GIT_CONFIG_* indices when the entry count shrinks.
      CONDITIONAL_GIT_ENV_KEYS = /\A(?:GIT_CONFIG_(?:KEY|VALUE)_\d+|FF_GIT_URLS_WITHOUT_TOKENS)\z/

      private

      def variables
        # Preserve job variables from initial workload; refresh only token variables.
        # Git config is recomputed rather than preserved: a resumed workflow is a new
        # pipeline with a fresh clone, and the commands that depend on it are recomputed
        # too, so carrying the previous job's GIT_CONFIG_* forward would let a
        # dap_git_credential_helper or dap_session_tracking_enabled? flip mid-workflow
        # leave the variables and the commands on opposite git-auth paths.
        previous_vars = previous_workload_variables
        return super if previous_vars.empty?

        merged = previous_vars
          .reject { |key, _| key.to_s.match?(CONDITIONAL_GIT_ENV_KEYS) }
          .merge(git_environment_variables)
          .merge(token_variables)

        # The preserved `DUO_WORKFLOW_GOAL` is stale from the first run, so a
        # resume carrying a fresh goal has to override it.
        merged[:DUO_WORKFLOW_GOAL] = workflow_goal if @params[:goal].present?
        merged
      end

      def executor_cli_command
        cmd = super
        # `human_approval` nil (vs true/false) means no approve/reject decision;
        # omit the flag instead so ai-gateway treats `goal` as the reply.
        cmd += %( --approval #{@params[:human_approval]}) unless @params[:human_approval].nil?
        if @params[:human_message].present?
          cmd += %( --rejection-reason #{Shellwords.shellescape(@params[:human_message])})
        end

        cmd
      end

      def previous_workload_variables
        build = @workflow.last_workload&.pipeline&.builds&.first
        return {} unless build

        build.yaml_variables.to_h { |v| [v[:key].to_sym, v[:value]] }
      end

      # A resumed goal can be a user's free-text reply (see
      # ResumeWorkplanService), not the templated goal a fresh start carries.
      # The job trace is otherwise unmasked and often public, so this is not
      # echoed - same reasoning as DUO_WORKFLOW_ADDITIONAL_CONTEXT_CONTENT in
      # the parent class.
      def goal_echo_command
        nil
      end
    end
  end
end
