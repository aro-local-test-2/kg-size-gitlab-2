import { GlEmptyState, GlLoadingIcon } from '@gitlab/ui';
import { MountingPortal } from 'portal-vue';
import Vue from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { stubComponent } from 'helpers/stub_component';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import ServiceSidePanel from 'ee/cd/components/application_details/services/service_side_panel.vue';
import cdServiceQuery from 'ee/cd/graphql/applications/services/cd_service.query.graphql';
import ArtifactSourceCard from 'ee/cd/components/application_details/services/artifact_source_card.vue';
import DynamicPanel from '~/vue_shared/components/dynamic_panel.vue';
import TimeAgo from '~/vue_shared/components/time_ago_tooltip.vue';
import { makeService } from 'ee/cd/../../../../spec/frontend/cd/components/mock_data';

Vue.use(VueApollo);

const defaultServiceId = String(getIdFromGraphQLId(makeService().id));

const buildResponse = (service) => ({
  data: { organization: { id: 'gid://gitlab/Organization/1', cdService: service } },
});

describe('ServiceSidePanel', () => {
  let wrapper;
  let queryHandler;

  const findPortal = () => wrapper.findComponent(MountingPortal);
  const findPanel = () => wrapper.findComponent(DynamicPanel);
  const findEmptyState = () => wrapper.findComponent(GlEmptyState);
  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);
  const findDetailTitle = () => wrapper.findByTestId('detail-title');
  const findDetailMode = () => wrapper.findByTestId('detail-mode');
  const findSourceRef = () => wrapper.findByTestId('source-ref');
  const findLastDeployed = () => wrapper.findComponent(TimeAgo);
  const findArtifactSourceCards = () => wrapper.findAllComponents(ArtifactSourceCard);
  const findArtifactSourcesEmpty = () => wrapper.findByTestId('artifact-sources-empty');

  const createComponent = ({
    serviceId = defaultServiceId,
    service = makeService(),
    handler,
  } = {}) => {
    queryHandler = handler ?? jest.fn().mockResolvedValue(buildResponse(service));
    wrapper = shallowMountExtended(ServiceSidePanel, {
      apolloProvider: createMockApollo([[cdServiceQuery, queryHandler]]),
      propsData: { serviceId },
      stubs: {
        DynamicPanel,
        MountingPortal: stubComponent(MountingPortal, { name: 'MountingPortal' }),
      },
    });
  };

  describe('when the service resolves', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('runs the query for the resolved service', () => {
      expect(queryHandler).toHaveBeenCalledTimes(1);
    });

    it('renders MountingPortal targeting #contextual-panel-portal', () => {
      expect(findPortal().attributes('mount-to')).toBe('#contextual-panel-portal');
    });

    it('renders the DynamicPanel', () => {
      expect(findPanel().exists()).toBe(true);
    });

    it('renders the service name in the header', () => {
      expect(findDetailTitle().text()).toBe('api-server');
    });

    it('renders the detail body', () => {
      expect(findDetailMode().exists()).toBe(true);
    });

    it('does not render the empty state', () => {
      expect(findEmptyState().exists()).toBe(false);
    });

    it('does not render the loading icon', () => {
      expect(findLoadingIcon().exists()).toBe(false);
    });

    it('emits "close" when the panel emits close', () => {
      findPanel().vm.$emit('close');

      expect(wrapper.emitted('close')).toHaveLength(1);
    });

    it('renders the source ref', () => {
      expect(findSourceRef().text()).toBe('registry.example.com/api-server');
    });

    it('renders the last deployed time', () => {
      expect(findLastDeployed().props('time')).toBe('2024-06-10T08:00:00Z');
    });

    it('renders ArtifactSourceCard components', () => {
      expect(findArtifactSourceCards()).toHaveLength(1);
    });

    it('passes artifact source data to ArtifactSourceCard', () => {
      expect(findArtifactSourceCards().at(0).props('artifactSource')).toMatchObject({
        id: 'source-1',
      });
    });

    it('does not render the empty artifact sources message', () => {
      expect(findArtifactSourcesEmpty().exists()).toBe(false);
    });
  });

  describe('when the service has never been deployed', () => {
    beforeEach(async () => {
      createComponent({ service: makeService({ lastDeployedAt: null }) });
      await waitForPromises();
    });

    it('does not render the last deployed row', () => {
      expect(findLastDeployed().exists()).toBe(false);
    });
  });

  describe('with no artifact sources', () => {
    beforeEach(async () => {
      createComponent({
        service: makeService({ artifactSources: { nodes: [] } }),
      });
      await waitForPromises();
    });

    it('does not render the source row', () => {
      expect(findSourceRef().exists()).toBe(false);
    });

    it('renders the empty artifact sources message', () => {
      expect(findArtifactSourcesEmpty().text()).toBe('No artifact sources configured.');
    });

    it('does not render ArtifactSourceCard components', () => {
      expect(findArtifactSourceCards()).toHaveLength(0);
    });
  });

  describe('while loading', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders a loading icon', () => {
      expect(findLoadingIcon().exists()).toBe(true);
    });

    it('does not render the detail body', () => {
      expect(findDetailMode().exists()).toBe(false);
    });

    it('does not render the not-found empty state', () => {
      expect(findEmptyState().exists()).toBe(false);
    });
  });

  describe('when the query errors', () => {
    beforeEach(async () => {
      jest.spyOn(Sentry, 'captureException').mockImplementation();
      createComponent({ handler: jest.fn().mockRejectedValue(new Error('boom')) });
      await waitForPromises();
    });

    it('captures the exception in Sentry', () => {
      expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error));
    });

    it('renders the not-found empty state', () => {
      expect(findEmptyState().exists()).toBe(true);
    });
  });

  describe('when the service is not found', () => {
    beforeEach(async () => {
      createComponent({ service: null });
      await waitForPromises();
    });

    it('renders the empty state', () => {
      expect(findEmptyState().exists()).toBe(true);
    });

    it('does not render the detail body', () => {
      expect(findDetailMode().exists()).toBe(false);
    });

    it('does not render the detail title', () => {
      expect(findDetailTitle().exists()).toBe(false);
    });
  });

  describe('when serviceId is null', () => {
    beforeEach(async () => {
      createComponent({ serviceId: null });
      await waitForPromises();
    });

    it('skips the query', () => {
      expect(queryHandler).not.toHaveBeenCalled();
    });

    it('renders the empty state', () => {
      expect(findEmptyState().exists()).toBe(true);
    });

    it('does not render the detail body', () => {
      expect(findDetailMode().exists()).toBe(false);
    });
  });
});
