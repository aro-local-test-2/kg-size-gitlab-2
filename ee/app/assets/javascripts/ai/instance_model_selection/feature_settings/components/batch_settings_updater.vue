<script>
import { GlIcon, GlTooltipDirective, GlToastMixin } from '@gitlab/ui';
import { createAlert } from '~/alert';
import { s__, sprintf } from '~/locale';
import BatchUpdateButton from 'ee/ai/shared/feature_settings/batch_update_button.vue';
import updateAiFeatureSettings from '../graphql/mutations/update_ai_feature_setting.mutation.graphql';
import getAiFeatureSettingsQuery from '../graphql/queries/get_ai_feature_settings.query.graphql';
import { GITLAB_DEFAULT_MODEL, PROVIDERS } from '../constants';

export default {
  name: 'InstanceModelSelectionBatchSettingsUpdater',
  components: {
    BatchUpdateButton,
    GlIcon,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  mixins: [GlToastMixin],
  inject: ['canManageInstanceModelSelection'],
  props: {
    aiFeatureSettings: {
      type: Array,
      required: true,
    },
    selectedFeatureSetting: {
      type: Object,
      required: true,
    },
  },
  emits: ['update-batch-saving-state'],
  computed: {
    selectedFeatureSettingUnassigned() {
      const { defaultGitlabModel, provider } = this.selectedFeatureSetting;

      return provider === PROVIDERS.UNASSIGNED && !defaultGitlabModel;
    },
    selectedFeatureSettingDisabled() {
      return this.selectedFeatureSetting.provider === PROVIDERS.DISABLED;
    },
    selectedFeatureSettingSelfHosted() {
      return this.selectedFeatureSetting.provider === PROVIDERS.SELF_HOSTED;
    },
    selectedGitlabModelRef() {
      return this.selectedFeatureSetting.gitlabModel?.ref ?? GITLAB_DEFAULT_MODEL;
    },
    selectedFeatureSettingUsesGitlabManagedModels() {
      const { defaultGitlabModel, gitlabModel, provider } = this.selectedFeatureSetting;

      return (
        (provider === PROVIDERS.VENDORED && Boolean(gitlabModel || defaultGitlabModel)) ||
        (provider === PROVIDERS.UNASSIGNED && Boolean(defaultGitlabModel))
      );
    },
    selectedModelCompatibleWithAllSettings() {
      const selectedModelId = this.selectedFeatureSetting.selfHostedModel?.id;

      if (!selectedModelId) return false;

      return this.aiFeatureSettings.every((fs) => {
        const validModels = fs.validModels?.nodes?.map((model) => model.id);

        return validModels.includes(selectedModelId);
      });
    },
    selectedGitlabModelCompatibleWithAllSettings() {
      if (this.selectedGitlabModelRef === GITLAB_DEFAULT_MODEL) return true;

      return this.aiFeatureSettings.every((setting) => {
        const refs = setting.validGitlabModels?.nodes?.map(({ ref }) => ref) ?? [];

        return refs.includes(this.selectedGitlabModelRef);
      });
    },
    canBatchUpdate() {
      if (this.selectedFeatureSettingDisabled) {
        return false;
      }

      if (this.selectedFeatureSettingUsesGitlabManagedModels) {
        return (
          this.canManageInstanceModelSelection && this.selectedGitlabModelCompatibleWithAllSettings
        );
      }

      if (this.selectedFeatureSetting.provider === PROVIDERS.VENDORED) {
        return true;
      }

      return this.selectedModelCompatibleWithAllSettings;
    },
    tooltipTitle() {
      let tooltipText;

      if (this.canBatchUpdate) {
        tooltipText = s__('AdminSelfHostedModels|Apply to all %{mainFeature} sub-features');
      } else if (this.selectedFeatureSettingUnassigned || this.selectedFeatureSettingDisabled) {
        tooltipText = s__(
          'AdminSelfHostedModels|Assign a model to %{subFeature} before applying to all',
        );
      } else {
        tooltipText = s__(
          'AdminSelfHostedModels|This model cannot be applied to all %{mainFeature} sub-features',
        );
      }

      return sprintf(tooltipText, {
        mainFeature: this.selectedFeatureSetting.mainFeature,
        subFeature: this.selectedFeatureSetting.title,
      });
    },
    successMessage() {
      return sprintf(
        s__('AdminSelfHostedModels|Successfully updated all %{mainFeature} features'),
        {
          mainFeature: this.selectedFeatureSetting.mainFeature,
        },
        false,
      );
    },
    errorMessage() {
      return sprintf(
        s__(
          'AdminSelfHostedModels|An error occurred while updating the %{mainFeature} sub-feature settings. Please try again.',
        ),
        { mainFeature: this.selectedFeatureSetting.mainFeature },
        false,
      );
    },
  },
  warningTooltipTitle: s__('AdminSelfHostedModels|Assign a model to enable this feature'),
  methods: {
    async onClick() {
      this.$emit('update-batch-saving-state', true);

      try {
        const features = this.aiFeatureSettings.map((fs) => fs.feature.toUpperCase());
        const usesGitlabManagedModels = this.selectedFeatureSettingUsesGitlabManagedModels;
        const provider = usesGitlabManagedModels
          ? PROVIDERS.VENDORED
          : this.selectedFeatureSetting.provider;
        const aiSelfHostedModelId = this.selectedFeatureSettingSelfHosted
          ? this.selectedFeatureSetting.selfHostedModel?.id
          : null;
        const offeredModelRef = usesGitlabManagedModels ? this.selectedGitlabModelRef : null;

        const { data } = await this.$apollo.mutate({
          mutation: updateAiFeatureSettings,
          variables: {
            input: {
              features,
              provider: provider.toUpperCase(),
              aiSelfHostedModelId,
              offeredModelRef,
            },
          },
          refetchQueries: [{ query: getAiFeatureSettingsQuery }],
        });

        if (data) {
          const { errors } = data.aiFeatureSettingUpdate;

          if (errors.length > 0) {
            throw new Error(errors[0]);
          }

          this.$toast.show(this.successMessage);
        }
      } catch (error) {
        createAlert({
          message: this.errorMessage,
          error,
          captureError: true,
        });
      } finally {
        this.$emit('update-batch-saving-state', false);
      }
    },
  },
};
</script>
<template>
  <div :class="{ 'gl-flex gl-w-full gl-justify-between': selectedFeatureSettingUnassigned }">
    <div
      v-if="selectedFeatureSettingUnassigned"
      v-gl-tooltip
      data-testid="unassigned-feature-tooltip"
      :title="$options.warningTooltipTitle"
    >
      <div
        class="gl-flex gl-h-7 gl-w-7 gl-items-center gl-justify-center gl-rounded-base gl-bg-orange-50"
      >
        <gl-icon
          data-testid="warning-icon"
          :aria-label="$options.warningTooltipTitle"
          name="warning"
          variant="warning"
          :size="16"
        />
      </div>
    </div>
    <batch-update-button
      :main-feature="selectedFeatureSetting.mainFeature"
      :disabled="!canBatchUpdate"
      :tooltip-title="tooltipTitle"
      @batch-update="onClick"
    />
  </div>
</template>
