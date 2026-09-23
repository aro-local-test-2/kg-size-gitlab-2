import { GlBadge, GlButton } from '@gitlab/ui';
import { shallowMount } from '@vue/test-utils';
import { nextTick } from 'vue';
import waitForPromises from 'helpers/wait_for_promises';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import { createAlert } from '~/alert';
import OrbitCodePanel from 'ee/orbit/components/orbit_code_panel.vue';
import * as orbitApi from 'ee/orbit/api/orbit_api';

jest.mock('~/alert');
jest.mock('ee/orbit/api/orbit_api');

const PROJECT_ID = 'gid://gitlab/Project/1';
const PROJECT_PATH = 'gitlab-org/gitlab';
const CURRENT_REF = 'main';
const FILE_PATH = 'app/services/user_service.rb';

const mockDefinitions = [
  {
    id: '1',
    type: 'Definition',
    name: 'UserService',
    fqn: 'App::UserService',
    definition_type: 'Class',
    file_path: FILE_PATH,
    start_line: '0',
  },
  {
    id: '2',
    type: 'Definition',
    name: 'get_user',
    fqn: 'App::UserService#get_user',
    definition_type: 'Method',
    file_path: FILE_PATH,
    start_line: '5',
  },
  {
    id: '3',
    type: 'Definition',
    name: 'create_user',
    fqn: 'App::UserService#create_user',
    definition_type: 'Function',
    file_path: FILE_PATH,
    start_line: '12',
  },
];

const mockCallerEdges = [
  { type: 'CALLS', from_id: '10', to_id: '2' },
  { type: 'CALLS', from_id: '11', to_id: '2' },
  { type: 'CALLS', from_id: '12', to_id: '3' },
  { type: 'CALLS', from_id: '2', to_id: '2' },
];

const mockReferences = [
  {
    id: '10',
    type: 'Definition',
    name: 'run',
    fqn: 'App::Runner#run',
    definition_type: 'Method',
    file_path: 'app/runner.rb',
    start_line: '8',
  },
  {
    id: '11',
    type: 'Definition',
    name: 'execute',
    fqn: 'App::Worker#execute',
    definition_type: 'Method',
    file_path: 'app/worker.rb',
    start_line: '3',
  },
];

const mockCallees = [
  {
    id: '20',
    type: 'Definition',
    name: 'find_by_id',
    fqn: 'App::Repo#find_by_id',
    definition_type: 'Method',
    file_path: 'app/repo.rb',
    start_line: '15',
  },
];

const definesResponse = () => ({ data: { result: { nodes: mockDefinitions, edges: [] } } });
const callersResponse = () => ({
  data: { result: { nodes: [], edges: mockCallerEdges } },
});
const referencesResponse = () => ({
  // API returns both caller nodes and the target def; target def must be filtered out
  data: { result: { nodes: [...mockReferences, mockDefinitions[1]], edges: [] } },
});
const calleesResponse = () => ({
  data: { result: { nodes: [...mockCallees, mockDefinitions[1]], edges: [] } },
});
const emptyResponse = () => ({ data: { result: { nodes: [], edges: [] } } });

