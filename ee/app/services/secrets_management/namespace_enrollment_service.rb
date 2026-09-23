# frozen_string_literal: true

module SecretsManagement
  class NamespaceEnrollmentService
    def initialize(namespace, current_user:)
      @namespace = namespace
      @current_user = current_user
    end

    def enroll
      return enrollment_not_allowed_error unless NamespaceEnrollment.enrollment_allowed?(namespace)

      existing = NamespaceEnrollment.find_by_namespace_id(namespace.id)
      return already_enrolled_response if existing&.enabled?

      # Re-enrolling re-evaluates the beta cohort so a namespace that opted out
      # before the paid experience reached it does not keep free beta access.
      enrollment = existing || NamespaceEnrollment.new(namespace: namespace)
      enrollment.update!(disabled_at: nil, beta: beta_enrollment?)

      audit_event(name: 'secrets_manager_namespace_enroll', message: 'Enrolled namespace in Secrets Manager')

      ServiceResponse.success(payload: { enrollment: enrollment })
    rescue ActiveRecord::RecordNotUnique
      already_enrolled_response
    end

    # Under the paid experience, opting out soft-disables the record: it marks
    # the opt-out and stored secrets are retained. The free beta keeps the old
    # destroy behavior: outside the paid experience the opt-out marker has no consumer.
    def unenroll
      return enrollment_not_allowed_error unless NamespaceEnrollment.enrollment_allowed?(namespace)
      return destroy_enrollment unless paid_experience?

      existing = NamespaceEnrollment.find_by_namespace_id(namespace.id)
      return already_unenrolled_response if existing && !existing.enabled?

      # Explicit false: the column defaults to true, which would wrongly claim
      # beta membership on a record that only exists to mark the opt-out.
      # `enroll` re-evaluates the cohort if the namespace ever re-enrolls.
      enrollment = existing || NamespaceEnrollment.new(namespace: namespace, beta: false)

      # Add-on intent must not survive the opt-out, or any later re-enroll
      # (e.g. the trial chain) would silently restore the paid state.
      enrollment.update!(disabled_at: Time.current, add_on_requested_at: nil)

      clear_entitlement_cache
      unenroll_audit_event

      ServiceResponse.success
    rescue ActiveRecord::RecordNotUnique
      already_unenrolled_response
    end

    # Add-on conversion: enrolls (when needed) and stamps the paid intent.
    # The success payload carries a rollback token capturing the pre-call
    # shape for revert_add_on_intent, so a failed enable can restore an
    # opt-out or remove a record that did not exist before the click.
    def enroll_with_add_on_intent
      existing = NamespaceEnrollment.find_by_namespace_id(namespace.id)
      rollback = existing&.slice(:disabled_at, :add_on_requested_at) || :destroy

      result = enroll

      # "Already enrolled" is the expected shape for trial-chain or beta
      # enrollees; only a forbidden answer means enrollment cannot happen.
      return result if result.error? && result.reason == :forbidden

      begin
        enrollment = NamespaceEnrollment.find_by_namespace_id(namespace.id)
        stamped = enrollment.add_on_requested_at.nil?
        enrollment.update!(add_on_requested_at: Time.current) if stamped
      rescue ActiveRecord::ActiveRecordError
        # A stamp failure raises before the rollback token reaches the caller,
        # so the enroll write must be compensated here or it leaks. Scoped to
        # persistence errors so a programming error is not masked as a rollback.
        revert_add_on_intent(rollback)
        raise
      end

      ServiceResponse.success(payload: { enrollment: enrollment, rollback: rollback, stamped: stamped })
    end

    # Restores the shape captured by enroll_with_add_on_intent: clearing only
    # the intent stamp would leave a re-enabled opt-out undone.
    def revert_add_on_intent(rollback)
      enrollment = NamespaceEnrollment.find_by_namespace_id(namespace.id)
      return ServiceResponse.success unless enrollment

      rollback == :destroy ? enrollment.destroy! : enrollment.update!(rollback)

      # enroll audited these two shapes (new row / re-enabled opt-out), so the
      # undo must audit too, or the log claims an enrollment that never stuck.
      revert_enrollment_audit_event if rollback == :destroy || rollback[:disabled_at].present?

      ServiceResponse.success
    end

    # Audited separately from enrollment: the conversion is the billing-
    # affecting action, and the trial-chain shape never re-audits enroll.
    def audit_add_on_conversion
      audit_event(name: 'secrets_manager_add_on_enable', message: 'Enabled Secrets Manager paid add-on')
    end

    private

    attr_reader :namespace, :current_user

    def paid_experience?
      ::Feature.enabled?(:secrets_manager_paid_experience, namespace)
    end

    # Namespaces that enroll before the paid experience reaches them are part of the free beta cohort.
    def beta_enrollment?
      !paid_experience?
    end

    def destroy_enrollment
      enrollment = NamespaceEnrollment.find_by_namespace_id(namespace.id)
      return not_found_response unless enrollment

      enrollment.destroy!
      clear_entitlement_cache
      unenroll_audit_event

      ServiceResponse.success
    end

    # The entitlement resolver reads enrollment state (add-on intent, beta
    # cohort) and CI job registration caches its answer across requests, so a
    # stale entry would keep granting secrets access for up to the TTL after
    # the opt-out.
    def clear_entitlement_cache
      ::SecretsManagement::Entitlement::Resolver.clear_cache(namespace)
    end

    def unenroll_audit_event
      audit_event(name: 'secrets_manager_namespace_unenroll', message: 'Unenrolled namespace from Secrets Manager')
    end

    def revert_enrollment_audit_event
      audit_event(
        name: 'secrets_manager_namespace_unenroll',
        message: 'Reverted Secrets Manager enrollment after failed add-on enable'
      )
    end

    def not_found_response
      ServiceResponse.error(message: 'Enrollment not found.', reason: :not_found)
    end

    def audit_event(name:, message:)
      ::Gitlab::Audit::Auditor.audit({
        name: name,
        author: current_user,
        scope: namespace,
        target: namespace,
        message: message
      })
    end

    def enrollment_not_allowed_error
      ServiceResponse.error(message: 'Namespace enrollment is not allowed.', reason: :forbidden)
    end

    def already_enrolled_response
      ServiceResponse.error(message: 'Namespace is already enrolled.')
    end

    def already_unenrolled_response
      ServiceResponse.error(message: 'Namespace is already unenrolled.')
    end
  end
end
