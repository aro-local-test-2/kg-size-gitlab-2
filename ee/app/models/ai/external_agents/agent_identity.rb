# frozen_string_literal: true

module Ai
  module ExternalAgents
    class AgentIdentity < ApplicationRecord
      AGENT_TYPES = %w[claude-code opencode].freeze

      self.table_name = 'ai_agent_identities'

      belongs_to :user
      belongs_to :project

      validates :agent_type, presence: true, inclusion: { in: AGENT_TYPES }
      validates :machine_fingerprint, presence: true,
        format: { with: /\A\h{64}\z/, message: 'must be a 64-character hex string' }

      scope :active, -> { where(revoked_at: nil) }
      scope :revoked, -> { where.not(revoked_at: nil) }
      scope :for_project, ->(project) { where(project: project) }
      scope :for_user, ->(user) { where(user: user) }
      scope :in_namespace_hierarchy, ->(namespace) {
        where(project_id: ::Project.in_namespace(namespace.self_and_descendants.select(:id)).select(:id))
      }
      scope :with_agent_types, ->(agent_types) { where(agent_type: agent_types) }

      # [agent_type, machines, unrevoked machines, distinct users] per type,
      # most machines first.
      def self.registration_counts_by_agent_type(limit:)
        group(:agent_type)
          .order(Arel.sql('COUNT(*) DESC'), agent_type: :asc)
          .limit(limit)
          .pluck(
            :agent_type,
            Arel.sql('COUNT(*)'),
            Arel.sql('COUNT(*) FILTER (WHERE revoked_at IS NULL)'),
            Arel.sql('COUNT(DISTINCT user_id)')
          )
      end

      def self.register(user:, project:, agent_type:, machine_fingerprint:)
        safe_find_or_create_by!( # rubocop:disable Performance/ActiveRecordSubtransactionMethods -- identity registration is low-traffic and write-once per machine per project
          user: user,
          project: project,
          agent_type: agent_type,
          machine_fingerprint: machine_fingerprint
        )
      end

      def self.owned_by?(id:, user:, project:, agent_type:)
        active.where(id: id, user: user, project: project, agent_type: agent_type).exists?
      end

      def revoked?
        revoked_at.present?
      end

      def revoke!
        update!(revoked_at: Time.current)
      end
    end
  end
end
