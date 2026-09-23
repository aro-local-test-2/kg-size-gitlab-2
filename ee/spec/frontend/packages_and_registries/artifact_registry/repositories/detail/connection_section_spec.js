import { GlBadge, GlButton } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { useFakeDate } from 'helpers/fake_date';
import { createAlert } from '~/alert';
import ConnectionIndicator from 'ee/packages_and_registries/artifact_registry/repositories/components/connection_indicator.vue';
import ConnectionTestResult from 'ee/packages_and_registries/artifact_registry/repositories/components/connection_test_result.vue';
import ConnectionSection from 'ee/packages_and_registries/artifact_registry/repositories/detail/connection_section.vue';
import testRepositoryConnectionMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/test_repository_connection.mutation.graphql';
import {
  REMOTE_LAST_HEALTH_CHECKED_AT,
  mockRemoteSettings,
  mockRepositoryPermissions,
} from '../../mock_data';

jest.mock('~/alert');

Vue.use(VueApollo);

const REPOSITORY_NAME = 'my-remote-repository';

// Behind the frozen clock below and apart from the stored time, so an indicator left holding
// the value a probe replaced cannot look right.
const PROBED_AT = '2026-07-14T00:00:00Z';

const verdictProps = (healthStatus, lastHealthCheckedAt) => ({
  healthStatus,
  lastHealthCheckedAt,
  inline: false,
});

const STORED_VERDICT = verdictProps('HEALTHY', REMOTE_LAST_HEALTH_CHECKED_AT);

const mockVerdict = (overrides = {}) => ({
  data: {
    testConnection: {
      __typename: 'ArtifactRegistryRepositoryTestConnectionPayload',
      passed: true,
      httpStatus: 200,
      lastHealthStatus: 'HEALTHY',
      lastHealthCheckedAt: PROBED_AT,
      errors: [],
      ...overrides,
    },
  },
});

// The order the design draws.
const SECTION_ELEMENTS = ['connection-test', 'connection-indicator', 'connection-last-verified'];

