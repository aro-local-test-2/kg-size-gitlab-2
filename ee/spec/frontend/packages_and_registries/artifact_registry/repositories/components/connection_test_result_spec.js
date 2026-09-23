import { GlIcon } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import ConnectionTestResult from 'ee/packages_and_registries/artifact_registry/repositories/components/connection_test_result.vue';

describe('ArtifactRegistryConnectionTestResult', () => {
  let wrapper;

  const findIcon = () => wrapper.findComponent(GlIcon);
  const findUpstreamStatus = () => wrapper.findByTestId('connection-upstream-status');

  const createComponent = ({ passed = true, httpStatus = null } = {}) => {
    wrapper = mountExtended(ConnectionTestResult, { propsData: { passed, httpStatus } });
  };

  describe('when the probe reached the upstream', () => {
    beforeEach(() => {
      createComponent();
    });

    it('says the probe got through', () => {
      expect(wrapper.text()).toContain('Connection successful.');
    });

    it('draws the reachable treatment', () => {
      expect(findIcon().props()).toMatchObject({ name: 'check-circle', variant: 'success' });
    });
  });

  describe('when the probe did not reach the upstream', () => {
    beforeEach(() => {
      createComponent({ passed: false });
    });

    it('says the probe failed and what to look at', () => {
      expect(wrapper.text()).toContain('Failed to connect. Check the URL and credentials.');
    });

    it('draws the unreachable treatment', () => {
      expect(findIcon().props()).toMatchObject({ name: 'error', variant: 'danger' });
    });
  });

  it('tells the two outcomes apart in both words and treatment', () => {
    createComponent({ passed: true });
    const reached = { text: wrapper.text(), ...findIcon().props() };

    createComponent({ passed: false });
    const failed = { text: wrapper.text(), ...findIcon().props() };

    expect(reached.text).not.toBe(failed.text);
    expect(reached.name).not.toBe(failed.name);
    expect(reached.variant).not.toBe(failed.variant);
  });

  describe('the upstream HTTP status', () => {
    it.each([
      ['a reachable probe', true, 200],
      ['an unreachable probe', false, 503],
    ])('renders the status %s was answered with', (_case, passed, httpStatus) => {
      createComponent({ passed, httpStatus });

      expect(findUpstreamStatus().text()).toMatchInterpolatedText(
        `Upstream responded with ${httpStatus}`,
      );
    });

    it('reports the outcome alone when the probe came back without one', () => {
      createComponent({ passed: false });

      expect(wrapper.text()).toContain('Failed to connect. Check the URL and credentials.');
      expect(findUpstreamStatus().exists()).toBe(false);
    });
  });
});
