<script>
import { GlToggle } from '@gitlab/ui';
import { s__ } from '~/locale';
import { createAlert, VARIANT_INFO } from '~/alert';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { TYPE_ORGANIZATION } from '~/graphql_shared/constants';
import { scrollUp } from '~/lib/utils/scroll_utils';
import SettingsBlock from '~/vue_shared/components/settings/settings_block.vue';
import organizationUpdateMutation from '~/organizations/settings/general/graphql/mutations/organization_update.mutation.graphql';

export default {
  name: 'PolicyStoreSettings',
  components: { GlToggle, SettingsBlock },
  inject: ['organization', 'policyStoreExperimentEnabled'],
  props: {
    id: {
      type: String,
      required: true,
    },
    expanded: {
      type: Boolean,
      required: true,
    },
  },
  emits: ['toggle-expand'],
  i18n: {
    title: s__('PolicyStore|Policy store'),
    description: s__('PolicyStore|Control the Policy store experiment for this organization.'),
    toggleLabel: s__('PolicyStore|Enable the Policy store experiment'),
    toggleHelp: s__(
      'PolicyStore|Members of this organization can author and manage policies in the Policy store.',
    ),
  },
  data() {
    return {
      enabled: Boolean(this.policyStoreExperimentEnabled),
      saving: false,
    };
  },
  methods: {
    async onToggle(enabled) {
      this.saving = true;

      try {
        const {
          data: {
            organizationUpdate: { errors },
          },
        } = await this.$apollo.mutate({
          mutation: organizationUpdateMutation,
          variables: {
            input: {
              id: convertToGraphQLId(TYPE_ORGANIZATION, this.organization.id),
              policyStoreExperimentEnabled: enabled,
            },
          },
        });

        if (errors.length) {
          createAlert({ message: errors.join(' ') });
        } else {
          this.enabled = enabled;
          createAlert({
            message: s__('PolicyStore|Policy store experiment setting updated.'),
            variant: VARIANT_INFO,
          });
        }
      } catch (error) {
        createAlert({
          message: s__(
            'PolicyStore|An error occurred updating the Policy store setting. Please try again.',
          ),
          error,
          captureError: true,
        });
      } finally {
        this.saving = false;
        // The alert renders at the top of the document and this is the last
        // section on the page, so the feedback is invisible without this.
        scrollUp();
      }
    },
  },
};
</script>

<template>
  <settings-block
    :id="id"
    :title="$options.i18n.title"
    :expanded="expanded"
    data-testid="policy-store-settings"
    @toggle-expand="$emit('toggle-expand', $event)"
  >
    <template #description>{{ $options.i18n.description }}</template>
    <template #default>
      <gl-toggle
        :value="enabled"
        :is-loading="saving"
        :disabled="saving"
        :label="$options.i18n.toggleLabel"
        :help="$options.i18n.toggleHelp"
        data-testid="policy-store-experiment-toggle"
        @change="onToggle"
      />
    </template>
  </settings-block>
</template>
