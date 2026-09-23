import Vue from 'vue';
import VueApollo from 'vue-apollo';
import VueRouter from 'vue-router';
import { shallowMount } from '@vue/test-utils';
import { GlBreadcrumb } from '@gitlab/ui';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import CdBreadcrumbs from 'ee/cd/components/cd_breadcrumbs.vue';
import { routes } from 'ee/cd/router';
import cdApplicationNameQuery from 'ee/cd/graphql/applications/cd_application_name.query.graphql';
import cdEnvironmentNameQuery from 'ee/cd/graphql/environments/cd_environment_name.query.graphql';
import { buildApplicationNameResponse, buildEnvironmentNameResponse } from './mock_data';

Vue.use(VueApollo);
Vue.use(VueRouter);

const STATIC_CRUMBS = [{ text: 'GitLab', href: '/' }];
const APPLICATIONS_CRUMB = { text: 'Applications', to: { path: '/applications' } };
const ENVIRONMENTS_CRUMB = { text: 'Environments', to: { path: '/environments' } };
const MY_APP_CRUMB = { text: 'My App', to: { name: 'applications_show_route' } };
const FLOW_EDITOR_CRUMB = { text: 'Flow editor', to: { name: 'flow_editor_route' } };
const STAGING_CRUMB = { text: 'Staging', to: { name: 'environments_show_route' } };

describe('CdBreadcrumbs', () => {
  let wrapper;
  let router;

  const findBreadcrumb = () => wrapper.findComponent(GlBreadcrumb);
  const crumbTexts = () =>
    findBreadcrumb()
      .props('items')
      .map((item) => item.text);

  const createComponent = async ({ path = '/applications/1', handlers = {} } = {}) => {
    const queries = {
      application:
        handlers.application ?? jest.fn().mockResolvedValue(buildApplicationNameResponse()),
      environment:
        handlers.environment ?? jest.fn().mockResolvedValue(buildEnvironmentNameResponse()),
    };

    const apolloProvider = createMockApollo([
      [cdApplicationNameQuery, queries.application],
      [cdEnvironmentNameQuery, queries.environment],
    ]);
    router = new VueRouter({ routes });
    await router.push(path);

    wrapper = shallowMount(CdBreadcrumbs, {
      apolloProvider,
      router,
      propsData: { allStaticBreadcrumbs: STATIC_CRUMBS },
    });

    return queries;
  };

  it.each([
    { scenario: 'an index route', path: '/applications', crumbs: [APPLICATIONS_CRUMB] },
    {
      scenario: 'an application',
      path: '/applications/1',
      crumbs: [APPLICATIONS_CRUMB, MY_APP_CRUMB],
    },
    {
      scenario: 'a nested route',
      path: '/applications/1/flow',
      crumbs: [APPLICATIONS_CRUMB, MY_APP_CRUMB, FLOW_EDITOR_CRUMB],
    },
    {
      scenario: 'an environment',
      path: '/environments/1',
      crumbs: [ENVIRONMENTS_CRUMB, STAGING_CRUMB],
    },
  ])('renders the crumbs for $scenario', async ({ path, crumbs }) => {
    await createComponent({ path });
    await waitForPromises();

    expect(findBreadcrumb().props('items')).toEqual([...STATIC_CRUMBS, ...crumbs]);
  });

  it.each`
    resource         | otherResource    | path                 | gid
    ${'application'} | ${'environment'} | ${'/applications/1'} | ${'gid://gitlab/Cd::Application/1'}
    ${'environment'} | ${'application'} | ${'/environments/1'} | ${'gid://gitlab/Cd::Environment/1'}
  `(
    'queries the $resource and not the $otherResource',
    async ({ resource, otherResource, path, gid }) => {
      const queries = await createComponent({ path });
      await waitForPromises();

      expect(queries[resource]).toHaveBeenCalledWith({ id: gid });
      expect(queries[otherResource]).not.toHaveBeenCalled();
    },
  );

  it('does not query on a route without an id', async () => {
    const queries = await createComponent({ path: '/applications' });
    await waitForPromises();

    expect(queries.application).not.toHaveBeenCalled();
    expect(queries.environment).not.toHaveBeenCalled();
  });

  it.each([
    { scenario: 'is still loading', application: jest.fn().mockReturnValue(new Promise(() => {})) },
    {
      scenario: 'returns no name',
      application: jest.fn().mockResolvedValue(buildApplicationNameResponse(null)),
    },
    { scenario: 'fails', application: jest.fn().mockRejectedValue(new Error('boom')) },
  ])('falls back to the id when the query $scenario', async ({ application }) => {
    await createComponent({ handlers: { application } });
    await waitForPromises();

    expect(crumbTexts()).toEqual(['GitLab', 'Applications', '1']);
  });

  describe('when navigating to an application whose name fails to load', () => {
    beforeEach(async () => {
      const application = jest
        .fn()
        .mockResolvedValueOnce(buildApplicationNameResponse())
        .mockRejectedValueOnce(new Error('boom'));

      await createComponent({ handlers: { application } });
      await waitForPromises();

      await router.push('/applications/2');
      await waitForPromises();
    });

    it('does not keep the previous name', () => {
      expect(crumbTexts()).toEqual(['GitLab', 'Applications', '2']);
    });
  });
});
