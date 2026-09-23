import { GlAvatar, GlAvatarLink } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import ConnectionSection from 'ee/packages_and_registries/artifact_registry/repositories/detail/connection_section.vue';
import RepositorySidebar from 'ee/packages_and_registries/artifact_registry/repositories/detail/repository_sidebar.vue';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import {
  mockDeniedRepositoryPermissions,
  mockDetailRepository,
  mockRemoteSettings,
  mockRepository,
  mockRepositoryPermissions,
  mockUser,
} from '../../mock_data';

describe('ArtifactRegistryRepositorySidebar', () => {
  let wrapper;

  const findStat = (name) => wrapper.findByTestId(`repository-stat-${name}`);
  const findCreated = () => wrapper.findByTestId('repository-created');
  const findLastUpdated = () => wrapper.findByTestId('repository-last-updated');

  const findStats = () => wrapper.findByTestId('repository-stats');
  const findConnectionSection = () => wrapper.findComponent(ConnectionSection);
  const findCaching = () => wrapper.findByTestId('repository-caching');
  const findCachingLine = (window) => wrapper.findByTestId(`repository-caching-${window}`);

  const createComponent = ({
    format = 'MAVEN',
    overrides = {},
    hideStats = false,
    permissions = mockRepositoryPermissions(),
    upstreamRepositoriesCount = null,
  } = {}) => {
    wrapper = mountExtended(RepositorySidebar, {
      propsData: {
        repository: mockDetailRepository(format, overrides),
        hideStats,
        permissions,
        upstreamRepositoriesCount,
      },
      stubs: { ConnectionSection: true },
    });
  };

  const createRemoteComponent = (overrides = {}, options = {}) =>
    createComponent({
      overrides: { kind: 'REMOTE', settings: mockRemoteSettings, ...overrides },
      ...options,
    });

  describe('the counters', () => {
    beforeEach(() => {
      createComponent({
        overrides: { sizeBytes: '597688320', downloadsCount: '6910', artifactsCount: '5' },
      });
    });

    it('renders the size as a human-readable quantity, not a byte count', () => {
      expect(findStat('size').text()).toMatchInterpolatedText('570.00 MiB Size');
    });

    it('groups the download count, which reaches five and six figures', () => {
      expect(findStat('downloads').text()).toMatchInterpolatedText('6,910 Downloads');
    });

    it('renders the artifact count', () => {
      expect(findStat('artifacts').text()).toMatchInterpolatedText('5 Packages');
    });
  });

  describe.each([
    ['MAVEN', 'Packages'],
    ['NPM', 'Packages'],
    ['DOCKER', 'Images'],
    ['OCI', 'Images'],
  ])('for a %s repository', (format, expectedLabel) => {
    it(`names the artifact counter ${expectedLabel}`, () => {
      createComponent({ format, overrides: { artifactsCount: '5' } });

      expect(findStat('artifacts').text()).toContain(expectedLabel);
    });
  });

  describe('the artifact counter on a remote repository', () => {
    it.each([
      ['MAVEN', '35 Packages cached'],
      ['NPM', '35 Packages cached'],
      ['DOCKER', '35 Images cached'],
      ['OCI', '35 Images cached'],
    ])('names the %s counter for what a remote caches', (format, expected) => {
      createComponent({ format, overrides: { kind: 'REMOTE', artifactsCount: '35' } });

      expect(findStat('artifacts').text()).toMatchInterpolatedText(expected);
    });

    it.each([
      ['MAVEN', '1 Package cached'],
      ['DOCKER', '1 Image cached'],
    ])('names a single cached %s in the singular', (format, expected) => {
      createComponent({ format, overrides: { kind: 'REMOTE', artifactsCount: '1' } });

      expect(findStat('artifacts').text()).toMatchInterpolatedText(expected);
    });
  });

  describe('when a counter is one', () => {
    it.each([
      ['MAVEN', '1 Package'],
      ['DOCKER', '1 Image'],
    ])('names the %s artifact counter in the singular', (format, expected) => {
      createComponent({ format, overrides: { artifactsCount: '1' } });

      expect(findStat('artifacts').text()).toMatchInterpolatedText(expected);
    });

    it('names the download counter in the singular', () => {
      createComponent({ overrides: { downloadsCount: '1' } });

      expect(findStat('downloads').text()).toMatchInterpolatedText('1 Download');
    });
  });

  describe('when the counters are absent', () => {
    beforeEach(() => {
      createComponent({
        overrides: { sizeBytes: null, downloadsCount: null, artifactsCount: null },
      });
    });

    it('renders each one as zero, which English names in the plural', () => {
      expect(findStat('size').text()).toMatchInterpolatedText('0 B Size');
      expect(findStat('downloads').text()).toMatchInterpolatedText('0 Downloads');
      expect(findStat('artifacts').text()).toMatchInterpolatedText('0 Packages');
    });
  });

  describe('the virtual repository figure', () => {
    const findRepositoriesStat = () => findStat('repositories');

    const createVirtualComponent = ({
      format = 'MAVEN',
      upstreamRepositoriesCount = 3,
      overrides = {},
      hideStats = false,
    } = {}) =>
      createComponent({
        format,
        overrides: { kind: 'VIRTUAL', ...overrides },
        hideStats,
        upstreamRepositoriesCount,
      });

    it('renders the repository count, taken from the upstream list length', () => {
      createVirtualComponent({ upstreamRepositoriesCount: 3 });

      expect(findRepositoriesStat().text()).toMatchInterpolatedText('3 Repositories');
    });

    it('names a single upstream in the singular', () => {
      createVirtualComponent({ upstreamRepositoriesCount: 1 });

      expect(findRepositoriesStat().text()).toMatchInterpolatedText('1 Repository');
    });

    it('renders the count rather than the buffered artifact count when the two differ', () => {
      createVirtualComponent({ upstreamRepositoriesCount: 3, overrides: { artifactsCount: '99' } });

      expect(findRepositoriesStat().text()).toMatchInterpolatedText('3 Repositories');
    });

    it('renders the repository figure alone, dropping size, downloads, and artifacts', () => {
      createVirtualComponent({
        overrides: { sizeBytes: '2048', downloadsCount: '1234', artifactsCount: '99' },
      });

      expect(findRepositoriesStat().exists()).toBe(true);
      expect(findStat('size').exists()).toBe(false);
      expect(findStat('downloads').exists()).toBe(false);
      expect(findStat('artifacts').exists()).toBe(false);
    });

    it('renders no stats block when the upstream list could not be read', () => {
      createVirtualComponent({ upstreamRepositoriesCount: null });

      expect(findStats().exists()).toBe(false);
      expect(findRepositoriesStat().exists()).toBe(false);
    });

    it('renders no stats block on an empty list, which sends a zero count with the stats hidden', () => {
      createVirtualComponent({ upstreamRepositoriesCount: 0, hideStats: true });

      expect(findStats().exists()).toBe(false);
      expect(findRepositoriesStat().exists()).toBe(false);
    });

    it('renders no connection section or caching period', () => {
      createVirtualComponent({ overrides: { settings: mockRemoteSettings } });

      expect(findConnectionSection().exists()).toBe(false);
      expect(findCaching().exists()).toBe(false);
    });

    it('keeps the timestamps, which every kind carries', () => {
      createVirtualComponent();

      expect(findCreated().exists()).toBe(true);
    });
  });

  describe('the caching period', () => {
    beforeEach(() => {
      createRemoteComponent();
    });

    it('names the section with an h2, so the heading order does not skip a level', () => {
      expect(findCaching().find('h2').text()).toBe('Caching period');
    });

    it('renders both windows the settings carry, each named and in hours', () => {
      expect(findCachingLine('artifact').text()).toBe('Artifact: 48 hours');
      expect(findCachingLine('metadata').text()).toBe('Metadata: 12 hours');
    });

    it('names a one-hour window in the singular', () => {
      createRemoteComponent({
        settings: { ...mockRemoteSettings, cacheValidityHours: 1 },
      });

      expect(findCachingLine('artifact').text()).toBe('Artifact: 1 hour');
    });
  });

  describe('when a remote repository has no metadata window', () => {
    beforeEach(() => {
      createRemoteComponent({
        settings: { ...mockRemoteSettings, metadataCacheValidityHours: null },
      });
    });

    it('drops that line, having no window to name', () => {
      expect(findCachingLine('metadata').exists()).toBe(false);
    });

    it('keeps the artifact window, which the repository still has', () => {
      expect(findCachingLine('artifact').text()).toBe('Artifact: 48 hours');
    });
  });

  describe('when a window is zero', () => {
    it('names it, so a zero window is not read as an absent one', () => {
      createRemoteComponent({ settings: { ...mockRemoteSettings, metadataCacheValidityHours: 0 } });

      expect(findCachingLine('metadata').text()).toBe('Metadata: 0 hours');
    });
  });

  describe('when there is no caching period to render', () => {
    it('renders no section on a hosted repository, which caches nothing', () => {
      createComponent();

      expect(findCaching().exists()).toBe(false);
    });

    it('renders no section when a remote repository’s settings did not resolve', () => {
      createRemoteComponent({ settings: null });

      expect(findCaching().exists()).toBe(false);
    });
  });

  describe('created on', () => {
    beforeEach(() => {
      createComponent({ overrides: { createdAt: '2026-05-12T09:24:00Z' } });
    });

    it('names the section', () => {
      expect(findCreated().text()).toContain('Created on');
    });

    it('names it with an h2, so the heading order does not skip a level', () => {
      expect(findCreated().find('h2').text()).toBe('Created on');
    });

    it('renders the date, so the reader is not left working it out from an interval', () => {
      expect(findCreated().text()).toContain('May 12, 2026');
    });

    it('reads as one sentence, attributing the date to the user the join resolved', () => {
      expect(findCreated().text()).toMatchInterpolatedText(
        `Created on May 12, 2026 by ${mockUser.name}`,
      );
    });

    it('links the avatar and the name to that user', () => {
      const link = findCreated().findComponent(GlAvatarLink);

      expect(link.attributes('href')).toBe(mockUser.webPath);
      expect(link.findComponent(GlAvatar).props('src')).toBe(mockUser.avatarUrl);
    });

    it('marks the avatar decorative, since the link already names the user', () => {
      expect(findCreated().findComponent(GlAvatar).props('alt')).toBe('');
    });
  });

  describe('last updated', () => {
    beforeEach(() => {
      createComponent({ overrides: { lastUpdatedAt: '2026-06-01T00:00:00Z' } });
    });

    it('names the section', () => {
      expect(findLastUpdated().text()).toContain('Last updated');
    });

    it('renders the interval since the content last changed', () => {
      expect(findLastUpdated().findComponent(TimeAgoTooltip).props('time')).toBe(
        '2026-06-01T00:00:00Z',
      );
    });

    it('attributes it to the user the join resolved', () => {
      expect(findLastUpdated().findComponent(GlAvatarLink).text()).toContain(mockUser.name);
    });
  });

  describe('when the repository has never been updated', () => {
    beforeEach(() => {
      createComponent({ overrides: { lastUpdatedAt: null } });
    });

    it('renders no last-updated section rather than an empty one', () => {
      expect(findLastUpdated().exists()).toBe(false);
    });

    it('keeps rendering created on, which happened regardless', () => {
      expect(findCreated().exists()).toBe(true);
    });
  });

  describe('when neither user resolves', () => {
    beforeEach(() => {
      createComponent({ overrides: { createdBy: null, updatedBy: null } });
    });

    it('renders the created-on date without attribution', () => {
      expect(findCreated().text()).toMatchInterpolatedText('Created on May 12, 2026');
    });

    it('keeps rendering the last-updated interval', () => {
      expect(findLastUpdated().findComponent(TimeAgoTooltip).exists()).toBe(true);
      expect(findLastUpdated().text()).not.toContain('by');
    });

    it('renders no avatar, which would otherwise stand for nobody', () => {
      expect(wrapper.findComponent(GlAvatar).exists()).toBe(false);
      expect(wrapper.findComponent(GlAvatarLink).exists()).toBe(false);
    });
  });

  describe('when the stats are hidden', () => {
    beforeEach(() => {
      createComponent({ hideStats: true });
    });

    it('drops the counters', () => {
      expect(findStats().exists()).toBe(false);
      expect(findStat('size').exists()).toBe(false);
      expect(findStat('downloads').exists()).toBe(false);
      expect(findStat('artifacts').exists()).toBe(false);
    });

    it('keeps the timestamps, which are true of an empty repository too', () => {
      expect(findCreated().exists()).toBe(true);
      expect(findLastUpdated().exists()).toBe(true);
    });
  });

  describe('when a remote repository hides its stats', () => {
    beforeEach(() => {
      createComponent({
        overrides: { kind: 'REMOTE', settings: mockRemoteSettings, artifactsCount: '35' },
        hideStats: true,
      });
    });

    it('drops the counters regardless of the count the row carries', () => {
      expect(findStats().exists()).toBe(false);
    });

    it('keeps the connection section and the caching period', () => {
      expect(findConnectionSection().exists()).toBe(true);
      expect(findCaching().exists()).toBe(true);
    });
  });

  it('renders the counters unless told to hide them', () => {
    createComponent();

    expect(findStats().exists()).toBe(true);
  });

  describe('the connection section', () => {
    it('renders it first, which is where the design puts it', () => {
      createRemoteComponent();

      expect(wrapper.element.firstElementChild).toBe(findConnectionSection().element);
    });

    it('hands it the repository it addresses and the fields it renders', () => {
      createRemoteComponent();

      expect(findConnectionSection().props()).toEqual({
        name: mockRepository.name,
        settings: mockRemoteSettings,
        permissions: mockRepositoryPermissions(),
      });
    });

    it('hands it the verdicts as they came, so a denial reaches the control it gates', () => {
      const permissions = mockDeniedRepositoryPermissions();

      createRemoteComponent({}, { permissions });

      expect(findConnectionSection().props('permissions')).toStrictEqual(permissions);
    });

    it.each`
      kind         | rendered
      ${'REMOTE'}  | ${true}
      ${'HOSTED'}  | ${false}
      ${'VIRTUAL'} | ${false}
    `('renders the section on a $kind repository: $rendered', ({ kind, rendered }) => {
      createComponent({ overrides: { kind, settings: mockRemoteSettings } });

      expect(findConnectionSection().exists()).toBe(rendered);
    });

    it('renders it on a remote repository carrying no settings', () => {
      createRemoteComponent({ settings: null });

      expect(findConnectionSection().props('settings')).toBeNull();
    });
  });
});
