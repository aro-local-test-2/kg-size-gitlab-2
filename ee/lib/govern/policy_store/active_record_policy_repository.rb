# frozen_string_literal: true

module Govern
  module PolicyStore
    # ActiveRecord implementation of the repository port from gems/gitlab-policy-store,
    # backing the Policy Store with the govern_policies table.
    #
    # Not an authorization boundary: find/list return any policy by id or
    # organization. Permission checks belong to the calling service layer.
    class ActiveRecordPolicyRepository < ::Gitlab::PolicyStore::Ports::PolicyRepository
      NAME_UNIQUENESS_CONSTRAINT = 'unique_govern_policies_organization_id_and_name'
      private_constant :NAME_UNIQUENESS_CONSTRAINT

      def create(attributes)
        normalized = creatable_attributes(attributes)
        validate_required_attributes!(normalized)
        validate_authored_text_limits!(normalized)
        validate_enumerated_attributes!(normalized, ENUMERATED_ATTRIBUTES)
        validate_entry_limits!(normalized)
        validate_action_shapes!(normalized)
        validate_name_available!(organization_id: normalized[:organization_id], name: normalized[:name])

        compiled = with_compiled_rules(with_compiled_scope(normalized))
        validate_compiled_text_limits!(compiled)

        record = ::Govern::Policy.new
        record.assign_attributes(compiled)
        save_record!(record)

        # Postgres truncates the nanosecond timestamps Rails assigned, so a value object
        # built from the saved record would never equal one a later read returns.
        record.reload # rubocop:disable Cop/ActiveRecordAssociationReload -- the record, not an association

        to_value_object(record)
      end

      def update(id, attributes)
        record = find_record(id)
        stored_attributes = to_value_object(record).to_h
        changes = changes_excluding_restated(stored_attributes, updatable_changes(attributes, stored_attributes))

        return to_value_object(record) if changes.empty?

        authored = stored_attributes.merge(changes)
        validate_required_attributes!(authored)
        validate_authored_text_limits!(authored)
        validate_enumerated_attributes!(authored, ENUMERATED_ATTRIBUTES)
        validate_entry_limits!(changes)
        validate_action_shapes!(changes)
        validate_name_available!(organization_id: authored[:organization_id], name: authored[:name], excluding_id: id)

        record.with_lock do
          record.assign_attributes(reconciled_changes(record, changes))
          next unless record.changed?

          record.version += 1
          save_record!(record)
          record.reload # rubocop:disable Cop/ActiveRecordAssociationReload -- the record, not an association
        end

        to_value_object(record)
      rescue ActiveRecord::RecordNotFound
        # with_lock reloads, so a concurrent delete surfaces here rather than in find_record.
        raise ::Gitlab::PolicyStore::NotFound, "Policy with id #{id} was not found"
      end

      def find(id)
        to_value_object(find_record(id))
      end

      def delete(id)
        find_record(id).destroy!

        nil
      end

      def list(
        organization_id:, trigger_type: nil, namespace_id: nil, lifecycle_state: nil, ids: nil, offset: 0,
        per_page: DEFAULT_PER_PAGE)
        records = ::Govern::Policy.for_organization(organization_id).order_id_asc
        records = records.for_trigger_type(trigger_type) if trigger_type
        records = records.for_namespace(namespace_id) if namespace_id
        records = records.for_lifecycle_state(lifecycle_state) if lifecycle_state

        if ids
          validate_ids_size!(ids)
          fetched = records.id_in(ids).to_a
          return paginated_result(fetched, per_page: fetched.size) { |record| to_value_object(record) }
        end

        offset, per_page = clamped_pagination(offset: offset, per_page: per_page)
        fetched = records.paginated(starting_at: offset, per_page: per_page + 1).to_a

        paginated_result(fetched, per_page: per_page) { |record| to_value_object(record) }
      end

      private

      def find_record(id)
        ::Govern::Policy.find(id)
      rescue ActiveRecord::RecordNotFound
        raise ::Gitlab::PolicyStore::NotFound, "Policy with id #{id} was not found"
      end

      # Cheap check, run before compiling scope or rules, so a taken name is reported
      # even when the rest of the input would not otherwise compile. save_record! still
      # catches the unique index itself, since this read-then-write check has a race.
      def validate_name_available!(organization_id:, name:, excluding_id: nil)
        scope = ::Govern::Policy.for_organization(organization_id).for_name(name)
        scope = scope.excluding_id(excluding_id) if excluding_id

        raise ::Gitlab::PolicyStore::ValidationError, 'Name has already been taken' if scope.exists?
      end

      # The uniqueness validation is a read-then-write, so a concurrent create of the same
      # name passes it and loses to the unique index instead. Any other constraint is a bug
      # rather than caller input, so it keeps its own exception.
      def save_record!(record)
        raise ::Gitlab::PolicyStore::ValidationError, record.errors.full_messages.to_sentence unless record.save

        nil
      rescue ActiveRecord::RecordNotUnique => error
        raise unless error.message.include?(NAME_UNIQUENESS_CONSTRAINT)

        raise ::Gitlab::PolicyStore::ValidationError, 'Name has already been taken'
      end

      def reconciled_changes(record, changes)
        stored_scope = {
          name: record.name, policy_scope: record.policy_scope, scope_rego: record.scope_rego,
          scope_dimensions: record.scope_dimensions
        }
        updated_scope = with_updated_scope(stored_scope, changes).slice(:policy_scope, :scope_rego, :scope_dimensions)
        validate_compiled_text_limits!(updated_scope)

        with_updated_rules(changes.merge(updated_scope), changes)
      end

      def to_value_object(record)
        ::Gitlab::PolicyStore::Policy.new(
          id: record.id,
          organization_id: record.organization_id,
          namespace_id: record.namespace_id,
          name: record.name,
          description: record.description,
          version: record.version,
          trigger_type: record.trigger_type,
          rules: record.rules.deep_dup,
          actions: record.actions.deep_dup,
          policy_scope: record.policy_scope.deep_dup,
          scope_rego: record.scope_rego,
          scope_dimensions: record.scope_dimensions&.deep_dup,
          mode: record.mode,
          lifecycle_state: record.lifecycle_state,
          created_at: record.created_at,
          updated_at: record.updated_at
        )
      end
    end
  end
end
