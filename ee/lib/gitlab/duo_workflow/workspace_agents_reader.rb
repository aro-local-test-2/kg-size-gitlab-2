# frozen_string_literal: true

module Gitlab
  module DuoWorkflow
    class WorkspaceAgentsReader
      include Gitlab::Loggable

      AGENTS_DIR = '.agents/agents'
      FILE_EXTENSION = '.md'
      # Same limit as the AI Gateway.
      MAX_AGENTS = 10
      # Derived from the field ceilings the Duo Workflow Service enforces, with headroom for
      # multibyte characters and front matter.
      # https://gitlab.com/gitlab-org/modelops/applied-ml/code-suggestions/ai-assist/-/blob/eb701cd8cbabb2c87cb2e6c574563ee91ba0a8b0/duo_workflow_service/agent_platform/v1/catalog/items/workspace_agent.py#L25-27
      MAX_FILE_SIZE = 64.kilobytes

      def initialize(project)
        @project = project
      end

      def agents
        return [] unless default_branch

        blobs.filter_map { |blob| parse(blob) }
      rescue StandardError => e
        Gitlab::ErrorTracking.track_exception(e, project_id: project.id)
        []
      end

      private

      attr_reader :project

      def default_branch
        project.default_branch
      end

      def blobs
        tree = project.repository.tree(default_branch, AGENTS_DIR)
        return [] unless tree

        paths = tree.blobs.map(&:path).select { |path| path.end_with?(FILE_EXTENSION) }.sort
        log_over_limit(paths.drop(MAX_AGENTS)) if paths.size > MAX_AGENTS

        items = paths.first(MAX_AGENTS).map { |path| [default_branch, path] }
        project.repository.blobs_at(items, blob_size_limit: MAX_FILE_SIZE)
      end

      def log_over_limit(paths)
        Gitlab::AppJsonLogger.warn(
          build_structured_payload_labkit(
            message: 'Ignoring workspace agent files over the limit',
            Labkit::Fields::GL_PROJECT_ID => project.id,
            limit: MAX_AGENTS,
            paths: paths
          )
        )
      end

      def parse(blob)
        return skip(blob, "is larger than #{MAX_FILE_SIZE} bytes") if blob.truncated?
        return skip(blob, 'is not a UTF-8 text file') if blob.binary? || !blob.data.valid_encoding?

        match = ::Gitlab::FrontMatter::PATTERN_UNTRUSTED_REGEX.match(blob.data)
        return skip(blob, 'has no YAML front matter') unless yaml_front_matter?(match)

        fields = YAML.safe_load(match[:front_matter])
        return skip(blob, 'front matter is not a mapping') unless fields.is_a?(Hash)

        agent = build_agent(fields, blob.data.delete_prefix(match.to_s), blob.path)
        return skip(blob, 'is missing a description or a prompt') unless agent

        agent
      rescue Psych::Exception
        skip(blob, 'has invalid YAML front matter')
      end

      def yaml_front_matter?(match)
        match && match[:delim] == '---' && match[:lang].blank?
      end

      def build_agent(fields, body, path)
        description = fields['description'].to_s.strip
        prompt = body.strip
        return if description.empty? || prompt.empty?

        {
          'name' => fields['name'].to_s.strip.presence || File.basename(path, FILE_EXTENSION),
          'description' => description,
          'toolset' => toolset(fields['tools']),
          'prompt' => prompt
        }
      end

      # Tool names pass through as declared; governance is enforced downstream. Filtering here is a follow-up:
      # https://gitlab.com/gitlab-org/gitlab/-/work_items/628971
      def toolset(tools)
        entries = tools.is_a?(String) ? tools.split(',') : Array(tools)
        entries.map { |tool| tool.to_s.strip }.reject(&:empty?)
      end

      # Invalid files are logged and dropped so the run still starts. Surfacing them to the user is a follow-up:
      # https://gitlab.com/gitlab-org/gitlab/-/work_items/628969
      def skip(blob, reason)
        Gitlab::AppJsonLogger.warn(
          build_structured_payload_labkit(
            message: 'Skipping workspace agent file',
            Labkit::Fields::GL_PROJECT_ID => project.id,
            path: blob.path,
            Labkit::Fields::ADDITIONAL_DETAILS => reason
          )
        )
        nil
      end
    end
  end
end
