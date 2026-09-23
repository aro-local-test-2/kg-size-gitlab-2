import { shallowMount } from '@vue/test-utils';
import { GlIcon } from '@gitlab/ui';
import SummarySection from 'ee/policy_store/components/detail/summary_section.vue';

describe('PolicySummarySection', () => {
  let wrapper;

  const entries = [
    { id: 'block', label: 'Block', description: 'Stops the pipeline', icon: 'cancel' },
    { id: 'warn', label: 'Warn', description: '', icon: 'warning' },
  ];

  const createComponent = (props = {}, options = {}) => {
    wrapper = shallowMount(SummarySection, {
      propsData: {
        label: 'Actions',
        entries,
        testid: 'actions',
        ...props,
      },
      ...options,
    });
  };

  const findByTestId = (id) => wrapper.find(`[data-testid="${id}"]`);
  const findEntries = () => wrapper.findAll('[data-testid="actions-entry"]');

  it('renders the section heading and testid', () => {
    createComponent();

    expect(findByTestId('actions-section').find('h2').text()).toBe('Actions');
  });

  it('renders each entry with its label, description, and icon', () => {
    createComponent();

    const first = findEntries().at(0);
    expect(first.text()).toContain('Block');
    expect(first.text()).toContain('Stops the pipeline');
    expect(first.findComponent(GlIcon).props('name')).toBe('cancel');
  });

  it('omits the description element for an entry without one', () => {
    createComponent();

    expect(findEntries().at(1).text()).toBe('Warn');
  });

  describe('configured values', () => {
    const configuredEntries = [
      {
        id: 'calendar',
        label: 'Freeze Window',
        description: '',
        icon: 'clock',
        configItems: [
          { key: 'windowStart', label: 'Window start', code: false, value: '2026-12-20T00:00:00Z' },
          { key: 'policy', label: 'Rego policy definition', code: true, value: 'input.ok == true' },
        ],
      },
    ];

    it('renders each configured value with its field label', () => {
      createComponent({ entries: configuredEntries });

      const config = findByTestId('actions-entry-config');
      expect(config.text()).toContain('Window start');
      expect(config.text()).toContain('2026-12-20T00:00:00Z');
    });

    it('renders code values inside a code block', () => {
      createComponent({ entries: configuredEntries });

      expect(findByTestId('actions-entry-config').find('pre code').text()).toBe('input.ok == true');
    });

    it('renders no config list for an entry without configured values', () => {
      createComponent();

      expect(findByTestId('actions-entry-config').exists()).toBe(false);
    });
  });

  it('shows a placeholder instead of entries when there are none', () => {
    createComponent({ entries: [] });

    expect(wrapper.text()).toContain('None added');
    expect(findEntries()).toHaveLength(0);
  });

  it('renders slot content inside the card instead of the entry list', () => {
    createComponent(
      { entries: [] },
      { slots: { default: '<p data-testid="custom-content">All projects</p>' } },
    );

    expect(findByTestId('custom-content').text()).toBe('All projects');
    expect(wrapper.text()).not.toContain('None added');
  });
});
