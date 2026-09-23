import { GlToggle } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import App from 'ee/security_orchestration/components/policy_editor/app.vue';
import * as urlUtils from '~/lib/utils/url_utility';
import SkipCiSelector from 'ee/security_orchestration/components/policy_editor/skip_ci_selector.vue';
import { DEFAULT_ASSIGNED_POLICY_PROJECT } from 'ee/security_orchestration/constants';
import { createMockApolloProvider } from '../apollo_util';
import { DEFAULT_PROVIDE } from '../mocks/mocks';
import { mockPolicySchemaRequest, verify } from '../utils';
import { mockSkipCiScanExecutionManifest } from './mocks';

describe('Skip ci for scan execution policy', () => {
  let wrapper;
  let mockAxios;

  const createWrapper = ({ propsData = {}, provide = {}, glFeatures = {} } = {}) => {
    wrapper = mountExtended(App, {
      apolloProvider: createMockApolloProvider(),
      propsData: {
        assignedPolicyProject: DEFAULT_ASSIGNED_POLICY_PROJECT,
        ...propsData,
      },
      provide: {
        ...DEFAULT_PROVIDE,
        glFeatures,
        ...provide,
      },
    });
  };

  const findSkipCiSelector = () => wrapper.findComponent(SkipCiSelector);
  // The first GlToggle in the tree belongs to the advanced editor toggle, not skip CI.
  const findSkipCiSelectorToggle = () => findSkipCiSelector().findComponent(GlToggle);

  beforeEach(() => {
    mockAxios = mockPolicySchemaRequest();
    jest.spyOn(urlUtils, 'getParameterByName').mockReturnValue('scan_execution_policy');
  });

  afterEach(() => {
    mockAxios.restore();
  });

  describe('skip ci configuration', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('disallows skipping ci when the prevent-skip toggle is turned on', async () => {
      const verifyRuleMode = () => {
        expect(findSkipCiSelector().exists()).toBe(true);
      };

      expect(findSkipCiSelector().props('skipCiConfiguration')).toEqual({
        allowed: true,
      });

      await findSkipCiSelectorToggle().vm.$emit('change', true);

      await verify({
        manifest: mockSkipCiScanExecutionManifest,
        verifyRuleMode,
        wrapper,
      });
    });
  });
});
