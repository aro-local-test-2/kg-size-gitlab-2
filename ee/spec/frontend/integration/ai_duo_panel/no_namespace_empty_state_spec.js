import { fireEvent, waitFor } from '@testing-library/vue';
import { screen, within, waitForElement } from 'ee_jest/integration/helpers/test_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { useMockLocationHelper } from 'helpers/mock_window_location_helper';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { lastRequestVariables } from '../core/operation_helpers';
import {
  getDuoDefaultNamespaceCandidates,
  duoDefaultNamespaceCandidatesVariants,
  installDuoAIPanelHandlers,
} from './test_support/api_handlers';
import {
  buildChatConfiguration,
  findChatToggle,
  findDuoDisabledToggle,
  mountAISidebar,
  openChatTab,
  setupDuoChatTest,
  teardownDuoChatTest,
} from './test_support/test_setup';

// A Duo user with no default namespace opens the panel outside a group/project.
// Both `agenticAvailable` and `classicAvailable` are 'false' because that is what
// the backend sends here (the policies deny against a nil container) — the prompt
// must render anyway.
describe('AI panel when no default Duo namespace is selected', () => {
  const mountNoNamespacePanel = (defaultProps = {}) =>
    mountAISidebar({
      chatConfiguration: buildChatConfiguration({
        defaultProps: {
          isAgenticAvailable: false,
          isClassicAvailable: false,
          defaultNamespaceSelected: false,
          defaultNamespaceRequired: true,
          shouldShowBlockedState: true,
          namespaceId: null,
          rootNamespaceId: null,
          projectId: null,
          ...defaultProps,
        },
      }),
    });

  const findEmptyState = () => screen.queryByTestId('no-namespace-empty-state');
  const findListbox = () => document.querySelector('[data-testid="namespace-listbox"]');
  const findConfirmButton = () =>
    document.querySelector('[data-testid="confirm-namespace-button"]');
  const findNoGroupsMessage = () => screen.queryByTestId('no-groups-message');
  const findReturnToNonAgenticButton = () => screen.queryByTestId('return-to-non-agentic-button');
  const findAgenticModeToggle = () => screen.queryByRole('switch', { name: /agentic/i });

  beforeEach(() => {
    setupDuoChatTest();
    installDuoAIPanelHandlers();
  });

  afterEach(() => teardownDuoChatTest());

  it('renders the inline group selector fed by the candidates query', async () => {
    mountNoNamespacePanel();

    const toggle = await waitForElement(findDuoDisabledToggle);
    toggle.click();

    await waitForElement(findEmptyState);
    await waitFor(() => {
      expect(findListbox()).not.toBe(null);
    });

    expect(findConfirmButton()).not.toBe(null);
    expect(findNoGroupsMessage()).toBe(null);
  });

  it('explains there are no groups to pick when the candidates list is empty', async () => {
    setQueryVariant(duoDefaultNamespaceCandidatesVariants).empty();

    mountNoNamespacePanel();

    const toggle = await waitForElement(findDuoDisabledToggle);
    toggle.click();

    await waitForElement(findEmptyState);
    await waitForElement(findNoGroupsMessage);

    expect(findListbox()).toBe(null);
    expect(findConfirmButton()).toBe(null);
  });

  it('does not render a return-to-classic button or the agentic toggle', async () => {
    mountNoNamespacePanel();

    const toggle = await waitForElement(findDuoDisabledToggle);
    toggle.click();

    await waitForElement(findEmptyState);

    expect(findReturnToNonAgenticButton()).toBe(null);
    expect(findAgenticModeToggle()).toBe(null);
  });
});

// Exercises the state-manager-routed empty state (Duo available, just no default
// namespace yet), as opposed to the blocked-state-routed one covered above.
describe('AI panel when the state manager needs a default Duo namespace', () => {
  useMockLocationHelper();

  const mountAgenticPanelWithoutNamespace = () =>
    mountAISidebar({
      chatConfiguration: buildChatConfiguration({
        defaultProps: {
          defaultNamespaceSelected: false,
          // Skips the `hasCredits` query: no MSW handler needs wiring for it here,
          // and credit status is irrelevant to this namespace-selection flow.
          isSubscriptionExpired: true,
        },
      }),
    });

  const findGroupSelectorEmptyState = () => screen.queryByTestId('no-namespace-empty-state');
  const findGroupListbox = () => document.querySelector('[data-testid="namespace-listbox"]');
  const findGroupListboxToggle = () =>
    within(findGroupListbox()).queryByTestId('base-dropdown-toggle');
  const findGroupOption = (groupId) => screen.queryByTestId(`listbox-item-${groupId}`);
  const findGroupConfirmButton = () =>
    document.querySelector('[data-testid="confirm-namespace-button"]');

  beforeEach(() => {
    setupDuoChatTest();
    installDuoAIPanelHandlers();
  });

  afterEach(() => teardownDuoChatTest());

  it('narrows the list to matching groups when typing in the search box', async () => {
    const [hiddenGroup, matchingGroup] = getDuoDefaultNamespaceCandidates.namespaces();

    mountAgenticPanelWithoutNamespace();

    await waitForElement(findChatToggle);
    openChatTab();

    await waitForElement(findGroupSelectorEmptyState);

    const listboxToggle = await waitForElement(findGroupListboxToggle);
    listboxToggle.click();

    await waitForElement(() => findGroupOption(hiddenGroup.id));

    const searchInput = within(findGroupListbox()).getByRole('combobox');
    await fireEvent.update(searchInput, matchingGroup.name);

    await waitFor(() => {
      expect(findGroupOption(hiddenGroup.id)).toBe(null);
    });
    expect(findGroupOption(matchingGroup.id)).not.toBe(null);
  });

  it('selects a group from the listbox, saves it, and reloads the page', async () => {
    // Any candidate proves the flow; take the first so a regeneration that reorders
    // or renumbers the groups does not break this.
    const [candidate] = getDuoDefaultNamespaceCandidates.namespaces();

    mountAgenticPanelWithoutNamespace();

    await waitForElement(findChatToggle);
    openChatTab();

    await waitForElement(findGroupSelectorEmptyState);

    const listboxToggle = await waitForElement(findGroupListboxToggle);
    listboxToggle.click();

    const groupOption = await waitForElement(() => findGroupOption(candidate.id));
    groupOption.click();

    const confirmButton = await waitForElement(findGroupConfirmButton);
    confirmButton.click();

    await waitFor(() => {
      expect(lastRequestVariables('updateDuoDefaultNamespace')).toEqual({
        input: { duoDefaultNamespaceId: getIdFromGraphQLId(candidate.id) },
      });
    });

    await waitFor(() => {
      expect(window.location.reload).toHaveBeenCalledTimes(1);
    });
  });
});
