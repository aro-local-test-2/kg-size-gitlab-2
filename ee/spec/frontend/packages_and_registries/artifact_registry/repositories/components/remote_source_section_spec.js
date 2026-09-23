import { GlButton } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { createAlert } from '~/alert';
import ConnectionIndicator from 'ee/packages_and_registries/artifact_registry/repositories/components/connection_indicator.vue';
import ConnectionTestResult from 'ee/packages_and_registries/artifact_registry/repositories/components/connection_test_result.vue';
import RemoteSourceSection from 'ee/packages_and_registries/artifact_registry/repositories/components/remote_source_section.vue';
import testRepositoryConnectionMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/test_repository_connection.mutation.graphql';
import testUpstreamConnectionMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/test_upstream_connection.mutation.graphql';
import {
  REPOSITORY_FORMAT_DOCKER,
  REPOSITORY_FORMAT_MAVEN,
  REPOSITORY_FORMAT_NPM,
  REPOSITORY_FORMAT_OCI,
} from 'ee/packages_and_registries/artifact_registry/constants';

jest.mock('~/alert');

Vue.use(VueApollo);

const PAIR_FORMATS = [REPOSITORY_FORMAT_MAVEN, REPOSITORY_FORMAT_DOCKER, REPOSITORY_FORMAT_OCI];

const METADATA_WINDOW_FORMATS = [REPOSITORY_FORMAT_MAVEN, REPOSITORY_FORMAT_NPM];

const CONTAINER_FORMATS = [REPOSITORY_FORMAT_DOCKER, REPOSITORY_FORMAT_OCI];

const REPOSITORY_NAME = 'my-remote-repository';

const LAST_CHECKED_AT = '2026-07-12T00:00:00Z';

const PROBED_AT = '2026-07-14T00:00:00Z';

const SETTINGS = {
  url: 'https://repo.example.com/maven2',
  cacheValidityHours: 48,
  metadataCacheValidityHours: 12,
  lastHealthStatus: 'HEALTHY',
  lastHealthCheckedAt: LAST_CHECKED_AT,
};

const verdictProps = (healthStatus, lastHealthCheckedAt) => ({
  healthStatus,
  lastHealthCheckedAt,
  inline: true,
});

const STORED_VERDICT = verdictProps('HEALTHY', LAST_CHECKED_AT);

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

const mockUpstreamVerdict = (overrides = {}) => ({
  data: {
    testConnection: {
      __typename: 'ArtifactRegistryUpstreamTestConnectionPayload',
      passed: true,
      httpStatus: 200,
      errors: [],
      ...overrides,
    },
  },
});

const CACHE_VALIDITY_PLACEHOLDER = '24';

const URL_REQUIRED = 'URL is required.';

const CACHE_REQUIRED = 'Artifact caching period is required.';

const METADATA_CACHE_REQUIRED = 'Metadata caching period is required.';

const WINDOWS = [
  ['artifact', 'remote-source-cache-validity', CACHE_REQUIRED],
  ['metadata', 'remote-source-metadata-cache-validity', METADATA_CACHE_REQUIRED],
];

const CHANGED_URL = 'https://mirror.example.com/maven2';

const INCOMPLETE_PAIR =
  'Enter both a username and a token or password, or leave both empty to keep the stored credentials.';

