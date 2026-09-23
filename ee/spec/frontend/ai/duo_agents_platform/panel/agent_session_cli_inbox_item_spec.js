import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import AgentSessionCliInboxItem from 'ee/ai/duo_agents_platform/panel/agent_session_cli_inbox_item.vue';
import InboxRow from 'ee/ai/duo_agents_platform/panel/inbox_row.vue';
import { buildInboxRowItem } from '../../mocks';

describe('AgentSessionCliInboxItem', () => {
  let wrapper;

  const item = buildInboxRowItem({
    status: 'INPUT_REQUIRED',
    humanStatus: 'input required',
    flowMetadataVersion: '2.1.0-interactive',
  });

  beforeEach(() => {
    wrapper = shallowMountExtended(AgentSessionCliInboxItem, {
      propsData: { item },
      stubs: { InboxRow },
      mocks: { $router: { push: jest.fn() } },
    });
  });

  const findInboxRow = () => wrapper.findComponent(InboxRow);
  const findCliIcon = () => wrapper.findComponentByTestId('item-cli-icon');
  const findCliLabel = () => wrapper.findByTestId('item-cli-label');
  const findStatusLabel = () => wrapper.findByTestId('item-status-label');
  const findCliReadOnlyNote = () => wrapper.findByTestId('item-cli-readonly-note');
  const findTitle = () => wrapper.findByTestId('item-title');
  const findMetadata = () => wrapper.findByTestId('item-metadata');

  it('hands the item to the row', () => {
    expect(findInboxRow().props('item')).toBe(item);
  });

  it('renders a decorative terminal icon and the "CLI" label in place of a status', () => {
    expect(findCliIcon().props('name')).toBe('terminal');
    expect(findCliIcon().attributes('aria-hidden')).toBe('true');
    expect(findCliLabel().text()).toBe('CLI');
    expect(findStatusLabel().exists()).toBe(false);
  });

  it('renders the read-only note under the title', () => {
    expect(findCliReadOnlyNote().text()).toBe('Read-only on the web');
  });

  it('keeps the title and metadata line from the row', () => {
    expect(findTitle().text()).toBe('Fix the login bug');
    expect(findMetadata().text()).toContain('42');
  });
});
