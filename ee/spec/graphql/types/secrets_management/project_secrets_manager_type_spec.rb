# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ProjectSecretsManager'], feature_category: :secrets_management do
  include GraphqlHelpers

  it { expect(described_class).to require_graphql_authorizations(:read_project_secrets_manager_status) }

  it 'has the expected fields' do
    expect(described_class).to have_graphql_fields(:project, :status, :read_only, :user_permissions)
  end

  describe 'readOnly' do
    let_it_be(:project) { create(:project) }
    let_it_be(:user) { create(:user, owner_of: project) }
    let_it_be(:secrets_manager) { create(:project_secrets_manager, project: project) }

    before do
      stub_licensed_features(native_secrets_management: true)
      stub_feature_flags(secrets_manager_paid_experience: false)
      allow(::SecretsManagement::Availability).to receive(:enabled_for_project?).with(project).and_return(true)
    end

    it 'is true when the database is read-only' do
      allow(::Gitlab::Database).to receive(:read_only?).and_return(true)

      expect(resolve_field(:read_only, secrets_manager, current_user: user)).to be(true)
    end

    it 'is false when the database is writable' do
      allow(::Gitlab::Database).to receive(:read_only?).and_return(false)

      expect(resolve_field(:read_only, secrets_manager, current_user: user)).to be(false)
    end
  end
end