describe('ArtifactRegistryConnectionSection', () => {
  let wrapper;
  let mockApollo;
  let testConnectionHandler;

  useFakeDate(2026, 6, 15);

  const findHeading = () => wrapper.find('h2');
  const findIndicator = () => wrapper.findComponent(ConnectionIndicator);
  const findBadge = () => wrapper.findComponent(GlBadge);
  const findTestButton = () => wrapper.findComponent(GlButton);
  const findEmptyState = () => wrapper.findByTestId('connection-empty');

  const elementOrder = () =>
    wrapper
      .findAll('[data-testid]')
      .wrappers.map((element) => element.attributes('data-testid'))
      .filter((testId) => SECTION_ELEMENTS.includes(testId));

  const createComponent = ({
    settings = mockRemoteSettings,
    name = REPOSITORY_NAME,
    ...props
  } = {}) => {
    mockApollo = createMockApollo([[testRepositoryConnectionMutation, testConnectionHandler]]);

    wrapper = mountExtended(ConnectionSection, {
      apolloProvider: mockApollo,
      propsData: { name, settings, permissions: mockRepositoryPermissions(), ...props },
    });
  };

  const testConnection = async () => {
    await findTestButton().trigger('click');
    await waitForPromises();
  };

  const startTestConnection = async () => {
    await findTestButton().trigger('click');
    await nextTick();
  };

  beforeEach(() => {
    testConnectionHandler = jest.fn().mockResolvedValue(mockVerdict());
  });

  describe('the section', () => {
    beforeEach(() => {
      createComponent();
    });

    it('names itself', () => {
      expect(findHeading().text()).toBe('Connection');
    });

    it('draws the control, then the verdict and the time it was taken', () => {
      expect(elementOrder()).toEqual(SECTION_ELEMENTS);
    });

    it('puts the control at the end of the heading row', () => {
      const row = findHeading().element.parentElement;

      expect(row).toBe(findTestButton().element.parentElement);
      expect(row.lastElementChild).toBe(findTestButton().element);
    });

    it('names the control for what it does', () => {
      expect(findTestButton().text()).toBe('Test');
    });

    // The sidebar is a column of read-only facts, so the one control in it is drawn as the
    // quietest thing that is still a button.
    it('draws the control quietly, the sidebar being a column of facts', () => {
      expect(findTestButton().props()).toMatchObject({ category: 'tertiary', size: 'small' });
    });

    // A verdict renders here whatever recorded it, so the page opens on the stored fields
    // rather than probing to fill them.
    it('opens on the stored verdict, with no probe triggered from this page', () => {
      expect(testConnectionHandler).not.toHaveBeenCalled();
      expect(findIndicator().props()).toEqual(STORED_VERDICT);
    });

    // Probing is a write the repository CRUD slice owns; this page hosts the affordance on
    // the same terms as the header's Edit and Delete.
    it('issues the slice-owned probe against the repository the page is showing', async () => {
      await testConnection();

      expect(testConnectionHandler).toHaveBeenCalledTimes(1);
      expect(testConnectionHandler).toHaveBeenCalledWith({ input: { name: REPOSITORY_NAME } });
    });
  });

  // All three of Artifact Registry's health values reach this page, and a newly created
  // remote sits in the third until something probes it.
  describe.each`
    healthStatus   | lastHealthCheckedAt              | label
    ${'HEALTHY'}   | ${REMOTE_LAST_HEALTH_CHECKED_AT} | ${'Healthy'}
    ${'UNHEALTHY'} | ${REMOTE_LAST_HEALTH_CHECKED_AT} | ${'Unhealthy'}
    ${'UNKNOWN'}   | ${null}                          | ${'Unknown'}
  `('on a $healthStatus repository', ({ healthStatus, lastHealthCheckedAt, label }) => {
    beforeEach(() => {
      createComponent({
        settings: { ...mockRemoteSettings, lastHealthStatus: healthStatus, lastHealthCheckedAt },
      });
    });

    it('renders the section rather than waiting for a first probe', () => {
      expect(findBadge().text()).toBe(label);
    });

    it('hands the indicator the stored fields whole', () => {
      expect(findIndicator().props()).toEqual(verdictProps(healthStatus, lastHealthCheckedAt));
    });
  });

  describe('when a probe resolves', () => {
    beforeEach(() => {
      testConnectionHandler.mockResolvedValue(
        mockVerdict({ passed: false, httpStatus: 503, lastHealthStatus: 'UNHEALTHY' }),
      );
      createComponent();
    });

    // The returned fields are the stored fields, so the section re-renders from the payload.
    it('re-renders the verdict and its time in place', async () => {
      await testConnection();

      expect(findIndicator().props()).toEqual(verdictProps('UNHEALTHY', PROBED_AT));
      expect(findBadge().text()).toBe('Unhealthy');
    });

    it('renders the indicator as its only result surface', async () => {
      await testConnection();

      expect(wrapper.findComponent(ConnectionTestResult).exists()).toBe(false);
      expect(wrapper.findAllComponents(ConnectionIndicator)).toHaveLength(1);
      expect(wrapper.findAllComponents(GlBadge)).toHaveLength(1);
    });

    it('holds the stored verdict until the probe answers, then takes the payload’s', async () => {
      let answer;
      testConnectionHandler.mockReturnValue(
        new Promise((resolve) => {
          answer = resolve;
        }),
      );
      createComponent();

      await startTestConnection();

      expect(findTestButton().props('loading')).toBe(true);
      expect(findIndicator().props()).toEqual(STORED_VERDICT);

      answer(mockVerdict());
      await waitForPromises();

      expect(findTestButton().props('loading')).toBe(false);
      expect(findIndicator().props()).toEqual(verdictProps('HEALTHY', PROBED_AT));
    });
  });

  // One failure sits below Artifact Registry's consecutive-failure threshold, so a probe
  // that ran can leave the stored verdict exactly where it was.
  describe('when a probe resolves on the verdict already stored', () => {
    beforeEach(async () => {
      testConnectionHandler.mockResolvedValue(
        mockVerdict({
          passed: false,
          httpStatus: 503,
          lastHealthCheckedAt: REMOTE_LAST_HEALTH_CHECKED_AT,
        }),
      );
      createComponent();

      await testConnection();
    });

    it('leaves the indicator as it was', () => {
      expect(findIndicator().props()).toEqual(STORED_VERDICT);
    });

    it('renders no error inline, an unchanged verdict not being one', () => {
      expect(wrapper.text()).not.toMatch(/error|failed|unavailable/i);
    });
  });

  describe('while a probe is in flight', () => {
    beforeEach(async () => {
      testConnectionHandler.mockReturnValue(new Promise(() => {}));
      createComponent();

      await startTestConnection();
    });

    it('says a test is running rather than leaving the rest label in place', () => {
      expect(findTestButton().text()).toBe('Testing');
      expect(findTestButton().props('loading')).toBe(true);
    });

    it('takes no second request until the first resolves', async () => {
      await findTestButton().trigger('click');
      await waitForPromises();

      expect(testConnectionHandler).toHaveBeenCalledTimes(1);
    });

    // Blanking the indicator, or switching it to never-verified, would report a state
    // Artifact Registry never sent.
    it('keeps the indicator on the stored verdict', () => {
      expect(findIndicator().props()).toEqual(STORED_VERDICT);
      expect(findBadge().text()).toBe('Healthy');
    });
  });

  // Artifact Registry answering 500 means a probe ran and its verdict could not be recorded,
  // so there is no outcome to report and nothing to move the indicator to.
  describe('when the probe could not be run', () => {
    beforeEach(async () => {
      testConnectionHandler.mockRejectedValue(new Error('the service is unavailable'));
      createComponent();

      await testConnection();
    });

    it('raises the service-unavailable alert', () => {
      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({
          message: 'The Artifact Registry service is unavailable. Please try again.',
        }),
      );
    });

    it('leaves the indicator as it was', () => {
      expect(findIndicator().props()).toEqual(STORED_VERDICT);
    });
  });

  describe('the update verdict', () => {
    describe('when it allows', () => {
      beforeEach(() => {
        createComponent({ permissions: mockRepositoryPermissions() });
      });

      it('renders the test control', () => {
        expect(findTestButton().text()).toBe('Test');
      });
    });

    describe('when it denies', () => {
      beforeEach(() => {
        createComponent({ permissions: mockRepositoryPermissions({ updateRepository: false }) });
      });

      it('renders no test control', () => {
        expect(findTestButton().exists()).toBe(false);
      });

      it('keeps the heading and the stored verdict', () => {
        expect(findHeading().text()).toBe('Connection');
        expect(findIndicator().props()).toEqual(STORED_VERDICT);
      });
    });

    describe('before it has resolved', () => {
      beforeEach(() => {
        createComponent({ permissions: undefined });
      });

      it('renders no test control', () => {
        expect(findTestButton().exists()).toBe(false);
      });

      it('still renders the stored verdict', () => {
        expect(findIndicator().props()).toEqual(STORED_VERDICT);
      });
    });
  });

  describe('when the repository carries no settings', () => {
    beforeEach(() => {
      createComponent({ settings: null });
    });

    it('says there is nothing to show rather than rendering an empty indicator', () => {
      expect(findEmptyState().text()).toBe('No connection information available.');
      expect(findIndicator().exists()).toBe(false);
    });

    // The route the probe calls needs a repository that exists, which is what the page is
    // looking at, so the control does not depend on the stored fields.
    it('keeps offering the test, which needs the repository rather than its settings', () => {
      expect(findTestButton().text()).toBe('Test');
    });
  });
});
