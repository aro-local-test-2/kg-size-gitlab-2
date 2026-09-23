import { GlCollapsibleListbox } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { stubComponent } from 'helpers/stub_component';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import VersionsDropdown from 'ee/cd/components/application_details/releases/versions_dropdown.vue';
import cdVersionCreateMutation from 'ee/cd/graphql/applications/releases/cd_version_create.mutation.graphql';
import { cdVersionCreateResponse } from 'ee/cd/../../../../spec/frontend/cd/mock_data';

Vue.use(VueApollo);

const ARTIFACT_SOURCE_ID = 'gid://gitlab/Cd::ArtifactSource/1';
const CREATED_ID = 'gid://gitlab/Cd::Version/99';

const versionItems = [
  {
    value: 'gid://gitlab/Cd::Version/2',
    text: 'v2.0.0',
    verified: true,
    environments: ['production'],
  },
  { value: 'gid://gitlab/Cd::Version/1', text: 'v1.0.0', verified: true, environments: [] },
];

const GlCollapsibleListboxStub = stubComponent(GlCollapsibleListbox, {
  template: `<div>
    <template v-for="item in items"><slot name="list-item" :item="item"></slot></template>
    <slot name="footer"></slot>
  </div>`,
  methods: { close: () => {} },
});

describe('VersionsDropdown', () => {
  let wrapper;
  let createHandler;

  const findListbox = () => wrapper.findComponent(GlCollapsibleListbox);
  const findCreateButton = () => wrapper.findComponentByTestId('create-version-button');
  const findSubtexts = () => wrapper.findAllByTestId('version-subtext');

  const createComponent = ({ props = {}, handler } = {}) => {
    createHandler = handler ?? jest.fn().mockResolvedValue(cdVersionCreateResponse());

    wrapper = shallowMountExtended(VersionsDropdown, {
      apolloProvider: createMockApollo([[cdVersionCreateMutation, createHandler]]),
      propsData: { artifactSourceId: ARTIFACT_SOURCE_ID, versionItems, ...props },
      stubs: { GlCollapsibleListbox: GlCollapsibleListboxStub },
    });
  };

  const search = async (term) => {
    findListbox().vm.$emit('search', term);
    await nextTick();
  };

  const create = async () => {
    findCreateButton().vm.$emit('click');
    await waitForPromises();
  };

  beforeEach(() => {
    createComponent();
  });

  it('makes the listbox searchable', () => {
    expect(findListbox().props('searchable')).toBe(true);
    expect(findListbox().props('searchPlaceholder')).toBe('Search version');
  });

  it('renders every version', () => {
    expect(findListbox().props('items')).toEqual(versionItems);
  });

  it('renders a subtext per version', () => {
    expect(findSubtexts().wrappers.map((subtext) => subtext.text())).toEqual([
      'production',
      'not deployed',
    ]);
  });

  describe('when a version is selected', () => {
    beforeEach(() => {
      createComponent({ props: { selected: 'gid://gitlab/Cd::Version/2' } });
    });

    it('renders environments names in the toggle text', () => {
      expect(findListbox().props('toggleText')).toBe('v2.0.0 · production');
    });
  });

  describe('when nothing is selected', () => {
    it('renders placeholder toggle text', () => {
      expect(findListbox().props('toggleText')).toBe('Select version');
    });
  });

  describe('when a version is deployed to more environments than fit', () => {
    beforeEach(() => {
      createComponent({
        props: {
          versionItems: [
            {
              value: 'gid://gitlab/Cd::Version/3',
              text: 'v3.0.0',
              verified: true,
              environments: ['production', 'staging', 'qa', 'dev'],
            },
          ],
          selected: 'gid://gitlab/Cd::Version/3',
        },
      });
    });

    it('renders the first two and counts the rest', () => {
      expect(findSubtexts().at(0).text()).toBe('production, staging +2');
    });
  });

  describe('when the term matches a version', () => {
    beforeEach(async () => {
      await search('v2');
    });

    it('renders only matching versions', () => {
      expect(findListbox().props('items')).toEqual([versionItems[0]]);
    });

    it('renders create button', () => {
      expect(findCreateButton().text()).toBe('Use "v2"');
    });
  });

  describe('when the term matches a version exactly', () => {
    beforeEach(async () => {
      await search('V1.0.0');
    });

    it('does not render create button', () => {
      expect(findCreateButton().exists()).toBe(false);
    });
  });

  describe('when the term matches nothing', () => {
    beforeEach(async () => {
      await search('2026-08-summer');
    });

    it('renders create button with searched name', () => {
      expect(findCreateButton().text()).toBe('Use "2026-08-summer"');
    });

    it('renders searched name unescaped', async () => {
      await search("mike's & co");

      expect(findCreateButton().text()).toBe('Use "mike\'s & co"');
    });

    it('calls create mutation once when clicked twice', async () => {
      findCreateButton().vm.$emit('click');
      findCreateButton().vm.$emit('click');
      await waitForPromises();

      expect(createHandler).toHaveBeenCalledTimes(1);
    });

    describe('when the offer is accepted', () => {
      let closeSpy;

      beforeEach(async () => {
        closeSpy = jest.spyOn(findListbox().vm, 'close');
        await create();
      });

      it('calls create mutation', () => {
        expect(createHandler).toHaveBeenCalledWith({
          input: { artifactSourceId: ARTIFACT_SOURCE_ID, name: '2026-08-summer' },
        });
      });

      it('emits select with new version', () => {
        expect(wrapper.emitted('select')).toEqual([[CREATED_ID]]);
      });

      it('closes the dropdown', () => {
        expect(closeSpy).toHaveBeenCalled();
      });
    });

    describe('when the mutation returns errors', () => {
      beforeEach(async () => {
        createComponent({
          handler: jest
            .fn()
            .mockResolvedValue(
              cdVersionCreateResponse({ errors: ['Name has already been taken'] }),
            ),
        });
        await search('2026-08-summer');
        await create();
      });

      it('emits error with message', () => {
        expect(wrapper.emitted('error').at(-1)).toEqual(['Name has already been taken']);
      });

      it('does not emit select', () => {
        expect(wrapper.emitted('select')).toBeUndefined();
      });
    });

    describe('when the mutation throws', () => {
      beforeEach(async () => {
        jest.spyOn(Sentry, 'captureException').mockImplementation();
        createComponent({ handler: jest.fn().mockRejectedValue(new Error('boom')) });
        await search('2026-08-summer');
        await create();
      });

      it('emits error with a generic message', () => {
        expect(wrapper.emitted('error').at(-1)).toEqual([
          'Failed to add the version. Please try again.',
        ]);
      });

      it('reports exception to Sentry', () => {
        expect(Sentry.captureException).toHaveBeenCalledWith(new Error('boom'));
      });
    });
  });

  describe('when the source has no versions', () => {
    beforeEach(async () => {
      createComponent({ props: { versionItems: [] } });
      await search('only-option');
    });

    it('renders create button', () => {
      expect(findCreateButton().text()).toBe('Use "only-option"');
    });
  });

  describe('when the dropdown is closed', () => {
    beforeEach(async () => {
      await search('2026-08-summer');
      findListbox().vm.$emit('hidden');
      await nextTick();
    });

    it('does not render create button', () => {
      expect(findCreateButton().exists()).toBe(false);
    });

    it('renders every version', () => {
      expect(findListbox().props('items')).toEqual(versionItems);
    });
  });

  describe('when the name is too long', () => {
    beforeEach(async () => {
      await search('a'.repeat(256));
      findCreateButton().vm.$emit('click');
      await waitForPromises();
    });

    it('emits error with the limit', () => {
      expect(wrapper.emitted('error').at(-1)).toEqual([
        'Version name cannot exceed 255 characters.',
      ]);
    });

    it('does not call create mutation', () => {
      expect(createHandler).not.toHaveBeenCalled();
    });
  });

  describe('when a version is unverified and undeployed', () => {
    beforeEach(() => {
      createComponent({
        props: {
          versionItems: [{ value: CREATED_ID, text: 'typed', verified: false, environments: [] }],
          selected: CREATED_ID,
        },
      });
    });

    it('renders unverified subtext', () => {
      expect(findSubtexts().at(0).text()).toBe('unverified version');
      expect(findListbox().props('toggleText')).toBe('typed · unverified version');
    });
  });
});
