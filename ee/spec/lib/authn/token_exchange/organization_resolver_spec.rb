# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authn::TokenExchange::OrganizationResolver, feature_category: :system_access do
  let_it_be(:user) { create(:user) }

  subject(:resolved) { described_class.new(user).execute }

  context 'when the caller belongs to no Artifact Registry organization' do
    it 'falls back to the organization that owns the account' do
      expect(resolved).to eq(user.organization)
    end

    it 'falls back even when they belong to organizations without Artifact Registry' do
      create(:organization_user, organization: create(:organization), user: user)

      expect(resolved).to eq(user.organization)
    end
  end

  context 'when the caller belongs to exactly one Artifact Registry organization' do
    let_it_be(:organization) { create(:organization) }

    before_all do
      create(:artifact_registry_namespace_mapping, organization: organization)
      create(:organization_user, organization: organization, user: user)
    end

    it 'resolves to that organization, not the one owning the account', :aggregate_failures do
      expect(resolved).to eq(organization)
      expect(resolved).not_to eq(user.organization)
    end

    it 'ignores an Artifact Registry organization the caller does not belong to' do
      create(:artifact_registry_namespace_mapping, organization: create(:organization))

      expect(resolved).to eq(organization)
    end
  end

  context 'when the caller belongs to more than one Artifact Registry organization' do
    before do
      2.times do
        organization = create(:organization)
        create(:artifact_registry_namespace_mapping, organization: organization)
        create(:organization_user, organization: organization, user: user)
      end
    end

    # Refused rather than guessed: a token naming the wrong organization
    # resolves to a different principal in IAM and sees none of the caller's
    # roles.
    it 'refuses rather than picking one' do
      expect { resolved }.to raise_error(described_class::AmbiguousOrganizationError)
    end
  end
end