describe('OrbitCodePanel', () => {
  let wrapper;

  const createWrapper = (props = {}) => {
    wrapper = shallowMount(OrbitCodePanel, {
      propsData: {
        projectId: PROJECT_ID,
        projectPath: PROJECT_PATH,
        currentRef: CURRENT_REF,
        filePath: FILE_PATH,
        ...props,
      },
      stubs: {
        // Render slots so we can test the panel header and body content
        CrudComponent: {
          template:
            '<div><slot name="title" /><slot name="actions" /><slot /><slot name="footer" /></div>',
        },
      },
    });
  };

  const setupFetchData = () => {
    orbitApi.executeOrbitNamedQuery
      .mockResolvedValueOnce(definesResponse())
      .mockResolvedValueOnce(callersResponse());
  };

  const setupSelectDef = () => {
    orbitApi.executeOrbitNamedQuery
      .mockResolvedValueOnce(referencesResponse())
      .mockResolvedValueOnce(calleesResponse());
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('on mount', () => {
    it('fires the file definitions and callers named queries in parallel', () => {
      setupFetchData();
      createWrapper();

      expect(orbitApi.executeOrbitNamedQuery).toHaveBeenCalledTimes(2);

      const expectedOptions = {
        parameters: { project_id: 1, file_path: FILE_PATH },
        sourceType: 'code_intelligence',
      };
      expect(orbitApi.executeOrbitNamedQuery).toHaveBeenCalledWith(
        'file_definitions',
        expectedOptions,
      );
      expect(orbitApi.executeOrbitNamedQuery).toHaveBeenCalledWith(
        'file_definition_callers',
        expectedOptions,
      );
    });

    it('renders the symbol list after data loads', async () => {
      setupFetchData();
      createWrapper();
      await waitForPromises();

      expect(wrapper.find('[data-testid="symbol-list"]').exists()).toBe(true);
      expect(wrapper.findAll('[data-testid="symbol-item"]')).toHaveLength(mockDefinitions.length);
    });

    it('shows the no-symbols message when the file has no definitions', async () => {
      orbitApi.executeOrbitNamedQuery
        .mockResolvedValueOnce(emptyResponse())
        .mockResolvedValueOnce(emptyResponse());
      createWrapper();
      await waitForPromises();

      expect(wrapper.find('[data-testid="no-symbols"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="symbol-list"]').exists()).toBe(false);
    });

    it('does not fetch when projectId is missing', () => {
      createWrapper({ projectId: null });

      expect(orbitApi.executeOrbitNamedQuery).not.toHaveBeenCalled();
    });

    it('shows an alert on fetch failure', async () => {
      orbitApi.executeOrbitNamedQuery.mockRejectedValue(new Error('network error'));
      createWrapper();
      await waitForPromises();

      expect(createAlert).toHaveBeenCalledWith(expect.objectContaining({ variant: 'warning' }));
    });
  });

  describe('Orbit attribution', () => {
    beforeEach(async () => {
      setupFetchData();
      createWrapper();
      await waitForPromises();
    });

    it('marks the panel as Orbit-powered', () => {
      expect(wrapper.find('[data-testid="orbit-marker"]').attributes('name')).toBe('orbit');
    });

    it('shows a Beta badge', () => {
      expect(wrapper.find('[data-testid="beta-badge"]').text()).toBe('Beta');
    });
  });

  describe('caller-count badges', () => {
    it('shows a badge with the correct count for symbols that have callers', async () => {
      setupFetchData();
      createWrapper();
      await waitForPromises();

      const items = wrapper.findAll('[data-testid="symbol-item"]');
      // get_user (id 2) has 2 caller edges plus a self-call that must not count
      const getUserItem = items.wrappers.find((li) => li.text().includes('get_user'));
      expect(getUserItem.findComponent(GlBadge).text()).toBe('2 callers');
    });

    it('does not show a badge for symbols with no callers', async () => {
      setupFetchData();
      createWrapper();
      await waitForPromises();

      const items = wrapper.findAll('[data-testid="symbol-item"]');
      const userServiceItem = items.wrappers.find((li) => li.text().includes('UserService'));
      expect(userServiceItem.findComponent(GlBadge).exists()).toBe(false);
    });

    it('does not show a badge for a symbol whose only caller is itself', async () => {
      orbitApi.executeOrbitNamedQuery
        .mockResolvedValueOnce(definesResponse())
        .mockResolvedValueOnce({
          data: { result: { nodes: [], edges: [{ type: 'CALLS', from_id: '3', to_id: '3' }] } },
        });
      createWrapper();
      await waitForPromises();

      const items = wrapper.findAll('[data-testid="symbol-item"]');
      const createUserItem = items.wrappers.find((li) => li.text().includes('create_user'));
      expect(createUserItem.findComponent(GlBadge).exists()).toBe(false);
    });
  });

  describe('symbol type ordering', () => {
    it('sorts definitions by type order (Class before Method before Function)', async () => {
      setupFetchData();
      createWrapper();
      await waitForPromises();

      const items = wrapper.findAll('[data-testid="symbol-item"]');
      const names = items.wrappers.map((li) => li.text().split(' ')[0]);
      const classIndex = names.findIndex((n) => n === 'UserService');
      const methodIndex = names.findIndex((n) => n === 'get_user');
      const functionIndex = names.findIndex((n) => n === 'create_user');

      expect(classIndex).toBeLessThan(methodIndex);
      expect(methodIndex).toBeLessThan(functionIndex);
    });
  });

  describe('navigating to symbol detail', () => {
    beforeEach(async () => {
      setupFetchData();
      createWrapper();
      await waitForPromises();

      setupSelectDef();
      await wrapper.findAll('[data-testid="symbol-item"]').at(1).trigger('click');
    });

    it('fires the references and callees named queries in parallel', () => {
      // First 2 calls are fetchData; next 2 are selectDef
      expect(orbitApi.executeOrbitNamedQuery).toHaveBeenCalledTimes(4);

      const expectedOptions = {
        // def at index 1 is get_user with id '2'
        parameters: { node_id: '2' },
        sourceType: 'code_intelligence',
      };
      expect(orbitApi.executeOrbitNamedQuery.mock.calls[2]).toEqual([
        'definition_references',
        expectedOptions,
      ]);
      expect(orbitApi.executeOrbitNamedQuery.mock.calls[3]).toEqual([
        'definition_callees',
        expectedOptions,
      ]);
    });

    it('shows the detail view with the symbol name', async () => {
      await waitForPromises();

      expect(wrapper.find('[data-testid="symbol-detail"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="symbol-detail"]').text()).toContain('get_user');
      expect(wrapper.find('[data-testid="symbol-list"]').exists()).toBe(false);
    });

    it('excludes the selected symbol itself from the references list', async () => {
      await waitForPromises();

      const refList = wrapper.find('[data-testid="references-list"]');
      expect(refList.exists()).toBe(true);
      expect(refList.text()).not.toContain('get_user');
      expect(refList.text()).toContain('run');
      expect(refList.text()).toContain('execute');
    });

    it('shows the back button', async () => {
      await waitForPromises();

      expect(wrapper.find('[data-testid="back-button"]').exists()).toBe(true);
    });
  });

  describe('back navigation', () => {
    it('returns to the symbol list when the back button is clicked', async () => {
      setupFetchData();
      createWrapper();
      await waitForPromises();

      setupSelectDef();
      await wrapper.findAll('[data-testid="symbol-item"]').at(0).trigger('click');
      await waitForPromises();

      expect(wrapper.find('[data-testid="symbol-detail"]').exists()).toBe(true);

      await wrapper.findComponent('[data-testid="back-button"]').vm.$emit('click');
      await nextTick();

      expect(wrapper.find('[data-testid="symbol-list"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="symbol-detail"]').exists()).toBe(false);
    });
  });

  describe('calls tab', () => {
    it('shows the calls list when the Calls tab is clicked', async () => {
      setupFetchData();
      createWrapper();
      await waitForPromises();

      setupSelectDef();
      await wrapper.findAll('[data-testid="symbol-item"]').at(1).trigger('click');
      await waitForPromises();

      expect(wrapper.find('[data-testid="calls-list"]').exists()).toBe(false);

      await wrapper.find('[data-testid="calls-tab"]').trigger('click');

      expect(wrapper.find('[data-testid="calls-list"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="calls-list"]').text()).toContain('find_by_id');
    });

    it('shows the no-calls message when there are no outbound calls', async () => {
      setupFetchData();
      createWrapper();
      await waitForPromises();

      orbitApi.executeOrbitNamedQuery
        .mockResolvedValueOnce(emptyResponse())
        .mockResolvedValueOnce(emptyResponse());
      await wrapper.findAll('[data-testid="symbol-item"]').at(0).trigger('click');
      await waitForPromises();

      await wrapper.find('[data-testid="calls-tab"]').trigger('click');

      expect(wrapper.find('[data-testid="no-calls"]').exists()).toBe(true);
    });
  });

  describe('close', () => {
    it('emits close when the close button is clicked', async () => {
      setupFetchData();
      createWrapper();

      const closeBtn = wrapper
        .findAllComponents(GlButton)
        .wrappers.find((b) => b.attributes('icon') === 'close');
      await closeBtn.vm.$emit('click');

      expect(wrapper.emitted('close')).toHaveLength(1);
    });
  });

  describe('filePath watcher', () => {
    it('re-fetches and resets selected symbol when filePath changes', async () => {
      setupFetchData();
      createWrapper();
      await waitForPromises();

      setupSelectDef();
      await wrapper.findAll('[data-testid="symbol-item"]').at(0).trigger('click');
      await waitForPromises();

      expect(wrapper.find('[data-testid="symbol-detail"]').exists()).toBe(true);

      setupFetchData();
      await wrapper.setProps({ filePath: 'app/other_service.rb' });
      await waitForPromises();

      expect(wrapper.find('[data-testid="symbol-list"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="symbol-detail"]').exists()).toBe(false);
    });
  });

  describe('internal events', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();

    const selectSymbol = async (index) => {
      setupSelectDef();
      await wrapper.findAll('[data-testid="symbol-item"]').at(index).trigger('click');
      await waitForPromises();
    };

    let trackEventSpy;

    beforeEach(async () => {
      setupFetchData();
      createWrapper();
      await waitForPromises();
      ({ trackEventSpy } = bindInternalEventDocument(wrapper.element));
    });

    it('tracks the panel being opened on mount', () => {
      expect(trackEventSpy).toHaveBeenCalledWith('open_code_navigation_panel', {}, undefined);
    });

    it('tracks symbol selection with the symbol type', async () => {
      // Index 1 is get_user, a Method
      await selectSymbol(1);

      expect(trackEventSpy).toHaveBeenCalledWith(
        'select_code_navigation_symbol',
        { label: 'Method' },
        undefined,
      );
    });

    it('tracks the Calls tab being viewed', async () => {
      await selectSymbol(1);

      await wrapper.find('[data-testid="calls-tab"]').trigger('click');

      expect(trackEventSpy).toHaveBeenCalledWith(
        'view_code_navigation_tab',
        { property: 'calls' },
        undefined,
      );
    });

    it('tracks the References tab being viewed', async () => {
      await selectSymbol(1);
      await wrapper.find('[data-testid="calls-tab"]').trigger('click');

      await wrapper.find('[data-testid="references-tab"]').trigger('click');

      expect(trackEventSpy).toHaveBeenCalledWith(
        'view_code_navigation_tab',
        { property: 'references' },
        undefined,
      );
    });

    // Selecting a symbol opens References without a click. That still counts as
    // a tab view, otherwise References undercounts against Calls in the funnel.
    it('tracks the default References tab when a symbol is selected', async () => {
      await selectSymbol(1);

      expect(trackEventSpy).toHaveBeenCalledWith(
        'view_code_navigation_tab',
        { property: 'references' },
        undefined,
      );
    });

    it('does not track a tab view when the active tab is selected again', async () => {
      await selectSymbol(1);
      trackEventSpy.mockClear();

      await wrapper.find('[data-testid="references-tab"]').trigger('click');

      expect(trackEventSpy).not.toHaveBeenCalled();
    });

    it('tracks Jump to definition being clicked', async () => {
      await selectSymbol(1);

      await wrapper.findComponent('[data-testid="jump-to-definition-button"]').vm.$emit('click');

      expect(trackEventSpy).toHaveBeenCalledWith(
        'click_jump_to_definition_in_code_navigation',
        {},
        undefined,
      );
    });
  });

  describe('blobUrl', () => {
    it('builds a URL with the line anchor matching the 1-indexed start_line from the API', async () => {
      setupFetchData();
      createWrapper();
      await waitForPromises();

      setupSelectDef();
      await wrapper.findAll('[data-testid="symbol-item"]').at(1).trigger('click');
      await waitForPromises();

      // get_user has start_line: '5' (1-indexed from KG), so the anchor should be L5
      const detail = wrapper.find('[data-testid="symbol-detail"]');
      const jumpBtn = detail.findAllComponents(GlButton).wrappers.find((b) => b.attributes('href'));
      expect(jumpBtn.attributes('href')).toContain('#L5');
      expect(jumpBtn.attributes('href')).toContain(
        `/${PROJECT_PATH}/-/blob/${CURRENT_REF}/${FILE_PATH}`,
      );
    });
  });
});
