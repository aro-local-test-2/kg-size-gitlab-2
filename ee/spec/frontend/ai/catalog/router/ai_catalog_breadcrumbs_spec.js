import { GlBreadcrumb } from '@gitlab/ui';
import { shallowMount } from '@vue/test-utils';
import AiCatalogBreadcrumbs from 'ee/ai/catalog/router/ai_catalog_breadcrumbs.vue';
import { breadcrumbState } from 'ee/ai/catalog/router/breadcrumb_state';
import {
  AI_CATALOG_INDEX_ROUTE,
  AI_CATALOG_AGENTS_ROUTE,
  AI_CATALOG_AGENTS_SHOW_ROUTE,
  AI_CATALOG_AGENTS_EDIT_ROUTE,
  AI_CATALOG_AGENTS_NEW_ROUTE,
  AI_CATALOG_FLOWS_ROUTE,
  AI_CATALOG_FOUNDATIONAL_AGENTS_SHOW_ROUTE,
} from 'ee/ai/catalog/router/constants';

describe('AiCatalogBreadcrumbs', () => {
  let wrapper;

  afterEach(() => {
    breadcrumbState.clearName();
  });

  const mockExploreBreadcrumb = {
    text: 'Explore',
    to: '/explore',
  };
  const defaultProps = {
    staticBreadcrumbs: [mockExploreBreadcrumb],
  };

  const createComponent = (routeOptions = { matched: [], params: {} }, { props, provide } = {}) => {
    wrapper = shallowMount(AiCatalogBreadcrumbs, {
      propsData: {
        ...defaultProps,
        ...props,
      },
      provide,
      mocks: {
        $route: {
          name: AI_CATALOG_INDEX_ROUTE,
          path: '/ai-catalog',
          ...routeOptions,
        },
      },
      stubs: {
        GlBreadcrumb,
      },
    });
  };

  const findBreadcrumb = () => wrapper.findComponent(GlBreadcrumb);
  const getBreadcrumbItems = () => findBreadcrumb().props('items');

  describe('template', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders breadcrumbs', () => {
      expect(findBreadcrumb().exists()).toBe(true);
      expect(findBreadcrumb().props('autoResize')).toBe(false);
    });
  });

  describe.each`
    routeName                       | expectedText    | matched                                                                                                        | params
    ${AI_CATALOG_INDEX_ROUTE}       | ${'AI Catalog'} | ${[]}                                                                                                          | ${{}}
    ${AI_CATALOG_AGENTS_ROUTE}      | ${'Agents'}     | ${[{ path: '/agents', meta: { text: 'Agents' } }]}                                                             | ${{}}
    ${AI_CATALOG_AGENTS_NEW_ROUTE}  | ${'New agent'}  | ${[{ path: '/agents', meta: { text: 'Agents' } }, { path: '/agents/new', meta: { text: 'New agent' } }]}       | ${{}}
    ${AI_CATALOG_AGENTS_EDIT_ROUTE} | ${'Edit agent'} | ${[{ path: '/agents', meta: { text: 'Agents' } }, { path: '/agents/:id/edit', meta: { text: 'Edit agent' } }]} | ${{ id: 4 }}
    ${AI_CATALOG_FLOWS_ROUTE}       | ${'Flows'}      | ${[{ path: '/flows', meta: { text: 'Flows' } }]}                                                               | ${{}}
  `('breadcrumbs on $routeName', ({ expectedText, matched, routeName, params }) => {
    beforeEach(() => {
      createComponent({
        name: routeName,
        matched,
        params,
      });
    });

    it('renders correct items', () => {
      const items = getBreadcrumbItems();
      // 1 static route + AI Catalog + dynamic routes
      const totalLength = 2 + matched.length;

      expect(items).toHaveLength(totalLength);
      expect(items[totalLength - 1].text).toBe(expectedText);
    });
  });

  describe('namespace breadcrumbs', () => {
    const groupCrumb = { text: 'Group', to: '/group' };
    const projectCrumb = { text: 'Project', to: '/group/project' };
    const props = {
      staticBreadcrumbs: [groupCrumb],
      allStaticBreadcrumbs: [groupCrumb, projectCrumb],
    };

    const getItemTexts = () => getBreadcrumbItems().map((item) => item.text);

    it('uses the sliced static breadcrumbs by default', () => {
      createComponent({ matched: [], params: {} }, { props });

      expect(getItemTexts()).toEqual(['Group', 'AI Catalog']);
    });

    it('uses the full static breadcrumbs when includeNamespaceBreadcrumbs is injected', () => {
      createComponent(
        { matched: [], params: {} },
        { props, provide: { includeNamespaceBreadcrumbs: true } },
      );

      expect(getItemTexts()).toEqual(['Group', 'Project', 'AI Catalog']);
    });
  });

  describe('AI Catalog root crumb', () => {
    const getRootCrumb = () => getBreadcrumbItems().find((item) => item.text === 'AI Catalog');

    it('links to the AI Catalog index route by default', () => {
      createComponent();

      expect(getRootCrumb().to).toEqual({ name: AI_CATALOG_INDEX_ROUTE });
    });

    it('is rendered by default', () => {
      createComponent({ matched: [{ path: '/agents', meta: { text: 'Agents' } }], params: {} });

      expect(getBreadcrumbItems().map((item) => item.text)).toEqual([
        'Explore',
        'AI Catalog',
        'Agents',
      ]);
    });

    it('is omitted when showCatalogRootCrumb is injected as false', () => {
      createComponent(
        { matched: [{ path: '/agents', meta: { text: 'Agents' } }], params: {} },
        { provide: { showCatalogRootCrumb: false } },
      );

      expect(getBreadcrumbItems().map((item) => item.text)).toEqual(['Explore', 'Agents']);
    });
  });

  describe('item name breadcrumb', () => {
    describe('on a foundational agent route', () => {
      const foundationalAgentRoute = {
        name: AI_CATALOG_FOUNDATIONAL_AGENTS_SHOW_ROUTE,
        matched: [
          {
            path: '/foundational_agents/:reference',
            meta: { useId: true, indexRoute: AI_CATALOG_FOUNDATIONAL_AGENTS_SHOW_ROUTE },
          },
        ],
        params: { reference: 'support_assistant' },
      };

      it('omits the item crumb when no item name is set', () => {
        createComponent(foundationalAgentRoute);

        expect(getBreadcrumbItems().at(-1).text).toBe('AI Catalog');
      });

      it('shows the item name when set for the current reference', () => {
        breadcrumbState.setName('support_assistant', 'Support Assistant');
        createComponent(foundationalAgentRoute);

        expect(getBreadcrumbItems().at(-1).text).toBe('Support Assistant');
      });

      it('omits the item crumb when the item name belongs to another reference', () => {
        breadcrumbState.setName('security_analyst_agent', 'Security Analyst');
        createComponent(foundationalAgentRoute);

        expect(getBreadcrumbItems().at(-1).text).toBe('AI Catalog');
      });
    });

    describe('on a custom item route', () => {
      const customAgentRoute = {
        name: AI_CATALOG_AGENTS_SHOW_ROUTE,
        matched: [
          { path: '/agents/:id', meta: { useId: true, indexRoute: AI_CATALOG_AGENTS_SHOW_ROUTE } },
        ],
        params: { id: '4' },
      };

      it('shows the item name when set for the current id', () => {
        breadcrumbState.setName('4', 'My Agent');
        createComponent(customAgentRoute);

        expect(getBreadcrumbItems().at(-1).text).toBe('My Agent');
      });

      it('truncates a long item name', () => {
        breadcrumbState.setName('4', 'a'.repeat(80));
        createComponent(customAgentRoute);

        expect(getBreadcrumbItems().at(-1).text).toBe(`${'a'.repeat(24)}…`);
      });

      it('omits the item crumb when no item name is set', () => {
        createComponent(customAgentRoute);

        expect(getBreadcrumbItems().at(-1).text).toBe('AI Catalog');
      });

      it('omits the item crumb when the item name belongs to another item', () => {
        breadcrumbState.setName('7', 'Another Agent');
        createComponent(customAgentRoute);

        expect(getBreadcrumbItems().at(-1).text).toBe('AI Catalog');
      });

      it('never renders the route id, so no id flashes before the name loads', () => {
        createComponent(customAgentRoute);

        expect(getBreadcrumbItems().map((item) => item.text)).not.toContain('4');
      });

      it('keeps the nested crumb but omits the item until its name loads', () => {
        createComponent({
          name: AI_CATALOG_AGENTS_EDIT_ROUTE,
          matched: [
            { path: '/agents/:id', meta: { useId: true } },
            { path: '/agents/:id/edit', meta: { text: 'Edit agent' } },
          ],
          params: { id: '4' },
        });

        expect(getBreadcrumbItems().map((item) => item.text)).toEqual([
          'Explore',
          'AI Catalog',
          'Edit agent',
        ]);
      });

      it('shows the item name on nested routes such as edit', () => {
        breadcrumbState.setName('4', 'My Agent');
        createComponent({
          name: AI_CATALOG_AGENTS_EDIT_ROUTE,
          matched: [
            { path: '/agents/:id', meta: { useId: true } },
            { path: '/agents/:id/edit', meta: { text: 'Edit agent' } },
          ],
          params: { id: '4' },
        });

        expect(getBreadcrumbItems().map((item) => item.text)).toEqual([
          'Explore',
          'AI Catalog',
          'My Agent',
          'Edit agent',
        ]);
      });
    });
  });
});
