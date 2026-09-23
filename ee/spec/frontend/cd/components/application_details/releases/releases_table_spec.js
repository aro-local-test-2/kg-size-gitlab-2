import { GlBadge, GlTableLite } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import ReleasesTable from 'ee/cd/components/application_details/releases/releases_table.vue';
import TimeAgo from '~/vue_shared/components/time_ago_tooltip.vue';

describe('ReleasesTable', () => {
  let wrapper;

  const releases = [
    {
      id: 'gid://gitlab/Cd::VersionSet/1',
      name: 'v1_1_0',
      createdAt: '2024-06-01T00:00:00Z',
      rollouts: {
        nodes: [{ id: 'gid://gitlab/Cd::Rollout/1', iid: 1, state: 'IN_PROGRESS' }],
      },
      versionSetEntries: {
        count: 2,
        nodes: [
          { service: { id: 'gid://gitlab/Cd::Service/10' } },
          { service: { id: 'gid://gitlab/Cd::Service/10' } },
          { service: { id: 'gid://gitlab/Cd::Service/20' } },
        ],
      },
    },
    {
      id: 'gid://gitlab/Cd::VersionSet/2',
      name: 'v1_0_0',
      createdAt: '2024-05-01T00:00:00Z',
      rollouts: { nodes: [{ id: 'gid://gitlab/Cd::Rollout/2', iid: 2, state: 'COMPLETED' }] },
      versionSetEntries: {
        count: 1,
        nodes: [{ service: { id: 'gid://gitlab/Cd::Service/10' } }],
      },
    },
  ];

  const findTable = () => wrapper.findComponent(GlTableLite);
  const findRows = () => wrapper.findAll('tbody tr');
  const findHeaders = () => wrapper.findAll('thead th');
  const findRowCells = (rowIndex) => findRows().at(rowIndex).findAll('td');

  const createComponent = (props = {}) => {
    wrapper = mountExtended(ReleasesTable, {
      propsData: { releases, ...props },
    });
  };

  describe('collapsed (default)', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the version and status columns', () => {
      expect(findHeaders().wrappers.map((h) => h.text())).toEqual(['Version', 'Status']);
    });

    it('renders a row per release showing its version name', () => {
      expect(findRows()).toHaveLength(releases.length);
      expect(findRows().at(0).text()).toContain('v1_1_0');
      expect(findRows().at(1).text()).toContain('v1_0_0');
    });

    describe('when the row is clicked', () => {
      beforeEach(() => {
        findTable().vm.$emit('row-clicked', releases[0]);
      });

      it('emits select event with the release data', () => {
        expect(wrapper.emitted('select')).toEqual([[releases[0]]]);
      });
    });
  });

  describe('expanded (full)', () => {
    beforeEach(() => {
      createComponent({ full: true });
    });

    it('renders the columns in order: version, deployment id, services, created, status', () => {
      expect(findHeaders().wrappers.map((h) => h.text())).toEqual([
        'Version',
        'Deployment ID',
        'Services',
        'Created',
        'Status',
      ]);
    });

    it('shows the count of services in the release', () => {
      expect(findRowCells(0).at(2).text()).toBe('2');
      expect(findRowCells(1).at(2).text()).toBe('1');
    });

    it('shows the created date via TimeAgo', () => {
      expect(wrapper.findComponent(TimeAgo).props('time')).toBe('2024-06-01T00:00:00Z');
    });
  });

  describe('when a release has multiple rollouts', () => {
    beforeEach(() => {
      createComponent({
        full: true,
        releases: [
          {
            id: 'gid://gitlab/Cd::VersionSet/3',
            name: 'v',
            rollouts: {
              nodes: [
                { id: 'gid://gitlab/Cd::Rollout/2', iid: 4, state: 'COMPLETED' },
                { id: 'gid://gitlab/Cd::Rollout/1', iid: 3, state: 'COMPLETED' },
              ],
            },
            versionSetEntries: { count: 0 },
          },
        ],
      });
    });

    it('joins every rollout id in the deployment column', () => {
      expect(findRowCells(0).at(1).text()).toBe('#4, #3');
    });

    it('shows the status from the latest rollout only', () => {
      expect(findRowCells(0).at(4).text()).toBe('Available');
    });
  });

  describe('status column', () => {
    const createWithRelease = (release) =>
      createComponent({
        releases: [{ id: 'gid://gitlab/Cd::VersionSet/9', name: 'v', ...release }],
      });

    const findStatusBadge = () => findRowCells(0).at(1).findComponent(GlBadge);

    describe.each([
      ['DEPLOYING', 'Deploying', 'info'],
      ['SUPERSEDED', 'Superseded', 'neutral'],
      ['ROLLED_BACK', 'Rolled back', 'neutral'],
    ])('when the status is %s', (status, label, variant) => {
      beforeEach(() => {
        createWithRelease({ status, rollouts: { nodes: [{ state: 'IN_PROGRESS' }] } });
      });

      it('renders the status label', () => {
        expect(findRowCells(0).at(1).text()).toBe(label);
      });

      it('renders the status variant', () => {
        expect(findStatusBadge().props('variant')).toBe(variant);
      });
    });

    describe('when the status is null and the latest rollout completed', () => {
      beforeEach(() => {
        createWithRelease({ status: null, rollouts: { nodes: [{ state: 'COMPLETED' }] } });
      });

      it('renders Available', () => {
        expect(findRowCells(0).at(1).text()).toBe('Available');
      });

      it('renders the success variant', () => {
        expect(findStatusBadge().props('variant')).toBe('success');
      });
    });

    describe.each(['FAILED', 'CANCELLED'])(
      'when the status is null and the latest rollout is %s',
      (state) => {
        beforeEach(() => {
          createWithRelease({ status: null, rollouts: { nodes: [{ state }] } });
        });

        it('renders no badge', () => {
          expect(findStatusBadge().exists()).toBe(false);
        });

        it('renders the empty placeholder', () => {
          expect(findRowCells(0).at(1).text()).toBe('—');
        });
      },
    );

    describe('when the release has no rollouts', () => {
      beforeEach(() => {
        createWithRelease({ status: null, rollouts: { nodes: [] } });
      });

      it('renders Pending', () => {
        expect(findRowCells(0).at(1).text()).toBe('Pending');
      });

      it('renders the warning variant', () => {
        expect(findStatusBadge().props('variant')).toBe('warning');
      });
    });
  });

  describe('with a recent release', () => {
    beforeEach(() => {
      createComponent({ recentId: 'gid://gitlab/Cd::VersionSet/1' });
    });

    it('highlights the recent release row only', () => {
      expect(findRows().at(0).classes()).toContain('gl-bg-purple-50');
      expect(findRows().at(1).classes()).not.toContain('gl-bg-purple-50');
    });
  });

  describe('with a selected release', () => {
    beforeEach(() => {
      createComponent({ selectedId: 'gid://gitlab/Cd::VersionSet/1' });
    });

    it('highlights the selected release row only', () => {
      expect(findRows().at(0).classes()).toContain('gl-bg-blue-50');
      expect(findRows().at(1).classes()).not.toContain('gl-bg-blue-50');
    });
  });

  describe('with no releases', () => {
    beforeEach(() => {
      createComponent({ releases: [] });
    });

    it('renders no rows', () => {
      expect(findTable().exists()).toBe(true);
      expect(findRows()).toHaveLength(0);
    });
  });
});
