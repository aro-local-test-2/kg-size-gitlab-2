<script>
import { GlModal, GlLink, GlSprintf } from '@gitlab/ui';
import { __, s__ } from '~/locale';
import { helpPagePath } from '~/helpers/help_page_helper';

export default {
  name: 'EnableAddOnModal',
  components: {
    GlModal,
    GlLink,
    GlSprintf,
  },
  inject: ['subscriptionsUrl'],
  props: {
    visible: {
      type: Boolean,
      required: true,
    },
    onDemandEnabled: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['enable', 'hide'],
  computed: {
    title() {
      return this.onDemandEnabled
        ? s__('SecretsManager|Enable GitLab Secrets Manager with GitLab Credits')
        : s__('SecretsManager|Your group subscription does not have GitLab Credits available');
    },
    actionPrimary() {
      if (!this.onDemandEnabled) {
        return null;
      }

      return {
        text: s__('SecretsManager|Enable GitLab Secrets Manager'),
        attributes: { variant: 'confirm' },
      };
    },
    actionCancel() {
      return this.onDemandEnabled ? { text: __('Cancel') } : null;
    },
  },
  SECRETS_MANAGER_BILLING_DOCS_LINK: helpPagePath('ci/secrets/secrets_manager/credit_usage'),
};
</script>
<template>
  <gl-modal
    modal-id="enable-secrets-manager-add-on-modal"
    :visible="visible"
    :title="title"
    :hide-footer="!onDemandEnabled"
    :action-primary="actionPrimary"
    :action-cancel="actionCancel"
    @primary="$emit('enable')"
    @hidden="$emit('hide')"
  >
    <template v-if="onDemandEnabled">
      <p>
        {{
          s__(
            'SecretsManager|You pay for GitLab Secrets Manager through GitLab Credits. Usage across all projects and subgroups is combined.',
          )
        }}
      </p>
      <ul>
        <li>
          {{ s__('SecretsManager|Storing secrets and reading them consumes GitLab Credits.') }}
        </li>
        <li>
          {{
            s__(
              'SecretsManager|Credits are drawn from your Monthly Commitment Pool first. When that pool is exhausted, usage continues and is billed as on-demand credits.',
            )
          }}
        </li>
        <li>{{ s__("SecretsManager|Spend caps don't limit Secrets Manager usage.") }}</li>
      </ul>
    </template>
    <p v-else>
      <gl-sprintf
        :message="
          s__(
            'SecretsManager|Contact your subscription owner or visit the %{linkStart}Customer Portal%{linkEnd} to purchase a Monthly Commitment of GitLab Credits or accept on-demand billing. After your subscription owner has completed this task, you can enable GitLab Secrets Manager with GitLab Credits.',
          )
        "
      >
        <template #link="{ content }">
          <gl-link :href="subscriptionsUrl" target="_blank">{{ content }}</gl-link>
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
