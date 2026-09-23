import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlCollapsibleListbox, GlFormGroup, GlLoadingIcon, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import NoNamespaceEmptyState from 'ee/ai/duo_agentic_chat/components/no_namespace_empty_state.vue';
import getDuoDefaultNamespaceCandidates from 'ee/ai/graphql/get_duo_default_namespace_candidates.query.graphql';
import updateDuoDefaultNamespace from 'ee/ai/graphql/update_duo_default_namespace.mutation.graphql';

Vue.use(VueApollo);

describe('NoNamespaceEmptyState', () => {
  let wrapper;

  const NAMESPACE_1 = {
    id: 'gid://gitlab/Group/1',
    name: 'Group One',
    fullPath: 'group-one',
    avatarUrl: 'https://example.com/group-one/avatar.png',
  };
  const NAMESPACE_2 = {
    id: 'gid://gitlab/Group/2',
    name: 'Group Two',
    fullPath: 'group-two',
    avatarUrl: null,
  };

  const LISTBOX_ITEM_1 = {
    value: NAMESPACE_1.id,
    text: NAMESPACE_1.name,
    avatarUrl: NAMESPACE_1.avatarUrl,
    entityId: 1,
  };
  const LISTBOX_ITEM_2 = {
    value: NAMESPACE_2.id,
    text: NAMESPACE_2.name,
    avatarUrl: NAMESPACE_2.avatarUrl,
    entityId: 2,
  };

  const buildGroupedItems = (options) => [{ text: 'Groups with GitLab Duo enabled', options }];

  const buildCandidatesResponse = (nodes = [NAMESPACE_1, NAMESPACE_2]) => ({
    data: {
      duoDefaultNamespaceCandidates: { nodes },
    },
  });

  const buildUpdateResponse = ({ errors = [] } = {}) => ({
    data: {
      userPreferencesUpdate: {
        userPreferences: {
          duoDefaultNamespace: {
            id: NAMESPACE_1.id,
            name: NAMESPACE_1.name,
            fullPath: NAMESPACE_1.fullPath,
          },
        },
        errors,
      },
    },
  });

  let candidatesQueryMock;
  let updateMutationMock;

  const createComponent = ({
    props = {},
    queryHandler = candidatesQueryMock,
    mutationHandler = updateMutationMock,
  } = {}) => {
    const apolloProvider = createMockApollo([
      [getDuoDefaultNamespaceCandidates, queryHandler],
      [updateDuoDefaultNamespace, mutationHandler],
    ]);

    wrapper = shallowMountExtended(NoNamespaceEmptyState, {
      apolloProvider,
      propsData: {
        isClassicAvailable: true,
        ...props,
      },
      stubs: { GlSprintf },
    });
  };

  const findContainer = () => wrapper.findByTestId('no-namespace-empty-state');
  const findHeading = () => wrapper.find('h2');
  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);
  const findListbox = () => wrapper.findComponent(GlCollapsibleListbox);
  const findFormGroup = () => wrapper.findComponent(GlFormGroup);
  const findConfirmButton = () => wrapper.findComponentByTestId('confirm-namespace-button');
  const findReturnToNonAgenticButton = () =>
    wrapper.findComponentByTestId('return-to-non-agentic-button');
  const findNoGroupsMessage = () => wrapper.findByTestId('no-groups-message');

  beforeEach(() => {
    candidatesQueryMock = jest.fn().mockResolvedValue(buildCandidatesResponse());
    updateMutationMock = jest.fn().mockResolvedValue(buildUpdateResponse());
  });

  describe('rendering', () => {
    it('renders the container', async () => {
      createComponent();
      await waitForPromises();

      expect(findContainer().exists()).toBe(true);
    });

    it('renders the title', async () => {
      createComponent();
      await waitForPromises();

      expect(findHeading().text()).toBe('Choose a group to use Agentic Chat');
    });

    describe('while loading', () => {
      it('shows a loading icon', () => {
        createComponent();

        expect(findLoadingIcon().exists()).toBe(true);
        expect(findListbox().exists()).toBe(false);
      });
    });

    describe('when namespace candidates are available', () => {
      beforeEach(async () => {
        createComponent();
        await waitForPromises();
      });

      it('renders the listbox with namespace options grouped under a Duo-enabled header', () => {
        expect(findListbox().exists()).toBe(true);
        expect(findListbox().props('items')).toEqual(
          buildGroupedItems([LISTBOX_ITEM_1, LISTBOX_ITEM_2]),
        );
      });

      it('renders a searchable listbox', () => {
        expect(findListbox().props('searchable')).toBe(true);
      });

      it('renders the confirm button (enabled even without a selection)', () => {
        expect(findConfirmButton().exists()).toBe(true);
        expect(findConfirmButton().props('disabled')).toBe(false);
      });

      it('does not render the no-groups message', () => {
        expect(findNoGroupsMessage().exists()).toBe(false);
      });
    });

    describe('when namespace candidates arrive in non-alphabetical order', () => {
      beforeEach(async () => {
        candidatesQueryMock = jest
          .fn()
          .mockResolvedValue(buildCandidatesResponse([NAMESPACE_2, NAMESPACE_1]));
        createComponent();
        await waitForPromises();
      });

      it('sorts the listbox items by name', () => {
        expect(findListbox().props('items')).toEqual(
          buildGroupedItems([LISTBOX_ITEM_1, LISTBOX_ITEM_2]),
        );
      });
    });

    describe('searching', () => {
      beforeEach(async () => {
        createComponent();
        await waitForPromises();
      });

      it('uses the default no-results text', () => {
        expect(findListbox().props('noResultsText')).toBe('No results found');
      });

      it('filters the listbox items case-insensitively', async () => {
        findListbox().vm.$emit('search', 'oNe');
        await nextTick();

        expect(findListbox().props('items')).toEqual(buildGroupedItems([LISTBOX_ITEM_1]));
      });

      it('passes empty items (no group header) when no namespace matches', async () => {
        findListbox().vm.$emit('search', 'does not match');
        await nextTick();

        expect(findListbox().props('items')).toEqual([]);
      });

      it('restores all items when the search term is cleared', async () => {
        findListbox().vm.$emit('search', 'does not match');
        await nextTick();
        findListbox().vm.$emit('search', '');
        await nextTick();

        expect(findListbox().props('items')).toEqual(
          buildGroupedItems([LISTBOX_ITEM_1, LISTBOX_ITEM_2]),
        );
      });
    });

    describe('when no namespace candidates are available', () => {
      beforeEach(async () => {
        candidatesQueryMock = jest.fn().mockResolvedValue(buildCandidatesResponse([]));
        createComponent();
        await waitForPromises();
      });

      it('renders the no-groups message', () => {
        expect(findNoGroupsMessage().exists()).toBe(true);
        expect(findListbox().exists()).toBe(false);
        expect(findConfirmButton().exists()).toBe(false);
      });
    });

    describe('when the candidates query fails', () => {
      beforeEach(async () => {
        candidatesQueryMock = jest.fn().mockRejectedValue(new Error('Network error'));
        createComponent();
        await waitForPromises();
      });

      it('renders the regular UI with the listbox and confirm button', () => {
        expect(findListbox().exists()).toBe(true);
        expect(findConfirmButton().exists()).toBe(true);
        expect(findConfirmButton().props('disabled')).toBe(false);
        expect(findNoGroupsMessage().exists()).toBe(false);
      });

      it('renders the description text', () => {
        expect(wrapper.text()).toContain(
          'This determines where your GitLab Duo usage is tracked. You can change this any time in your profile preferences.',
        );
      });

      it('passes the fetch error as the listbox no-results-text', () => {
        expect(findListbox().props('noResultsText')).toBe('Unable to load groups. Try again.');
      });

      it('passes empty items to the listbox', () => {
        expect(findListbox().props('items')).toEqual([]);
      });

      it('disables search since there is nothing to filter', () => {
        expect(findListbox().props('searchable')).toBe(false);
      });

      it('still renders the return-to-non-agentic button when isClassicAvailable is true', () => {
        expect(findReturnToNonAgenticButton().exists()).toBe(true);
      });
    });
  });

  describe('isClassicAvailable prop', () => {
    describe('when isClassicAvailable is true', () => {
      beforeEach(async () => {
        createComponent({ props: { isClassicAvailable: true } });
        await waitForPromises();
      });

      it('renders the return-to-non-agentic button', () => {
        expect(findReturnToNonAgenticButton().exists()).toBe(true);
      });
    });

    describe('when isClassicAvailable is false', () => {
      beforeEach(async () => {
        createComponent({ props: { isClassicAvailable: false } });
        await waitForPromises();
      });

      it('does not render the return-to-non-agentic button', () => {
        expect(findReturnToNonAgenticButton().exists()).toBe(false);
      });
    });
  });

  describe('namespace selection', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('updates the listbox toggle text to the selected namespace name', async () => {
      findListbox().vm.$emit('select', NAMESPACE_1.id);
      await nextTick();

      expect(findListbox().props('toggleText')).toBe(NAMESPACE_1.name);
    });

    it('clears validation state when a namespace is selected', async () => {
      await findConfirmButton().vm.$emit('click');
      await nextTick();

      expect(findFormGroup().vm.$attrs.state).toBe(false);

      findListbox().vm.$emit('select', NAMESPACE_1.id);
      await nextTick();

      expect(findFormGroup().vm.$attrs.state).toBeNull();
      expect(findListbox().props('toggleClass')).toBeNull();
    });
  });

  describe('validation', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('shows validation feedback and a red toggle when confirming without a selection', async () => {
      expect(findFormGroup().vm.$attrs.state).toBeNull();

      await findConfirmButton().vm.$emit('click');
      await nextTick();

      expect(findFormGroup().vm.$attrs.state).toBe(false);
      expect(findFormGroup().vm.$attrs['invalid-feedback']).toBe('Select a group to continue');
      expect(findListbox().props('toggleClass')).toBe('!gl-shadow-inner-1-red-400');
    });

    it('does not call the mutation when confirming without a selection', async () => {
      await findConfirmButton().vm.$emit('click');
      await waitForPromises();

      expect(updateMutationMock).not.toHaveBeenCalled();
    });
  });

  describe('confirming namespace selection', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();

      findListbox().vm.$emit('select', NAMESPACE_1.id);
      await nextTick();
    });

    it('calls the mutation with the correct namespace id', async () => {
      await findConfirmButton().vm.$emit('click');
      await waitForPromises();

      expect(updateMutationMock).toHaveBeenCalledWith({
        input: { duoDefaultNamespaceId: 1 },
      });
    });

    it('emits "namespace-selected" on success', async () => {
      await findConfirmButton().vm.$emit('click');
      await waitForPromises();

      expect(wrapper.emitted('namespace-selected')).toHaveLength(1);
    });

    it('keeps the confirm button loading after a successful save', async () => {
      await findConfirmButton().vm.$emit('click');
      await waitForPromises();

      expect(findConfirmButton().props('loading')).toBe(true);
    });
  });

  describe('when the mutation returns errors', () => {
    beforeEach(async () => {
      updateMutationMock = jest
        .fn()
        .mockResolvedValue(buildUpdateResponse({ errors: ['Something went wrong'] }));
      createComponent();
      await waitForPromises();

      findListbox().vm.$emit('select', NAMESPACE_1.id);
      await nextTick();
    });

    it('emits a save-error event with the error message', async () => {
      await findConfirmButton().vm.$emit('click');
      await waitForPromises();

      expect(wrapper.emitted('save-error')).toContainEqual([
        'Unable to save your namespace selection. Try again.',
      ]);
      expect(wrapper.emitted('namespace-selected')).toBeUndefined();
    });

    it('clears the confirm button loading state after a failed save', async () => {
      await findConfirmButton().vm.$emit('click');
      await waitForPromises();

      expect(findConfirmButton().props('loading')).toBe(false);
    });

    it('emits a save-error event with an empty message when the namespace is reselected', async () => {
      await findConfirmButton().vm.$emit('click');
      await waitForPromises();

      findListbox().vm.$emit('select', NAMESPACE_2.id);
      await nextTick();

      expect(wrapper.emitted('save-error').at(-1)).toEqual(['']);
    });
  });

  describe('when the mutation throws', () => {
    beforeEach(async () => {
      updateMutationMock = jest.fn().mockRejectedValue(new Error('Network error'));
      createComponent();
      await waitForPromises();

      findListbox().vm.$emit('select', NAMESPACE_1.id);
      await nextTick();
    });

    it('emits a save-error event with the error message', async () => {
      await findConfirmButton().vm.$emit('click');
      await waitForPromises();

      expect(wrapper.emitted('save-error')).toContainEqual([
        'Unable to save your namespace selection. Try again.',
      ]);
      expect(wrapper.emitted('namespace-selected')).toBeUndefined();
    });

    it('clears the confirm button loading state after the mutation throws', async () => {
      await findConfirmButton().vm.$emit('click');
      await waitForPromises();

      expect(findConfirmButton().props('loading')).toBe(false);
    });
  });

  describe('events', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('emits "return-to-classic" when the return-to-non-agentic button is clicked', () => {
      findReturnToNonAgenticButton().vm.$emit('click');

      expect(wrapper.emitted('return-to-classic')).toHaveLength(1);
    });
  });

  describe('when no namespace candidates are available and isClassicAvailable is true', () => {
    beforeEach(async () => {
      candidatesQueryMock = jest.fn().mockResolvedValue(buildCandidatesResponse([]));
      createComponent({ props: { isClassicAvailable: true } });
      await waitForPromises();
    });

    it('renders the return-to-non-agentic button in the no-groups state', () => {
      expect(findReturnToNonAgenticButton().exists()).toBe(true);
    });

    it('emits "return-to-classic" when the button is clicked', () => {
      findReturnToNonAgenticButton().vm.$emit('click');

      expect(wrapper.emitted('return-to-classic')).toHaveLength(1);
    });
  });
});
