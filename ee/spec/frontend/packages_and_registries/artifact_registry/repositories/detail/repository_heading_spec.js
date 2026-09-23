import { GlBadge, GlIcon, GlTruncate } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import FormatLogo from 'ee/packages_and_registries/artifact_registry/repositories/components/format_logo.vue';
import RepositoryHeading from 'ee/packages_and_registries/artifact_registry/repositories/detail/repository_heading.vue';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';
import { mockRemoteSettings, mockRepository } from '../../mock_data';

describe('ArtifactRegistryRepositoryHeading', () => {
  let wrapper;

  const findName = () => wrapper.findByTestId('repository-name');
  const findHeading = () => wrapper.findByTestId('page-heading');
  const findFormatLogo = () => wrapper.findComponent(FormatLogo);
  const findFormatName = () => wrapper.findByTestId('repository-format-name');
  const findVisibilityButton = () => wrapper.findComponentByTestId('repository-visibility');
  const findVisibilityIcon = () => findVisibilityButton().findComponent(GlIcon);
  const findKindBadge = () => wrapper.findComponent(GlBadge);
  const findUpstreamUrlLine = () => wrapper.findByTestId('upstream-url');
  const findUpstreamUrlLabel = () => wrapper.findByTestId('upstream-url-label');
  const findUpstreamUrlValue = () => wrapper.findComponent(GlTruncate);
  const findCopyButton = () => wrapper.findComponent(ClipboardButton);

  const createComponent = (overrides = {}) => {
    wrapper = mountExtended(RepositoryHeading, {
      propsData: { repository: { ...mockRepository, ...overrides } },
      directives: {
        GlTooltip: createMockDirective('gl-tooltip'),
      },
    });
  };

  const createRemoteComponent = (overrides = {}) =>
    createComponent({ kind: 'REMOTE', settings: mockRemoteSettings, ...overrides });

  describe('the name', () => {
    beforeEach(() => {
      createComponent({ name: 'payment-core' });
    });

    it('renders the repository name', () => {
      expect(findName().text()).toBe('payment-core');
    });

    it('renders it as the page heading', () => {
      expect(findHeading().element.tagName).toBe('H1');
      expect(findHeading().element.contains(findName().element)).toBe(true);
    });
  });

  describe('the format icon', () => {
    describe.each([
      ['MAVEN', 'Maven'],
      ['NPM', 'npm'],
      ['DOCKER', 'Docker'],
      ['OCI', 'OCI'],
    ])('for a %s repository', (format, label) => {
      beforeEach(() => {
        createComponent({ format });
      });

      it('renders the logo of that format', () => {
        expect(findFormatLogo().props('format')).toBe(format);
      });

      it(`names it ${label} for assistive technology`, () => {
        expect(findFormatName().text()).toBe(label);
        expect(findFormatName().classes()).toContain('gl-sr-only');
      });
    });

    it('renders the logo at the heading size', () => {
      createComponent();

      expect(findFormatLogo().props('size')).toBe(48);
    });
  });

  describe('for a PRIVATE repository', () => {
    beforeEach(() => {
      createComponent({ visibility: 'PRIVATE' });
    });

    it('renders the lock visibility icon', () => {
      expect(findVisibilityIcon().props('name')).toBe('lock');
    });

    it('names it Private for assistive technology', () => {
      expect(findVisibilityButton().attributes('aria-label')).toBe('Private');
    });

    it('reaches keyboard users', () => {
      expect(findVisibilityButton().element.tagName).toBe('BUTTON');
    });

    it('labels it Private on hover and focus', () => {
      expect(getBinding(findVisibilityButton().element, 'gl-tooltip')).toBeDefined();
      expect(findVisibilityButton().attributes('title')).toBe('Private');
    });
  });

  it.each([
    ['HOSTED', 'Hosted'],
    ['REMOTE', 'Remote'],
    ['VIRTUAL', 'Virtual'],
  ])('renders the kind of a %s repository as the badge %s', (kind, label) => {
    createComponent({ kind });

    expect(findKindBadge().text()).toBe(label);
  });

  describe('the upstream URL', () => {
    it('renders the URL as text rather than as a link', () => {
      createRemoteComponent();

      expect(findUpstreamUrlValue().props('text')).toBe(mockRemoteSettings.url);
      expect(wrapper.find(`a[href="${mockRemoteSettings.url}"]`).exists()).toBe(false);
    });

    it('names the line for assistive technology', () => {
      createRemoteComponent();

      expect(findUpstreamUrlLabel().text()).toBe('Upstream URL');
      expect(findUpstreamUrlLabel().classes()).toContain('gl-sr-only');
    });

    it.each([
      ['REMOTE', true],
      ['HOSTED', false],
      ['VIRTUAL', false],
    ])('renders a URL line on a %s repository: %s', (kind, rendered) => {
      createComponent({ kind, settings: kind === 'REMOTE' ? mockRemoteSettings : null });

      expect(findUpstreamUrlLine().exists()).toBe(rendered);
      expect(findCopyButton().exists()).toBe(rendered);
    });

    it('renders no URL line when the settings object is absent, heading intact', () => {
      createRemoteComponent({ settings: null });

      expect(findUpstreamUrlLine().exists()).toBe(false);
      expect(findCopyButton().exists()).toBe(false);
      expect(findName().text()).toBe(mockRepository.name);
    });

    describe('the copy action', () => {
      beforeEach(() => {
        createRemoteComponent();
      });

      it('copies the upstream URL', () => {
        expect(findCopyButton().props('text')).toBe(mockRemoteSettings.url);
      });

      it('names what it copies', () => {
        expect(findCopyButton().attributes('aria-label')).toBe('Copy upstream URL');
      });
    });
  });
});
