# frozen_string_literal: true

# Requires the following to be defined by the including context:
#   - `audit_scope`: the project or group owning the variables
#   - `auth_user`: a user allowed to read the variable values
#   - `variable_key`: key of a variable whose value is returned
#   - `hidden_variable_key`: key of a hidden variable owned by `audit_scope`
#   - `#variables_query(fields)`: builds a query selecting `fields` on the
#     variable nodes of `audit_scope`
RSpec.shared_examples 'auditing CI/CD variable value access' do
  before do
    stub_licensed_features(audit_events: true)
    allow(::Gitlab::Audit::Auditor).to receive(:audit).and_call_original
  end

  def expect_variable_audit(**attributes)
    expect(::Gitlab::Audit::Auditor).to receive(:audit)
      .with(hash_including(name: 'variable_viewed_graphql', **attributes))
  end

  def expect_no_variable_audit
    expect(::Gitlab::Audit::Auditor).not_to receive(:audit)
      .with(hash_including(name: 'variable_viewed_graphql'))
  end

  context 'when a variable value is returned' do
    it 'audits the accessed key once for the variable owner' do
      expect_variable_audit(
        author: auth_user,
        scope: audit_scope,
        target: audit_scope,
        target_details: variable_key,
        message: 'CI/CD variables accessed with GraphQL',
        additional_details: {
          api_type: 'graphql',
          accessed_keys: [variable_key],
          hidden_keys: [hidden_variable_key],
          truncated: false
        }
      )

      post_graphql(variables_query(%w[key value]), current_user: auth_user)
    end
  end

  context 'when the value field is selected more than once through aliases' do
    it 'audits the accessed key only once' do
      expect_variable_audit(
        additional_details: hash_including(accessed_keys: [variable_key])
      )

      post_graphql(variables_query(%w[key a: value b: value]), current_user: auth_user)
    end
  end

  context 'when the value field is not selected' do
    it 'does not audit' do
      expect_no_variable_audit

      post_graphql(variables_query(%w[key]), current_user: auth_user)
    end
  end

  context 'when the feature flag is disabled' do
    before do
      stub_feature_flags(audit_ci_variable_value_access: false)
    end

    it 'does not audit' do
      expect_no_variable_audit

      post_graphql(variables_query(%w[key value]), current_user: auth_user)
    end
  end
end
