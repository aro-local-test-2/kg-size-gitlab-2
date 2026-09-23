import initAiOverviewApp from 'ee/merge_requests/ai_overview';
import { AI_OVERVIEW_EL_ID } from '~/merge_requests/constants';

// The real client would fire the overview query over the network.
jest.mock(
  '~/lib/graphql',
  () => () => jest.requireActual('helpers/mock_apollo_helper').default().defaultClient,
);

describe('initAiOverviewApp', () => {
  let el;
  let app;

  beforeEach(() => {
    el = document.createElement('div');
    el.id = AI_OVERVIEW_EL_ID;
    el.dataset.projectPath = 'group/project';
    el.dataset.iid = '1';
    document.body.appendChild(el);
  });

  afterEach(() => {
    app?.$destroy();
    el.remove();
  });

  it('renders the app inside the given element', () => {
    app = initAiOverviewApp(el);

    expect(el.childElementCount).toBe(1);
  });

  it('leaves the mount point in the DOM, because other page bundles key off it', () => {
    app = initAiOverviewApp(el);

    expect(document.getElementById(AI_OVERVIEW_EL_ID)).toBe(el);
  });

  it('does not mount a second app when the element is already filled', () => {
    app = initAiOverviewApp(el);

    expect(initAiOverviewApp(el)).toBe(null);
    expect(el.childElementCount).toBe(1);
  });
});
