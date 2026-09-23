# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['SecretsManagerEntitlement'], feature_category: :secrets_management do
  let(:expected_fields) do
    %i[
      state
      blocked_reason
      trial_started_at
      trial_expires_at
      credits_remaining
      credits_total
      on_demand_enabled
      beta_program_ended
      beta_window_eligible
      offline_license
    ]
  end

  specify do
    expect(described_class.graphql_name).to eq('SecretsManagerEntitlement')
    expect(described_class).to have_graphql_fields(*expected_fields)
  end

  it 'requires a non-null state' do
    expect(described_class.fields['state'].type.to_type_signature).to eq('SecretsManagerEntitlementState!')
  end

  it 'exposes blockedReason as nullable' do
    signature = described_class.fields['blockedReason'].type.to_type_signature
    expect(signature).to eq('SecretsManagerEntitlementBlockedReason')
  end

  it 'exposes betaProgramEnded as nullable' do
    signature = described_class.fields['betaProgramEnded'].type.to_type_signature
    expect(signature).to eq('Boolean')
  end

  it 'exposes betaWindowEligible as nullable' do
    signature = described_class.fields['betaWindowEligible'].type.to_type_signature
    expect(signature).to eq('Boolean')
  end

  it 'exposes offlineLicense as nullable' do
    signature = described_class.fields['offlineLicense'].type.to_type_signature
    expect(signature).to eq('Boolean')
  end

  describe 'Adapter#offline_license' do
    let(:adapter) do
      described_class::Adapter.new(entitlement: ::SecretsManagement::Entitlement.new(state: :blocked,
        blocked_reason: :subscription_grace_period_expired), group: nil)
    end

    let(:online_license) { instance_double(License, online_cloud_license?: true) }
    let(:offline_license) { instance_double(License, online_cloud_license?: false) }

    where(:saas, :license, :expected) do
      [
        [true, ref(:online_license), nil],
        [false, ref(:online_license), false],
        [false, ref(:offline_license), true],
        [false, nil, true]
      ]
    end

    with_them do
      before do
        stub_saas_features(gitlab_com_subscriptions: saas)
        allow(::License).to receive(:current).and_return(license)
      end

      it 'is derived from the license, not the entitlement state' do
        expect(adapter.offline_license).to eq(expected)
      end
    end
  end

  describe 'granular token boundaries' do
    let(:directives) { described_class.directives.select { |d| d.is_a?(::Directives::Authz::GranularScope) } }

    # The same type is returned for a top-level group and, with a nil group,
    # for the instance-wide entitlement on self-managed.
    it 'accepts a group or the instance as boundary', :aggregate_failures do
      expect(directives.map { |d| d.arguments[:boundary_type] }).to contain_exactly('group', 'instance')
      expect(directives.map { |d| d.arguments[:permissions] }).to all(eq(%w[read_secrets_manager]))
    end
  end

  it 'exposes credit fields as Float to preserve fractional balances' do
    expect(described_class.fields['creditsRemaining'].type.to_type_signature).to eq('Float')
    expect(described_class.fields['creditsTotal'].type.to_type_signature).to eq('Float')
  end
end
