import { readFileSync } from 'fs';
import { join } from 'path';
import { load } from 'js-yaml';
import { configToPreviewPieces } from '~/vue_shared/components/dashboards_list/dashboard_preview_layout';

// Loads the shipped system dashboard YAMLs so these specs fail when the real
// configs drift from the preview compositions asserted below.
const SYSTEM_DASHBOARDS_DIR = join(
  __dirname,
  '../../../../../lib/gitlab/analytics/dashboards/system',
);

const loadSystemDashboardConfig = (slug) =>
  load(readFileSync(join(SYSTEM_DASHBOARDS_DIR, `${slug}.yaml`), 'utf8'));

describe('configToPreviewPieces with the shipped system dashboard configs', () => {
  it('previews GitLab Duo and SDLC trends as three stats with its first chart pulled into frame', () => {
    expect(configToPreviewPieces(loadSystemDashboardConfig('duo_and_sdlc_trends'))).toEqual([
      { type: 'stat', wide: false },
      { type: 'stat', wide: false },
      { type: 'stat', wide: false },
      { type: 'line-chart', wide: false },
    ]);
  });

  it('previews DAP Impact through the views fallback as three stats then wide bars', () => {
    expect(configToPreviewPieces(loadSystemDashboardConfig('dap_impact'))).toEqual([
      { type: 'stat', wide: false },
      { type: 'stat', wide: false },
      { type: 'stat', wide: false },
      { type: 'bar-rows', wide: true },
    ]);
  });
});
