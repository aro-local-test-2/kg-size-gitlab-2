import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';
import updateAiFeatureSettings from 'ee/ai/instance_model_selection/feature_settings/graphql/mutations/update_ai_feature_setting.mutation.graphql';
import getAiFeatureSettingsQuery from 'ee/ai/instance_model_selection/feature_settings/graphql/queries/get_ai_feature_settings.query.graphql';
import DuoSelfHostedBatchSettingsUpdater from 'ee/ai/instance_model_selection/feature_settings/components/batch_settings_updater.vue';
import BatchUpdateButton from 'ee/ai/shared/feature_settings/batch_update_button.vue';
import {
  mockDuoChatFeatureSettings,
  mockGitlabManagedModels,
  mockInstanceModelSelectionFeatureSettings,
} from './mock_data';

Vue.use(VueApollo);
jest.mock('~/alert');

describe('DuoSelfHostedBatchSettingsUpdater', () => {
  let wrapper;
  let mockApollo;

  const selectedFeatureSetting = mockDuoChatFeatureSettings[0];
  const mockToastShow = jest.fn();

  const updateFeatureSettingsSuccessHandler = jest.fn().mockResolvedValue({
    data: {
      aiFeatureSettingUpdate: {
        errors: [],
      },
    },
  });

  const getFeatureSettingsSuccessHandler = jest.fn().mockResolvedValue({
    data: {
      aiFeatureSettings: {
        nodes: mockDuoChatFeatureSettings,
      },
    },
  });

  const createComponent = ({
    apolloHandlers = [
      [updateAiFeatureSettings, updateFeatureSettingsSuccessHandler],
      [getAiFeatureSettingsQuery, getFeatureSettingsSuccessHandler],
    ],
    provide = {},
    props = {},
  } = {}) => {
    mockApollo = createMockApollo([...apolloHandlers]);
    wrapper = mountExtended(DuoSelfHostedBatchSettingsUpdater, {
      apolloProvider: mockApollo,
      provide: {
        canManageInstanceModelSelection: true,
        ...provide,
      },
      propsData: {
        selectedFeatureSetting,
        aiFeatureSettings: mockDuoChatFeatureSettings,
        ...props,
      },
      mocks: {
        $toast: {
          show: mockToastShow,
        },
      },
    });
  };

  const findBatchUpdateButton = () => wrapper.findComponent(BatchUpdateButton);
  const findUnassignedFeatureIcon = () => wrapper.findByTestId('warning-icon');
  const findUnassignedFeatureTooltip = () => wrapper.findByTestId('unassigned-feature-tooltip');

  it('renders `BatchUpdateButton` component', () => {
    createComponent();

    expect(findBatchUpdateButton().text()).toBe('Apply to all');
    expect(findBatchUpdateButton().props()).toEqual({
      tooltipTitle: 'Apply to all GitLab Duo Chat sub-features',
      disabled: false,
    });
  });

  describe('with GitLab managed models', () => {
    it('keeps the legacy vendored fallback enabled without GitLab managed model fields', async () => {
      const legacyVendoredFeatureSettings = mockDuoChatFeatureSettings.map((setting) => ({
        ...setting,
        provider: 'vendored',
        selfHostedModel: null,
      }));

      createComponent({
        props: {
          selectedFeatureSetting: legacyVendoredFeatureSettings[0],
          aiFeatureSettings: legacyVendoredFeatureSettings,
        },
      });

      expect(findBatchUpdateButton().props()).toEqual({
        tooltipTitle: 'Apply to all GitLab Duo Chat sub-features',
        disabled: false,
      });

      findBatchUpdateButton().vm.$emit('batch-update');
      await waitForPromises();

      expect(updateFeatureSettingsSuccessHandler).toHaveBeenCalledWith({
        input: {
          features: legacyVendoredFeatureSettings.map((setting) => setting.feature.toUpperCase()),
          provider: 'VENDORED',
          aiSelfHostedModelId: null,
          offeredModelRef: null,
        },
      });
    });

    it('shows an enabled batch update button for a compatible GitLab managed model', () => {
      createComponent({
        props: {
          selectedFeatureSetting: mockInstanceModelSelectionFeatureSettings[0],
          aiFeatureSettings: mockInstanceModelSelectionFeatureSettings,
        },
      });

      expect(findBatchUpdateButton().exists()).toBe(true);
      expect(findBatchUpdateButton().props()).toEqual({
        tooltipTitle: 'Apply to all GitLab Duo Chat sub-features',
        disabled: false,
      });
    });

    it('updates all settings with the selected GitLab managed model', async () => {
      createComponent({
        props: {
          selectedFeatureSetting: mockInstanceModelSelectionFeatureSettings[0],
          aiFeatureSettings: mockInstanceModelSelectionFeatureSettings,
        },
      });

      findBatchUpdateButton().vm.$emit('batch-update');
      await waitForPromises();

      expect(updateFeatureSettingsSuccessHandler).toHaveBeenCalledWith({
        input: {
          features: mockInstanceModelSelectionFeatureSettings.map((setting) =>
            setting.feature.toUpperCase(),
          ),
          provider: 'VENDORED',
          aiSelfHostedModelId: null,
          offeredModelRef: mockGitlabManagedModels[0].ref,
        },
      });
    });

    it('updates all settings with a self-hosted model when a managed default exists', async () => {
      const selfHostedFeatureSettingsWithManagedDefault = mockDuoChatFeatureSettings.map(
        (setting) => ({
          ...setting,
          defaultGitlabModel: mockGitlabManagedModels[0],
          validGitlabModels: { nodes: mockGitlabManagedModels },
        }),
      );

      createComponent({
        props: {
          selectedFeatureSetting: selfHostedFeatureSettingsWithManagedDefault[0],
          aiFeatureSettings: selfHostedFeatureSettingsWithManagedDefault,
        },
      });

      findBatchUpdateButton().vm.$emit('batch-update');
      await waitForPromises();

      expect(updateFeatureSettingsSuccessHandler).toHaveBeenCalledWith({
        input: {
          features: selfHostedFeatureSettingsWithManagedDefault.map((setting) =>
            setting.feature.toUpperCase(),
          ),
          provider: 'SELF_HOSTED',
          aiSelfHostedModelId: 'gid://gitlab/Ai::SelfHostedModel/1',
          offeredModelRef: null,
        },
      });
    });

    it('resets settings to their defaults without copying the selected row default', async () => {
      const defaultFeatureSettings = mockInstanceModelSelectionFeatureSettings.map(
        (setting, index) => ({
          ...setting,
          provider: 'unassigned',
          gitlabModel: null,
          defaultGitlabModel: mockGitlabManagedModels[index],
        }),
      );

      createComponent({
        props: {
          selectedFeatureSetting: defaultFeatureSettings[0],
          aiFeatureSettings: defaultFeatureSettings,
        },
      });

      expect(findBatchUpdateButton().props()).toEqual({
        tooltipTitle: 'Apply to all GitLab Duo Chat sub-features',
        disabled: false,
      });

      findBatchUpdateButton().vm.$emit('batch-update');
      await waitForPromises();

      expect(updateFeatureSettingsSuccessHandler).toHaveBeenCalledWith({
        input: {
          features: defaultFeatureSettings.map((setting) => setting.feature.toUpperCase()),
          provider: 'VENDORED',
          aiSelfHostedModelId: null,
          offeredModelRef: '',
        },
      });
    });

    it('disables the batch update button for GitLab default models when the user cannot manage instance models', () => {
      const defaultFeatureSettings = mockInstanceModelSelectionFeatureSettings.map((setting) => ({
        ...setting,
        provider: 'unassigned',
        gitlabModel: null,
        validGitlabModels: { nodes: [] },
      }));

      createComponent({
        provide: { canManageInstanceModelSelection: false },
        props: {
          selectedFeatureSetting: defaultFeatureSettings[0],
          aiFeatureSettings: defaultFeatureSettings,
        },
      });

      expect(findBatchUpdateButton().props('disabled')).toBe(true);
    });

    it('disables the batch update button when a GitLab managed model is incompatible', () => {
      const incompatibleFeatureSettings = mockInstanceModelSelectionFeatureSettings.map(
        (setting, index) => ({
          ...setting,
          validGitlabModels:
            index === 1 ? { nodes: mockGitlabManagedModels.slice(1) } : setting.validGitlabModels,
        }),
      );

      createComponent({
        props: {
          selectedFeatureSetting: incompatibleFeatureSettings[0],
          aiFeatureSettings: incompatibleFeatureSettings,
        },
      });

      expect(findBatchUpdateButton().props()).toEqual({
        tooltipTitle: 'This model cannot be applied to all GitLab Duo Chat sub-features',
        disabled: true,
      });
    });
  });

  describe('when the selected feature setting is unassigned', () => {
    beforeEach(() => {
      const unassignedFeatureSetting = {
        feature: 'duo_chat',
        title: 'General Chat',
        provider: 'unassigned',
      };

      createComponent({ props: { selectedFeatureSetting: unassignedFeatureSetting } });
    });

    it('disables the batch update button', () => {
      expect(findBatchUpdateButton().props()).toEqual({
        tooltipTitle: 'Assign a model to General Chat before applying to all',
        disabled: true,
      });
    });

    it('renders a warning tooltip and icon', () => {
      expect(findUnassignedFeatureIcon().exists()).toBe(true);
      expect(findUnassignedFeatureTooltip().attributes('title')).toBe(
        'Assign a model to enable this feature',
      );
    });

    it('renders the warning when GitLab managed model inventory is available without a default', () => {
      createComponent({
        props: {
          selectedFeatureSetting: {
            feature: 'duo_chat',
            title: 'General Chat',
            provider: 'unassigned',
            validGitlabModels: { nodes: mockGitlabManagedModels },
          },
        },
      });

      expect(findUnassignedFeatureIcon().exists()).toBe(true);
      expect(findUnassignedFeatureTooltip().exists()).toBe(true);
    });

    it('does not render the warning when a GitLab managed default is available', () => {
      createComponent({
        props: {
          selectedFeatureSetting: {
            feature: 'duo_chat',
            title: 'General Chat',
            provider: 'unassigned',
            defaultGitlabModel: mockGitlabManagedModels[0],
          },
        },
      });

      expect(findUnassignedFeatureIcon().exists()).toBe(false);
      expect(findUnassignedFeatureTooltip().exists()).toBe(false);
    });
  });

  it('disables batch update button if selected model is not compatible with all feature settings', () => {
    const incompatibleModel = { id: 'gid://gitlab/Ai::SelfHostedModel/999' };
    const featureSetting = {
      feature: 'duo_chat',
      title: 'General Chat',
      mainFeature: 'GitLab Duo Chat',
      provider: 'self_hosted',
      selfHostedModel: incompatibleModel,
    };

    createComponent({ props: { selectedFeatureSetting: featureSetting } });

    expect(findBatchUpdateButton().props()).toEqual({
      tooltipTitle: 'This model cannot be applied to all GitLab Duo Chat sub-features',
      disabled: true,
    });
  });

  it('disables batch update button if selected feature setting is disabled', () => {
    const disabledFeatureSetting = {
      feature: 'duo_chat',
      title: 'General Chat',
      provider: 'disabled',
    };

    createComponent({ props: { selectedFeatureSetting: disabledFeatureSetting } });

    expect(findBatchUpdateButton().props()).toEqual({
      tooltipTitle: 'Assign a model to General Chat before applying to all',
      disabled: true,
    });
  });

  describe('onClick', () => {
    beforeEach(async () => {
      createComponent();

      findBatchUpdateButton().vm.$emit('batch-update');
      await waitForPromises();
    });

    it('emits update-batch-saving-state events', () => {
      expect(wrapper.emitted('update-batch-saving-state')).toHaveLength(2);
    });

    it('invokes update mutation with correct input', () => {
      const features = mockDuoChatFeatureSettings.map((fs) => fs.feature.toUpperCase());

      expect(updateFeatureSettingsSuccessHandler).toHaveBeenCalledWith({
        input: {
          features,
          provider: 'SELF_HOSTED',
          aiSelfHostedModelId: 'gid://gitlab/Ai::SelfHostedModel/1',
          offeredModelRef: null,
        },
      });
    });

    describe('when the update succeeds', () => {
      it('refetches feature settings data', () => {
        expect(getFeatureSettingsSuccessHandler).toHaveBeenCalled();
      });

      it('triggers a success toast', () => {
        expect(mockToastShow).toHaveBeenCalledWith(
          'Successfully updated all GitLab Duo Chat features',
        );
      });

      it('does not HTML-escape special characters in the toast message', async () => {
        createComponent({
          props: {
            selectedFeatureSetting: {
              ...selectedFeatureSetting,
              mainFeature: 'Agents & flows',
            },
          },
        });

        findBatchUpdateButton().vm.$emit('batch-update');
        await waitForPromises();

        expect(mockToastShow).toHaveBeenCalledWith(
          'Successfully updated all Agents & flows features',
        );
      });
    });

    describe('when the update does not succeed', () => {
      describe('due to a general error', () => {
        it('displays an error message', async () => {
          createComponent({
            apolloHandlers: [
              [updateAiFeatureSettings, jest.fn().mockRejectedValue('ERROR')],
              [getAiFeatureSettingsQuery, getFeatureSettingsSuccessHandler],
            ],
          });

          findBatchUpdateButton().vm.$emit('batch-update');
          await waitForPromises();

          expect(createAlert).toHaveBeenCalledWith(
            expect.objectContaining({
              message:
                'An error occurred while updating the GitLab Duo Chat sub-feature settings. Please try again.',
            }),
          );
        });

        it('does not HTML-escape special characters in the error message', async () => {
          createComponent({
            apolloHandlers: [
              [updateAiFeatureSettings, jest.fn().mockRejectedValue('ERROR')],
              [getAiFeatureSettingsQuery, getFeatureSettingsSuccessHandler],
            ],
            props: {
              selectedFeatureSetting: {
                ...selectedFeatureSetting,
                mainFeature: 'Agents & flows',
              },
            },
          });

          findBatchUpdateButton().vm.$emit('batch-update');
          await waitForPromises();

          expect(createAlert).toHaveBeenCalledWith(
            expect.objectContaining({
              message:
                'An error occurred while updating the Agents & flows sub-feature settings. Please try again.',
            }),
          );
        });
      });

      describe('due to a business logic error', () => {
        const updateFeatureSettingsErrorHandler = jest.fn().mockResolvedValue({
          data: {
            aiFeatureSettingUpdate: {
              errors: ['An error occured'],
            },
          },
        });

        it('displays an error message', async () => {
          createComponent({
            apolloHandlers: [
              [updateAiFeatureSettings, updateFeatureSettingsErrorHandler],
              [getAiFeatureSettingsQuery, getFeatureSettingsSuccessHandler],
            ],
          });

          findBatchUpdateButton().vm.$emit('batch-update');
          await waitForPromises();

          expect(createAlert).toHaveBeenCalledWith(
            expect.objectContaining({
              message:
                'An error occurred while updating the GitLab Duo Chat sub-feature settings. Please try again.',
            }),
          );
        });
      });
    });
  });
});