describe('ArtifactRegistryRemoteSourceSection', () => {
  let wrapper;
  let mockApollo;
  let testConnectionHandler;
  let upstreamHandler;

  const findHeading = () => wrapper.find('h2');
  const findUrlInput = () => wrapper.findByTestId('remote-source-url');
  const findUsernameInput = () => wrapper.findByTestId('remote-source-username');
  const findPasswordInput = () => wrapper.findByTestId('remote-source-password');
  const findTokenInput = () => wrapper.findByTestId('remote-source-token');
  const findCacheInput = () => wrapper.findByTestId('remote-source-cache-validity');
  const findMetadataCacheInput = () =>
    wrapper.findByTestId('remote-source-metadata-cache-validity');
  const findNumberInputs = () => wrapper.findAll('input[type="number"]');
  const findTestButton = () => wrapper.findComponent(GlButton);
  const findIndicator = () => wrapper.findComponent(ConnectionIndicator);
  const findTestResult = () => wrapper.findComponent(ConnectionTestResult);
  const findResultRegion = () => wrapper.findByTestId('connection-test-result-region');
  const findProbeButton = () => wrapper.findByRole('button', { name: 'Test upstream connection' });
  const findButtons = () => wrapper.findAllComponents(GlButton);

  const labelOf = (input) => wrapper.find(`label[for="${input.attributes('id')}"]`);

  const accessibleNameOf = (input) => labelOf(input).text().replace(/\s+/g, ' ');

  const lastEmittedSettings = () => wrapper.emitted('input')?.at(-1)[0];

  const flaggedFields = () =>
    ['remote-source-url', 'remote-source-username', 'remote-source-password'].filter((testId) =>
      wrapper.findByTestId(testId).classes('is-invalid'),
    );

  const shownFeedback = () =>
    wrapper.findAll('.invalid-feedback.\\!gl-block').wrappers.map((message) => message.text());

  const createComponent = ({
    format = REPOSITORY_FORMAT_MAVEN,
    settings = SETTINGS,
    name = REPOSITORY_NAME,
    createMode = false,
  } = {}) => {
    mockApollo = createMockApollo([
      [testRepositoryConnectionMutation, testConnectionHandler],
      [testUpstreamConnectionMutation, upstreamHandler],
    ]);

    wrapper = mountExtended(RemoteSourceSection, {
      apolloProvider: mockApollo,
      propsData: { format, name, settings, createMode },
      attachTo: document.body,
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

  const clearResult = async () => {
    testConnectionHandler.mockReturnValue(new Promise(() => {}));
    await startTestConnection();
  };

  beforeEach(() => {
    testConnectionHandler = jest.fn().mockResolvedValue(mockVerdict());
    upstreamHandler = jest.fn().mockResolvedValue(mockUpstreamVerdict());
  });

  describe('the section frame', () => {
    beforeEach(() => {
      createComponent();
    });

    it('names itself as the source of the repository’s artifacts', () => {
      expect(findHeading().text()).toBe('Source');
    });

    it('groups the credentials under a heading saying they are optional', () => {
      expect(wrapper.text()).toContain('Authentication (optional)');
    });

    it('says the credentials are stored encrypted', () => {
      expect(wrapper.text()).toContain('stored encrypted');
    });
  });

  describe('the upstream URL', () => {
    beforeEach(() => {
      createComponent();
    });

    it('prefills the stored URL under a label of its own', () => {
      expect(findUrlInput().element.value).toBe(SETTINGS.url);
      expect(accessibleNameOf(findUrlInput())).toBe('URL');
    });

    it('takes input', () => {
      expect(findUrlInput().element.readOnly).toBe(false);
      expect(findUrlInput().element.disabled).toBe(false);
    });

    it('reports the URL that was typed, leaving the cache windows as they were', async () => {
      await findUrlInput().setValue('https://mirror.example.com/maven2');

      expect(lastEmittedSettings()).toEqual({
        url: 'https://mirror.example.com/maven2',
        cacheValidityHours: SETTINGS.cacheValidityHours,
        metadataCacheValidityHours: SETTINGS.metadataCacheValidityHours,
      });
    });
  });

  describe('the cache periods', () => {
    it.each(METADATA_WINDOW_FORMATS)('renders both periods on %s', (format) => {
      createComponent({ format });

      expect(findCacheInput().exists()).toBe(true);
      expect(findMetadataCacheInput().exists()).toBe(true);
      expect(findNumberInputs()).toHaveLength(2);
    });

    it.each(CONTAINER_FORMATS)(
      'renders the artifact period alone on %s, which has no metadata window',
      (format) => {
        createComponent({ format });

        expect(findCacheInput().exists()).toBe(true);
        expect(findMetadataCacheInput().exists()).toBe(false);
        expect(findNumberInputs()).toHaveLength(1);
      },
    );

    it('prefills each window with the stored value under a label of its own', () => {
      createComponent();

      expect(findCacheInput().element.value).toBe(String(SETTINGS.cacheValidityHours));
      expect(findMetadataCacheInput().element.value).toBe(
        String(SETTINGS.metadataCacheValidityHours),
      );
      expect(accessibleNameOf(findCacheInput())).toBe('Artifact caching period');
      expect(accessibleNameOf(findMetadataCacheInput())).toBe('Metadata caching period');
    });

    it('leaves each window empty when the read carries neither, hinting 24 rather than seeding it', () => {
      createComponent({ settings: {} });

      expect(findCacheInput().element.value).toBe('');
      expect(findCacheInput().attributes('placeholder')).toBe(CACHE_VALIDITY_PLACEHOLDER);
      expect(findMetadataCacheInput().element.value).toBe('');
      expect(findMetadataCacheInput().attributes('placeholder')).toBe(CACHE_VALIDITY_PLACEHOLDER);
    });

    it('refuses the submission when the read carried no window to prefill', async () => {
      createComponent({ settings: { url: SETTINGS.url } });

      const passed = wrapper.vm.validate();
      await nextTick();

      expect(passed).toBe(false);
      expect(shownFeedback()).toEqual([CACHE_REQUIRED, METADATA_CACHE_REQUIRED]);
    });

    it('carries the artifact window’s bounds', () => {
      createComponent();

      expect(findCacheInput().attributes()).toMatchObject({
        type: 'number',
        min: '0',
        max: '32767',
      });
    });

    it('carries the metadata window’s bounds, whose floor is one hour', () => {
      createComponent();

      expect(findMetadataCacheInput().attributes()).toMatchObject({
        type: 'number',
        min: '1',
        max: '32767',
      });
    });

    it.each([
      ['artifact', findCacheInput, 'artifact-registry-remote-source-cache-validity-hint'],
      [
        'metadata',
        findMetadataCacheInput,
        'artifact-registry-remote-source-metadata-cache-validity-hint',
      ],
    ])('points the %s window at a hint naming its unit', (_window, findInput, hintId) => {
      createComponent();

      expect(findInput().attributes('aria-describedby')).toBe(hintId);
      expect(wrapper.find(`#${hintId}`).text()).toBe('Time in hours');
    });

    it('reports the windows as numbers, which is what Artifact Registry stores', async () => {
      createComponent();

      await findCacheInput().setValue('72');
      await findMetadataCacheInput().setValue('6');

      expect(lastEmittedSettings()).toEqual({
        url: SETTINGS.url,
        cacheValidityHours: 72,
        metadataCacheValidityHours: 6,
      });
    });

    describe.each(WINDOWS)('the %s window on an edit', (_window, testId, message) => {
      const findInput = () => wrapper.findByTestId(testId);

      it('refuses the submission once it is emptied', async () => {
        createComponent();

        await findInput().setValue('');

        expect(wrapper.vm.validate()).toBe(false);
      });

      it('flags the field it emptied and says so', async () => {
        createComponent();

        await findInput().setValue('');
        await findInput().trigger('blur');
        await nextTick();

        expect(findInput().classes()).toContain('is-invalid');
        expect(shownFeedback()).toEqual([message]);
      });

      it('passes with a value present', () => {
        createComponent();

        expect(wrapper.vm.validate()).toBe(true);
        expect(shownFeedback()).toEqual([]);
      });
    });

    it.each(CONTAINER_FORMATS)(
      'leaves the metadata window unvalidated on %s, where it does not render',
      async (format) => {
        createComponent({ format });

        await findCacheInput().setValue('72');

        expect(findMetadataCacheInput().exists()).toBe(false);
        expect(wrapper.vm.validate()).toBe(true);
      },
    );

    it.each(CONTAINER_FORMATS)(
      'reports no metadata window on %s, which would earn a rejection',
      async (format) => {
        createComponent({ format });

        await findCacheInput().setValue('72');

        expect(lastEmittedSettings()).toEqual({
          url: SETTINGS.url,
          cacheValidityHours: 72,
        });
      },
    );
  });

  describe('the credential controls', () => {
    it.each(PAIR_FORMATS)('offers a username and a password on %s', (format) => {
      createComponent({ format });

      expect(accessibleNameOf(findUsernameInput())).toBe('Username');
      expect(accessibleNameOf(findPasswordInput())).toBe('Token or password');
      expect(findTokenInput().exists()).toBe(false);
    });

    it.each(PAIR_FORMATS)('masks the password on %s', (format) => {
      createComponent({ format });

      expect(findPasswordInput().attributes('type')).toBe('password');
      expect(findUsernameInput().attributes('type')).not.toBe('password');
    });

    it.each(PAIR_FORMATS)('prefills neither credential field on %s', (format) => {
      createComponent({ format });

      expect(findUsernameInput().element.value).toBe('');
      expect(findPasswordInput().element.value).toBe('');
    });

    it.each(PAIR_FORMATS)('reports the pair that was typed on %s', async (format) => {
      createComponent({ format });

      await findUsernameInput().setValue('robot');
      await findPasswordInput().setValue('s3cret');

      expect(lastEmittedSettings()).toMatchObject({
        credentials: { username: 'robot', password: 's3cret' },
      });
    });

    it.each(PAIR_FORMATS)('offers no action to clear the stored pair on %s', (format) => {
      createComponent({ format });

      expect(findProbeButton().exists()).toBe(true);
      expect(findButtons()).toHaveLength(1);
    });

    it('reports no credentials when neither control was typed into', async () => {
      createComponent();

      await findUrlInput().setValue('https://mirror.example.com/maven2');

      expect(lastEmittedSettings()).not.toHaveProperty('credentials');
    });
  });

  describe('the npm credential, which Artifact Registry takes as a bare token', () => {
    beforeEach(() => {
      createComponent({ format: REPOSITORY_FORMAT_NPM });
    });

    it('offers one token control and neither half of a pair', () => {
      expect(accessibleNameOf(findTokenInput())).toBe('Access token');
      expect(findUsernameInput().exists()).toBe(false);
      expect(findPasswordInput().exists()).toBe(false);
    });

    it('masks the token, which is a secret in the same way a password is', () => {
      expect(findTokenInput().attributes('type')).toBe('password');
    });

    it('prefills no token', () => {
      expect(findTokenInput().element.value).toBe('');
    });

    it('reports the token that was typed, under the name the schema will take', async () => {
      await findTokenInput().setValue('npm-token');

      expect(lastEmittedSettings()).toEqual({
        url: SETTINGS.url,
        cacheValidityHours: SETTINGS.cacheValidityHours,
        metadataCacheValidityHours: SETTINGS.metadataCacheValidityHours,
        credentials: { authToken: 'npm-token' },
      });
    });

    it('reports no credentials when the token was not typed into', () => {
      expect(lastEmittedSettings()).not.toHaveProperty('credentials');
    });

    it.each([
      ['empty', ''],
      ['filled', 'npm-token'],
    ])('passes validation with the token %s', async (_case, token) => {
      await findTokenInput().setValue(token);

      expect(wrapper.vm.validate()).toBe(true);
    });
  });

  describe('a format swapped part-way through the form', () => {
    const halfPairOnMaven = async () => {
      createComponent({ format: REPOSITORY_FORMAT_MAVEN });

      await findUsernameInput().setValue('robot');
      wrapper.vm.validate();
      await nextTick();
    };

    it('stops validating the pair the swap unmounted', async () => {
      await halfPairOnMaven();

      expect(flaggedFields()).toEqual(['remote-source-password']);

      await wrapper.setProps({ format: REPOSITORY_FORMAT_NPM });

      const passed = wrapper.vm.validate();
      await nextTick();

      expect(findUsernameInput().exists()).toBe(false);
      expect(passed).toBe(true);
      expect(shownFeedback()).toEqual([]);
    });

    it('reports no credential from the format it left', async () => {
      await halfPairOnMaven();
      await findPasswordInput().setValue('s3cret');

      await wrapper.setProps({ format: REPOSITORY_FORMAT_NPM });

      expect(lastEmittedSettings()).not.toHaveProperty('credentials');
    });

    it('clears the pair it left, so a swap back carries nothing over', async () => {
      await halfPairOnMaven();
      await findPasswordInput().setValue('s3cret');

      await wrapper.setProps({ format: REPOSITORY_FORMAT_NPM });
      await wrapper.setProps({ format: REPOSITORY_FORMAT_MAVEN });

      expect(findUsernameInput().element.value).toBe('');
      expect(findPasswordInput().element.value).toBe('');
      expect(lastEmittedSettings()).not.toHaveProperty('credentials');
    });

    it('clears the token it left, so a swap back carries nothing over', async () => {
      createComponent({ format: REPOSITORY_FORMAT_NPM });

      await findTokenInput().setValue('npm-token');
      await wrapper.setProps({ format: REPOSITORY_FORMAT_MAVEN });
      await wrapper.setProps({ format: REPOSITORY_FORMAT_NPM });

      expect(findTokenInput().element.value).toBe('');
      expect(lastEmittedSettings()).not.toHaveProperty('credentials');
    });

    it('waits for focus to leave before flagging a pair half-filled after a swap back', async () => {
      await halfPairOnMaven();

      await wrapper.setProps({ format: REPOSITORY_FORMAT_NPM });
      await wrapper.setProps({ format: REPOSITORY_FORMAT_MAVEN });
      await findUsernameInput().setValue('robot');

      expect(flaggedFields()).toEqual([]);
    });
  });

  describe('the upstream URL, which Artifact Registry requires', () => {
    const withoutUrl = () => createComponent({ settings: { ...SETTINGS, url: '' } });

    it('passes with a URL present', () => {
      createComponent();

      expect(wrapper.vm.validate()).toBe(true);
      expect(flaggedFields()).toEqual([]);
    });

    it('flags nothing while the field is being emptied', async () => {
      createComponent();

      await findUrlInput().setValue('');

      expect(flaggedFields()).toEqual([]);
      expect(shownFeedback()).toEqual([]);
    });

    it.each([
      ['empty', ''],
      ['whitespace', '   '],
    ])('fails an %s URL, flagging the URL field alone', async (_case, url) => {
      withoutUrl();

      await findUrlInput().setValue(url);

      expect(wrapper.vm.validate()).toBe(false);
      await nextTick();

      expect(flaggedFields()).toEqual(['remote-source-url']);
      expect(shownFeedback()).toEqual([URL_REQUIRED]);
    });

    it('flags the URL and the half-filled pair each on its own field', async () => {
      withoutUrl();

      await findUsernameInput().setValue('robot');

      expect(wrapper.vm.validate()).toBe(false);
      await nextTick();

      expect(flaggedFields()).toEqual(['remote-source-url', 'remote-source-password']);
      expect(shownFeedback()).toEqual([URL_REQUIRED, INCOMPLETE_PAIR]);
    });

    it('clears the URL error once it is filled, leaving the pair still flagged', async () => {
      withoutUrl();

      await findUsernameInput().setValue('robot');
      wrapper.vm.validate();
      await nextTick();

      await findUrlInput().setValue('https://mirror.example.com/maven2');

      expect(flaggedFields()).toEqual(['remote-source-password']);
      expect(shownFeedback()).toEqual([INCOMPLETE_PAIR]);
    });
  });

  describe('the credential pair, which Artifact Registry requires whole', () => {
    it('passes with both empty, which asks for the stored pair to be left alone', () => {
      createComponent();

      expect(wrapper.vm.validate()).toBe(true);
      expect(lastEmittedSettings()).not.toHaveProperty('credentials');
    });

    it('flags nothing while the first field is being filled', async () => {
      createComponent();

      await findUsernameInput().setValue('robot');

      expect(flaggedFields()).toEqual([]);
      expect(shownFeedback()).toEqual([]);
    });

    it.each([
      ['a username without a password', 'remote-source-username', 'remote-source-password'],
      ['a password without a username', 'remote-source-password', 'remote-source-username'],
    ])('fails %s, flagging the empty field alone', async (_case, filled, flagged) => {
      createComponent();

      await wrapper.findByTestId(filled).setValue('half-a-pair');

      expect(wrapper.vm.validate()).toBe(false);
      await nextTick();

      expect(flaggedFields()).toEqual([flagged]);
      expect(shownFeedback()).toEqual([INCOMPLETE_PAIR]);
      expect(lastEmittedSettings()).not.toHaveProperty('credentials');
    });

    it('clears the error and reports the pair once it is completed', async () => {
      createComponent();

      await findUsernameInput().setValue('robot');
      wrapper.vm.validate();
      await nextTick();

      await findPasswordInput().setValue('s3cret');

      expect(flaggedFields()).toEqual([]);
      expect(shownFeedback()).toEqual([]);
      expect(lastEmittedSettings()).toMatchObject({
        credentials: { username: 'robot', password: 's3cret' },
      });
    });
  });

  describe('reporting on blur, the way the common fields report', () => {
    const blur = async (input) => {
      await input.trigger('blur');
      await nextTick();
    };

    it('flags an emptied URL as soon as focus leaves it', async () => {
      createComponent();

      await findUrlInput().setValue('');
      await blur(findUrlInput());

      expect(flaggedFields()).toEqual(['remote-source-url']);
      expect(shownFeedback()).toEqual([URL_REQUIRED]);
    });

    it('flags nothing while the URL is being emptied, before focus leaves', async () => {
      createComponent();

      await findUrlInput().setValue('');

      expect(flaggedFields()).toEqual([]);
      expect(shownFeedback()).toEqual([]);
    });

    it.each([
      ['username', 'remote-source-username'],
      ['password', 'remote-source-password'],
    ])(
      'flags nothing when an empty %s is blurred beside an empty sibling',
      async (_half, testId) => {
        createComponent();

        await blur(wrapper.findByTestId(testId));

        expect(flaggedFields()).toEqual([]);
        expect(shownFeedback()).toEqual([]);
      },
    );

    it.each([
      ['username', 'remote-source-password', 'remote-source-username'],
      ['password', 'remote-source-username', 'remote-source-password'],
    ])('flags an empty %s once its sibling is filled', async (_half, filled, blurred) => {
      createComponent();

      await wrapper.findByTestId(filled).setValue('half-a-pair');
      await blur(wrapper.findByTestId(blurred));

      expect(flaggedFields()).toEqual([blurred]);
      expect(shownFeedback()).toEqual([INCOMPLETE_PAIR]);
    });
  });

  describe('the connection test', () => {
    beforeEach(() => {
      createComponent();
    });

    it('names the action for what it probes', () => {
      expect(findTestButton().text()).toBe('Test upstream connection');
    });

    it('draws the action beside the fields rather than as the page primary', () => {
      expect(findTestButton().props()).toMatchObject({
        category: 'secondary',
        variant: 'default',
      });
    });

    it('holds the result row open before any probe has run', () => {
      expect(findResultRegion().attributes('aria-live')).toBe('polite');
      expect(findTestResult().exists()).toBe(false);
    });

    it('opens on the stored verdict, which a probe from anywhere may have recorded', () => {
      expect(findIndicator().props()).toEqual(STORED_VERDICT);
    });

    it('probes the repository the form is editing', async () => {
      await testConnection();

      expect(testConnectionHandler).toHaveBeenCalledTimes(1);
      expect(testConnectionHandler).toHaveBeenCalledWith({ input: { name: REPOSITORY_NAME } });
    });
  });

  it('opens on never-verified when the read carries no stored verdict', () => {
    createComponent({ settings: {} });

    expect(findIndicator().props()).toEqual(verdictProps('UNKNOWN', null));
  });

  describe('while the probe runs', () => {
    beforeEach(async () => {
      testConnectionHandler.mockReturnValue(new Promise(() => {}));
      createComponent();
      await startTestConnection();
    });

    it('says a probe is running rather than leaving the rest label in place', () => {
      expect(findTestButton().text()).toBe('Testing upstream connection');
      expect(findTestButton().props('loading')).toBe(true);
    });

    it('disables the action', () => {
      expect(findTestButton().attributes('aria-disabled')).toBe('true');
    });

    it('takes no second probe while the first is unanswered', async () => {
      await findTestButton().trigger('click');
      await waitForPromises();

      expect(testConnectionHandler).toHaveBeenCalledTimes(1);
    });

    it('keeps showing the stored verdict', () => {
      expect(findIndicator().props()).toEqual(STORED_VERDICT);
    });
  });

  describe('when the probe is answered', () => {
    it.each`
      outcome            | passed   | httpStatus | lastHealthStatus
      ${'reachable'}     | ${true}  | ${200}     | ${'HEALTHY'}
      ${'not reachable'} | ${false} | ${503}     | ${'UNHEALTHY'}
    `(
      'draws a $outcome probe in the result line in place of the indicator, keeping its verdict',
      async ({ passed, httpStatus, lastHealthStatus }) => {
        testConnectionHandler.mockResolvedValue(
          mockVerdict({ passed, httpStatus, lastHealthStatus }),
        );
        createComponent();

        await testConnection();

        expect(findTestResult().props()).toEqual({ passed, httpStatus });
        expect(findIndicator().exists()).toBe(false);

        await clearResult();

        expect(findTestResult().exists()).toBe(false);
        expect(findIndicator().props()).toEqual(verdictProps(lastHealthStatus, PROBED_AT));
      },
    );

    it('reports a failed probe whose verdict sat below the failure threshold', async () => {
      testConnectionHandler.mockResolvedValue(mockVerdict({ passed: false, httpStatus: 503 }));
      createComponent();

      await testConnection();

      expect(findTestResult().props()).toEqual({ passed: false, httpStatus: 503 });
      expect(wrapper.text()).toContain('Failed to connect.');
      expect(findIndicator().exists()).toBe(false);

      await clearResult();

      expect(findIndicator().props()).toEqual(verdictProps('HEALTHY', PROBED_AT));
    });

    it('draws the result line as its only surface, the indicator having stood down', async () => {
      createComponent();

      await testConnection();

      expect(wrapper.findAllComponents(ConnectionIndicator)).toHaveLength(0);
      expect(wrapper.findAllComponents(ConnectionTestResult)).toHaveLength(1);
    });

    it('returns the action to rest, so a further probe can be asked for', async () => {
      createComponent();

      await testConnection();

      expect(findTestButton().text()).toBe('Test upstream connection');
      expect(findTestButton().attributes('aria-disabled')).toBeUndefined();
    });

    describe('and the upstream was not reached', () => {
      beforeEach(async () => {
        testConnectionHandler.mockResolvedValue(
          mockVerdict({ passed: false, httpStatus: 503, lastHealthStatus: 'UNHEALTHY' }),
        );
        createComponent();

        await testConnection();
      });

      it('leaves the form submittable, an unreachable upstream being a result', () => {
        expect(wrapper.vm.validate()).toBe(true);
        expect(shownFeedback()).toEqual([]);
      });
    });
  });

  describe('when the probe could not be run', () => {
    beforeEach(async () => {
      testConnectionHandler.mockRejectedValue(new Error('the service is unavailable'));
      createComponent();

      await testConnection();
    });

    it('raises the service-unavailable alert', () => {
      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({
          message: 'The Artifact Registry service is unavailable.',
        }),
      );
    });

    it('writes no result line, nothing having been established', () => {
      expect(findTestResult().exists()).toBe(false);
    });

    it('leaves the stored verdict as it was', () => {
      expect(findIndicator().props()).toEqual(STORED_VERDICT);
    });

    it('returns the action to rest', () => {
      expect(findTestButton().text()).toBe('Test upstream connection');
      expect(findTestButton().attributes('aria-disabled')).toBeUndefined();
    });
  });

  describe('in create mode', () => {
    beforeEach(() => {
      createComponent({ createMode: true, settings: {} });
    });

    it('keeps every writable field', () => {
      expect(findUrlInput().exists()).toBe(true);
      expect(findUsernameInput().exists()).toBe(true);
      expect(findPasswordInput().exists()).toBe(true);
      expect(findCacheInput().exists()).toBe(true);
      expect(findMetadataCacheInput().exists()).toBe(true);
    });

    it('offers the probe and its result region but no stored-health indicator', () => {
      expect(findProbeButton().exists()).toBe(true);
      expect(findResultRegion().exists()).toBe(true);
      expect(findIndicator().exists()).toBe(false);
    });

    it('offers the probe as its only action, with no cache eviction', () => {
      expect(findButtons()).toHaveLength(1);
      expect(wrapper.text()).not.toMatch(/evict|purge|clear the cache/i);
    });

    describe('the create-form probe', () => {
      it('is disabled until a URL is present', async () => {
        expect(findTestButton().attributes('aria-disabled')).toBe('true');

        await findUrlInput().setValue(CHANGED_URL);

        expect(findTestButton().attributes('aria-disabled')).toBeUndefined();
      });

      it('stays disabled while the credential pair is half-filled, so it never probes anonymously by surprise', async () => {
        await findUrlInput().setValue(CHANGED_URL);

        await findUsernameInput().setValue('robot');

        expect(findTestButton().attributes('aria-disabled')).toBe('true');

        await findPasswordInput().setValue('s3cret');

        expect(findTestButton().attributes('aria-disabled')).toBeUndefined();
      });

      it('probes the supplied URL and credentials, not a repository name', async () => {
        await findUrlInput().setValue(CHANGED_URL);
        await findUsernameInput().setValue('robot');
        await findPasswordInput().setValue('s3cret');

        await testConnection();

        expect(upstreamHandler).toHaveBeenCalledTimes(1);
        expect(upstreamHandler).toHaveBeenCalledWith({
          input: {
            format: REPOSITORY_FORMAT_MAVEN,
            url: CHANGED_URL,
            credentials: { username: 'robot', password: 's3cret' },
          },
        });
        expect(testConnectionHandler).not.toHaveBeenCalled();
      });

      it('omits credentials from the probe when none were typed', async () => {
        await findUrlInput().setValue(CHANGED_URL);

        await testConnection();

        expect(upstreamHandler).toHaveBeenCalledWith({
          input: { format: REPOSITORY_FORMAT_MAVEN, url: CHANGED_URL },
        });
      });

      it('draws the transient result with no stored-health indicator', async () => {
        await findUrlInput().setValue(CHANGED_URL);

        await testConnection();

        expect(findTestResult().props()).toEqual({ passed: true, httpStatus: 200 });
        expect(findIndicator().exists()).toBe(false);
      });

      it('reports an unreachable upstream without blocking the submission', async () => {
        upstreamHandler.mockResolvedValue(mockUpstreamVerdict({ passed: false, httpStatus: null }));
        await findUrlInput().setValue(CHANGED_URL);

        await testConnection();

        expect(findTestResult().props()).toEqual({ passed: false, httpStatus: null });
        expect(wrapper.vm.validate()).toBe(true);
      });

      it('raises the service-unavailable alert when the probe could not run', async () => {
        upstreamHandler.mockRejectedValue(new Error('the service is unavailable'));
        await findUrlInput().setValue(CHANGED_URL);

        await testConnection();

        expect(createAlert).toHaveBeenCalledWith(
          expect.objectContaining({
            message: 'The Artifact Registry service is unavailable.',
          }),
        );
        expect(findTestResult().exists()).toBe(false);
      });

      it('drops a stale result once a probe input changes', async () => {
        await findUrlInput().setValue(CHANGED_URL);
        await testConnection();

        expect(findTestResult().exists()).toBe(true);

        await findUrlInput().setValue('https://other.example.com/maven2');

        expect(findTestResult().exists()).toBe(false);
      });

      describe('when the upstream takes a single token (npm)', () => {
        beforeEach(() => {
          createComponent({ createMode: true, settings: {}, format: REPOSITORY_FORMAT_NPM });
        });

        it('probes with the auth token and never blocks on a half-filled pair', async () => {
          await findUrlInput().setValue(CHANGED_URL);

          expect(findTestButton().attributes('aria-disabled')).toBeUndefined();

          await findTokenInput().setValue('npm-token');

          await testConnection();

          expect(upstreamHandler).toHaveBeenCalledWith({
            input: {
              format: REPOSITORY_FORMAT_NPM,
              url: CHANGED_URL,
              credentials: { authToken: 'npm-token' },
            },
          });
        });
      });
    });

    it('announces the upstream URL as required, which Artifact Registry requires', () => {
      const url = wrapper.findByRole('textbox', { name: 'URL' });

      expect(url.attributes('data-testid')).toBe('remote-source-url');
      expect(url.attributes('aria-required')).toBe('true');
    });

    it('offers 24 as a hint on each window rather than as a value', () => {
      expect(findCacheInput().element.value).toBe('');
      expect(findCacheInput().attributes('placeholder')).toBe(CACHE_VALIDITY_PLACEHOLDER);
      expect(findMetadataCacheInput().element.value).toBe('');
      expect(findMetadataCacheInput().attributes('placeholder')).toBe(CACHE_VALIDITY_PLACEHOLDER);
    });

    it('reports neither window until one is typed into', async () => {
      await findUrlInput().setValue(CHANGED_URL);

      expect(lastEmittedSettings()).toEqual({ url: CHANGED_URL });
    });

    it('takes an empty window rather than refusing the submission', async () => {
      await findUrlInput().setValue(CHANGED_URL);

      expect(wrapper.vm.validate()).toBe(true);
      expect(shownFeedback()).toEqual([]);
    });

    it('omits a window again once it is cleared, and still submits', async () => {
      await findUrlInput().setValue(CHANGED_URL);
      await findCacheInput().setValue('72');
      await findCacheInput().setValue('');

      expect(lastEmittedSettings()).toEqual({ url: CHANGED_URL });
      expect(wrapper.vm.validate()).toBe(true);
    });

    it('reports the window that was typed into and omits the other', async () => {
      await findUrlInput().setValue(CHANGED_URL);
      await findCacheInput().setValue('72');

      expect(lastEmittedSettings()).toEqual({ url: CHANGED_URL, cacheValidityHours: 72 });

      await findMetadataCacheInput().setValue('6');

      expect(lastEmittedSettings()).toEqual({
        url: CHANGED_URL,
        cacheValidityHours: 72,
        metadataCacheValidityHours: 6,
      });
    });

    it('reports a window typed as zero, which asks for never revalidating', async () => {
      await findUrlInput().setValue(CHANGED_URL);
      await findCacheInput().setValue('0');

      expect(lastEmittedSettings()).toEqual({ url: CHANGED_URL, cacheValidityHours: 0 });
    });
  });
});
