# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'groups/settings/secure/show', feature_category: :secrets_management do
  let(:group) { build_stubbed(:group) }

  let(:paid_description) do
    s_('SecretsManager|Enable GitLab Secrets Manager for all groups and projects within this namespace.')
  end

  let(:beta_description) do
    s_('SecretsManagerPermissions|Allow the secrets manager to be enabled in any project or subgroup in this group.')
  end

  let(:self_managed_description) do
    s_('SecretsManagerPermissions|Store secrets in the secrets manager, ' \
      'which can then be fetched by any project in this group and its subgroups.')
  end

  before do
    assign(:group, group)
    allow(view).to receive(:current_user).and_return(build_stubbed(:user))
    # Isolate this view's own chrome; the partials have their own specs.
    stub_template 'groups/settings/_dependency_firewall.html.haml' => ''
    stub_template 'groups/settings/_secret_manager.html.haml' => ''
    stub_saas_features(gitlab_com_subscriptions: true)
    allow(view).to receive_messages(
      secrets_manager_available_for_group?: true,
      allow_secrets_manager_namespace_enrollment?: false
    )
  end

  context 'when the Secrets Manager setting is available for a top-level group' do
    # Feature flags are enabled by default in specs, so this is the paid experience.
    it 'renders the block with the heading, New badge, anchor id, and paid description', :aggregate_failures do
      render

      expect(rendered).to have_css('section#js-secrets-manager-settings')
      expect(rendered).to have_content(s_('SecretsManager|GitLab Secrets Manager'))
      expect(rendered).to have_content(_('New'))
      expect(rendered).to have_content(paid_description)
    end

    context 'when the paid experience is disabled' do
      before do
        stub_feature_flags(secrets_manager_paid_experience: false)
      end

      it 'renders the beta description' do
        render

        expect(rendered).to have_content(beta_description)
      end
    end
  end

  context 'when the group is not enrollable (self-managed top-level group)' do
    before do
      stub_saas_features(gitlab_com_subscriptions: false)
    end

    it 'renders the feature description regardless of the paid experience flag', :aggregate_failures do
      render

      expect(rendered).to have_content(self_managed_description)
      expect(rendered).not_to have_content(paid_description)
    end

    context 'when the paid experience is disabled' do
      before do
        stub_feature_flags(secrets_manager_paid_experience: false)
      end

      it 'still renders the feature description' do
        render

        expect(rendered).to have_content(self_managed_description)
      end
    end
  end

  context 'when the group is not a top-level group' do
    let(:group) { build_stubbed(:group, :nested) }

    it 'does not render the Secrets Manager settings block' do
      render

      expect(rendered).not_to have_css('section#js-secrets-manager-settings')
    end
  end

  context 'when the Secrets Manager is not available for the group' do
    before do
      allow(view).to receive_messages(
        secrets_manager_available_for_group?: false,
        allow_secrets_manager_namespace_enrollment?: false
      )
    end

    it 'does not render the Secrets Manager settings block' do
      render

      expect(rendered).not_to have_css('section#js-secrets-manager-settings')
    end
  end

  context 'when only namespace enrollment is allowed (SaaS beta, not yet enrolled)' do
    before do
      allow(view).to receive_messages(
        secrets_manager_available_for_group?: false,
        allow_secrets_manager_namespace_enrollment?: true
      )
    end

    it 'renders the Secrets Manager settings block' do
      render

      expect(rendered).to have_css('section#js-secrets-manager-settings')
    end
  end
end
