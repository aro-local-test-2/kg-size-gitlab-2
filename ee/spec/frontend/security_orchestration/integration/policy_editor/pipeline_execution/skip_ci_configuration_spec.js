import { GlToggle } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import App from 'ee/security_orchestration/components/policy_editor/app.vue';
import * as urlUtils from '~/lib/utils/url_utility';
import waitForPromises from 'helpers/wait_for_promises';
import SkipCiSelector from 'ee/security_orchestration/components/policy_editor/skip_ci_selector.vue';
import { DEFAULT_ASSIGNED_POLICY_PROJECT } from 'ee/security_orchestration/constants';
import { DEFAULT_PROVIDE } from '../mocks/mocks';
import { verify } from '../utils';
import { createMockApolloProvider } from '../apollo_util';
import { mockPipelineExecutionSkipCiManifest } from './mocks';

describe('Skip ci for pipeline execution policy', () => {
  let wrapper;

  const createWrapper = ({ propsData = {}, provide = {}, glFeatures = {} } = {}) => {
    wrapper = mountExtended(App, {
      apolloProvider: createMockApolloProvider(),
      propsData: {
        assignedPolicyProject: DEFAULT_ASSIGNED_POLICY_PROJECT,
        ...propsData,
      },
      provide: {
        ...DEFAULT_PROVIDE,
        existingPolicy: null,
        glFeatures,
        ...provide,
      },
      stubs: {
        SourceEditor: true,
      },
    });
  };

  const findSkipCiSelector = () => wrapper.findComponent(SkipCiSelector);
  // The first GlToggle in the tree belongs to the advanced editor toggle, not skip CI.
  const findSkipCiSelectorToggle = () => findSkipCiSelector().findComponent(GlToggle);

  beforeEach(() => {
    jest.spyOn(urlUtils, 'getParameterByName').mockReturnValue('pipeline_execution_policy');
  });

  describe('skip ci configuration', () => {
    beforeEach(async () => {
      createWrapper();
      await waitForPromises();
    });

    it('allows skipping ci when the prevent-skip toggle is turned off', async () => {
      const verifyRuleMode = () => {
        expect(findSkipCiSelector().exists()).toBe(true);
      };

      expect(findSkipCiSelector().props('skipCiConfiguration')).toEqual({
        allowed: false,
      });

      await findSkipCiSelectorToggle().vm.$emit('change', false);

      await verify({
        manifest: mockPipelineExecutionSkipCiManifest,
        verifyRuleMode,
        wrapper,
      });
    });
  });
});
