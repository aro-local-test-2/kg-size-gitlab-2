import { screen, within } from '@testing-library/dom';
import MockAdapter from 'axios-mock-adapter';
import initVulnerabilities from 'ee/vulnerabilities/vulnerabilities_init';
import { SEVERITY_LEVELS } from 'ee/security_dashboard/constants';
import { VULNERABILITY_STATES } from 'ee/vulnerabilities/constants';
import {
  hamlWithRelatedRecords,
  mockWithRelatedRecords,
} from 'ee_jest/vulnerabilities/components/vulnerability_details_enrichment/adapters/mock_data';
import { setHTMLFixture, resetHTMLFixture } from 'helpers/fixtures';
import { waitForText } from 'helpers/wait_for_text';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_OK } from '~/lib/utils/http_status';
import { unmountVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import { mockIssueLink } from './vulnerabilities_init_mock_data';

describe('Vulnerability details page', () => {
  let vm;
  let mockAxios;

  const createComponent = () => {
    const el = document.createElement('div');
    // The fixture is the real `vulnerability_details_app_data` payload, values already strings.
    Object.assign(el.dataset, mockWithRelatedRecords);
    document.querySelector('.vulnerability-details').appendChild(el);

    return initVulnerabilities(el);
  };

  beforeEach(() => {
    // `Api.buildUrl` reads `gon.api_version`, which the shared `createGon` helper omits.
    gon.api_version = 'v4';

    mockAxios = new MockAdapter(axios);
    mockAxios
      .onGet(`/api/v4/vulnerabilities/${hamlWithRelatedRecords.id}/issue_links`)
      .reply(HTTP_STATUS_OK, [mockIssueLink]);

    setHTMLFixture('<div class="vulnerability-details"></div>');
    vm = createComponent();
  });

  afterEach(() => {
    unmountVueApp(vm);
    mockAxios.restore();
    resetHTMLFixture();
  });

  it("displays a heading containing the vulnerability's title", () => {
    expect(screen.getByRole('heading', { name: hamlWithRelatedRecords.title })).toBeInstanceOf(
      HTMLElement,
    );
  });

  it("displays the vulnerability's status", () => {
    const section = screen.getByTestId('vulnerability-details-sidebar-status');
    const stateName = VULNERABILITY_STATES[hamlWithRelatedRecords.state];

    expect(within(section).getByText(stateName)).toBeInstanceOf(HTMLElement);
  });

  it("displays the vulnerability's severity", () => {
    const section = screen.getByTestId('vulnerability-details-sidebar-severity');
    const severityName = SEVERITY_LEVELS[hamlWithRelatedRecords.severity];

    expect(within(section).getByText(severityName)).toBeInstanceOf(HTMLElement);
  });

  it("displays the vulnerability's description", () => {
    const section = screen.getByTestId('details-description');
    const description = new DOMParser()
      .parseFromString(hamlWithRelatedRecords.description_html, 'text/html')
      .body.textContent.trim();

    expect(within(section).getByText(description)).toBeInstanceOf(HTMLElement);
  });

  it('displays related issues', async () => {
    expect(await waitForText(mockIssueLink.title)).toBeInstanceOf(HTMLElement);
  });
});
