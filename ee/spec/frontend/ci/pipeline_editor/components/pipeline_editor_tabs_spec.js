import { mount, shallowMount } from '@vue/test-utils';
import { GlAlert, GlButton } from '@gitlab/ui';
import VueApollo from 'vue-apollo';
import Vue from 'vue';
import PipelineAccountVerificationAlert from 'ee/vue_shared/components/pipeline_account_verification_alert.vue';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import EditorTab from '~/ci/pipeline_editor/components/ui/editor_tab.vue';
import PipelineEditorTabs from '~/ci/pipeline_editor/components/pipeline_editor_tabs.vue';
import getAppStatus from '~/ci/pipeline_editor/graphql/queries/client/app_status.query.graphql';
import { EDITOR_APP_STATUS_VALID } from '~/ci/pipeline_editor/constants';
import {
  mockCiYml,
  mockLintResponse,
} from '../../../../../../spec/frontend/ci/pipeline_editor/mock_data';

Vue.use(VueApollo);
Vue.config.ignoredElements = ['gl-emoji'];

describe('Pipeline editor tabs component', () => {
  let wrapper;
  let mockApollo;
  const MockTextEditor = {
    template: '<div />',
  };

  const findVerificationAlert = () => wrapper.findComponent(PipelineAccountVerificationAlert);

  const createComponent = async ({ provide = {}, mountFn = shallowMount } = {}) => {
    mockApollo = createMockApollo();
    mockApollo.clients.defaultClient.cache.writeQuery({
      query: getAppStatus,
      data: { app: { __typename: 'AppData', status: EDITOR_APP_STATUS_VALID } },
    });

    wrapper = mountFn(PipelineEditorTabs, {
      apolloProvider: mockApollo,
      propsData: {
        ciConfigData: mockLintResponse,
        ciFileContent: mockCiYml,
        showHelpDrawer: false,
        showJobAssistantDrawer: false,
      },
      provide: {
        aiChatAvailable: false,
        ciConfigPath: '/path/to/ci-config',
        ciLintPath: '/path/to/ci-lint',
        currentBranch: 'main',
        projectFullPath: '/path/to/project',
        simulatePipelineHelpPagePath: 'path/to/help/page',
        totalBranches: 1,
        identityVerificationRequired: false,
        identityVerificationPath: '/-/identity_verification',
        ...provide,
      },
      stubs: {
        TextEditor: MockTextEditor,
        EditorTab,
        CiValidate: true,
        CiConfigMergedPreview: true,
        'gl-emoji': true,
      },
    });

    await waitForPromises();
  };

  it('does not render the alert content when identity verification is not required', async () => {
    await createComponent({ provide: { identityVerificationRequired: false }, mountFn: mount });

    expect(findVerificationAlert().findComponent(GlAlert).exists()).toBe(false);
  });

  it('renders with the expected copy, button variant, and sticky/new-tab behavior when required', async () => {
    await createComponent({ provide: { identityVerificationRequired: true }, mountFn: mount });

    const alert = findVerificationAlert().findComponent(GlAlert);
    const button = findVerificationAlert().findComponent(GlButton);

    expect(alert.exists()).toBe(true);
    expect(alert.props('sticky')).toBe(true);
    expect(alert.text()).toContain('Verify your identity to commit this change');
    expect(alert.text()).toContain(
      'This step is separate from the verification you completed during registration.',
    );
    expect(button.props('variant')).toBe('default');
    expect(button.attributes('target')).toBe('_blank');
    expect(button.text()).toBe('Verify identity');
  });
});
