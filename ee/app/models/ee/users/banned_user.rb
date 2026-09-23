# frozen_string_literal: true

module EE
  module Users
    module BannedUser
      extend ActiveSupport::Concern

      prepended do
        after_commit :reindex_associations, on: [:create, :destroy]
      end

      private

      def reindex_associations
        # Notes are fanned out unconditionally, not gated on the `hidden` mapping
        # migration: `migration_has_finished?` is cached for 30 minutes and fails
        # closed, so a ban inside a false-negative window would leave those notes
        # `hidden: false` forever (nothing else re-indexes them). Fanning out
        # early is harmless -- the writer omits the field until its mapping exists.
        ElasticAssociationIndexerWorker.perform_async(user.class.name, user.id, %i[issues merge_requests notes])
      end
    end
  end
end
