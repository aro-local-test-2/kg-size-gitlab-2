<script>
import { GlModal, GlLink, GlSprintf } from '@gitlab/ui';
import { __, s__ } from '~/locale';
import { helpPagePath } from '~/helpers/help_page_helper';

export default {
  name: 'StartTrialModal',
  components: {
    GlModal,
    GlLink,
    GlSprintf,
  },
  props: {
    visible: {
      type: Boolean,
      required: true,
    },
  },
  emits: ['start-trial', 'hide'],
  title: s__('SecretsManager|Start free 30-day trial of GitLab Secrets Manager'),
  actionPrimary: {
    text: __('Start 30-day trial'),
    attributes: { variant: 'confirm' },
  },
  actionCancel: {
    text: __('Cancel'),
  },
  GITLAB_CREDITS_DOCS_LINK: helpPagePath('subscriptions/gitlab_credits'),
  SECRETS_MANAGER_BILLING_DOCS_LINK: helpPagePath('ci/secrets/secrets_manager/credit_usage'),
};
</script>
<template>
  <gl-modal
    modal-id="start-secrets-manager-trial-modal"
    :visible="visible"
    :title="$options.title"
    :action-primary="$options.actionPrimary"
    :action-cancel="$options.actionCancel"
    @primary="$emit('start-trial')"
    @hidden="$emit('hide')"
  >
    <p>
      {{
        s__(
          'SecretsManager|You will be granted 500 trial credits for a period of 30 days for use across all projects and subgroups in your instance.',
        )
      }}
    </p>
    <p>
      <gl-sprintf
        :message="
          s__(
            'SecretsManager|After you use up all your trial credits or your trial period ends, you need %{linkStart}GitLab Credits%{linkEnd} to continue using GitLab Secrets Manager as a paid capability. To avoid a disruption at the end of your trial, contact your subscription owner to make sure you have purchased a Monthly Commitment of GitLab Credits or accepted on-demand billing. You can disable this feature any time in your settings to avoid credit consumption.',
          )
        "
      >
        <template #link="{ content }">
          <gl-link :href="$options.GITLAB_CREDITS_DOCS_LINK" target="_blank">{{ content }}</gl-link>
        </template>
      </gl-sprintf>
    </p>
    <p>
      <gl-link :href="$options.SECRETS_MANAGER_BILLING_DOCS_LINK" target="_blank">
        {{ s__('SecretsManager|How does GitLab Secrets Manager use GitLab Credits?') }}
      </gl-link>
    </p>
  </gl-modal>
</template>
