# frozen_string_literal: true

module Security
  module SecurityOrchestrationPolicies
    module PolicyStore
      class ListService < BaseService
        # The port speaks offset, not page number: this is the boundary that translates
        # the caller-facing "page N of size M" request into that, so the repository never
        # needs to know what a page is.
        MAX_PAGE = 1_000

        # The REST/GraphQL-facing sentinel for "no lifecycle_state filter", so a caller
        # can request every policy in one page without a boolean losing that third state.
        ALL_LIFECYCLE_STATES = 'all'

        def initialize(
          container:, current_user:, trigger_type: nil, ids: nil,
          lifecycle_state: ::Gitlab::PolicyStore::Ports::PolicyRepository::DEFAULT_LIFECYCLE_STATE, page: 1,
          per_page: ::Gitlab::PolicyStore::Ports::PolicyRepository::DEFAULT_PER_PAGE)
          super(container: container, current_user: current_user)

          @trigger_type = trigger_type
          @ids = ids
          @requested_lifecycle_state = lifecycle_state
          @page = page.to_i.clamp(1, MAX_PAGE)
          @per_page = per_page.to_i.clamp(1, ::Gitlab::PolicyStore::Ports::PolicyRepository::MAX_PER_PAGE)
        end

        def execute
          return forbidden_error unless authorized?(:read_govern_policy)
          return experiment_not_active_error unless experiment_active?

          result_page = ::Gitlab::PolicyStore.list(
            organization_id: organization.id, trigger_type: trigger_type, namespace_id: namespace_id,
            lifecycle_state: lifecycle_state, ids: ids,
            offset: (@page - 1) * @per_page, per_page: @per_page
          )

          ServiceResponse.success(payload: {
            policies: result_page.items, page: @page, per_page: result_page.per_page,
            has_next_page: result_page.has_next_page?
          })
        rescue ::Gitlab::PolicyStore::ValidationError => error
          ServiceResponse.error(message: error.message, reason: :invalid)
        end

        private

        attr_reader :trigger_type, :ids, :requested_lifecycle_state

        def lifecycle_state
          requested_lifecycle_state == ALL_LIFECYCLE_STATES ? nil : requested_lifecycle_state
        end
      end
    end
  end
end
