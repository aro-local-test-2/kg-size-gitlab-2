# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['GovernPolicy'], feature_category: :security_policy_management do
  include GraphqlHelpers

  specify do
    expect(described_class).to have_graphql_fields(
      :id, :organization_id, :namespace_id, :name, :description, :version, :trigger_type,
      :rules, :policy_rego, :actions, :policy_scope, :scope_rego, :scope_dimensions, :mode,
      :lifecycle_state, :created_at, :updated_at
    )
  end

  describe '#policy_rego' do
    let(:rules) { [{ 'rego' => "package governance\ndeny := true\n" }] }

    let(:policy) do
      ::Gitlab::PolicyStore::Policy.new(
        id: 1, organization_id: 1, name: 'Gate', trigger_type: 'deployment_requested', rules: rules
      )
    end

    subject(:policy_rego) { resolve_field(:policy_rego, policy) }

    it 'merges the compiled rules into one governance module' do
      expect(policy_rego).to eq("package governance\ndeny := true\n")
    end

    context 'when the rules cannot be merged' do
      let(:rules) { [{ 'not_rego' => 'no compiled program' }] }

      it 'tracks the error and resolves to nil rather than failing the read' do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception)
          .with(instance_of(::Gitlab::PolicyStore::Error), policy_id: policy.id)

        expect(policy_rego).to be_nil
      end
    end
  end
end
