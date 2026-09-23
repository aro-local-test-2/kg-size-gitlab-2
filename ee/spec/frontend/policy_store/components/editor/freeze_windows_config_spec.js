import { GlFormGroup } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import FieldWrapper from 'ee/policy_store/components/editor/fields/field_wrapper.vue';
import FreezeWindowsConfig from 'ee/policy_store/components/editor/freeze_windows_config.vue';
import MultiBadgeSelector from 'ee/policy_store/components/editor/fields/multi_badge_selector.vue';

describe('FreezeWindowsConfig', () => {
  let wrapper;

  const tierOptions = [
    { id: 'production', label: 'Production' },
    { id: 'staging', label: 'Staging' },
  ];

  const buildWindow = (overrides = {}) => ({
    name: 'eoq-freeze',
    tiers: ['production'],
    starts_at: '2026-12-24T00:00:00Z',
    ends_at: '2027-01-02T00:00:00Z',
    ...overrides,
  });

  // The renderer passes every field control `{ field, value }`; the tier options
  // ride along on the field, so they are declared by the catalog rather than here.
  const createComponent = ({ freezeWindows = [], field = {} } = {}) => {
    wrapper = shallowMountExtended(FreezeWindowsConfig, {
      propsData: {
        field: { key: 'windows', label: 'Freeze windows', options: tierOptions, ...field },
        value: freezeWindows,
      },
      // Rendered for real so the rows inside its default slot exist.
      stubs: { FieldWrapper },
    });
  };

  const findWindows = () => wrapper.findAllByTestId('freeze-window');
  const findAddButton = () => wrapper.findComponentByTestId('add-window');

  it('renders no window rows until one is added', () => {
    createComponent();

    expect(findWindows()).toHaveLength(0);
  });

  it('emits a single blank window when Add window is clicked with none yet', () => {
    createComponent();

    findAddButton().vm.$emit('click');

    expect(wrapper.emitted('input')).toEqual([
      [[{ name: '', tiers: [], starts_at: '', ends_at: '' }]],
    ]);
  });

  it('appends a blank window after the existing ones', () => {
    createComponent({ freezeWindows: [buildWindow()] });

    findAddButton().vm.$emit('click');

    expect(wrapper.emitted('input')).toEqual([
      [[buildWindow(), { name: '', tiers: [], starts_at: '', ends_at: '' }]],
    ]);
  });

  it('renders one row per window with its fields filled', () => {
    createComponent({ freezeWindows: [buildWindow(), buildWindow({ name: 'summit' })] });

    expect(findWindows()).toHaveLength(2);
    expect(findWindows().at(0).findComponent('[data-testid="window-name"]').props('value')).toBe(
      'eoq-freeze',
    );
    expect(
      findWindows().at(0).findComponent('[data-testid="window-starts-at"]').props('value'),
    ).toBe('2026-12-24T00:00:00Z');
    expect(findWindows().at(0).findComponent(MultiBadgeSelector).props()).toMatchObject({
      field: expect.objectContaining({ options: tierOptions }),
      value: ['production'],
    });
  });

  it('emits the edited window without touching its siblings', () => {
    createComponent({ freezeWindows: [buildWindow(), buildWindow({ name: 'summit' })] });

    findWindows().at(1).findComponent('[data-testid="window-name"]').vm.$emit('input', 'offsite');

    expect(wrapper.emitted('input')).toEqual([[[buildWindow(), buildWindow({ name: 'offsite' })]]]);
  });

  it.each`
    testid                | key
    ${'window-starts-at'} | ${'starts_at'}
    ${'window-ends-at'}   | ${'ends_at'}
  `('emits an edited $key bound under its own key', ({ testid, key }) => {
    createComponent({ freezeWindows: [buildWindow()] });

    findWindows()
      .at(0)
      .findComponent(`[data-testid="${testid}"]`)
      .vm.$emit('input', '2026-06-01T00:00:00Z');

    expect(wrapper.emitted('input')).toEqual([[[buildWindow({ [key]: '2026-06-01T00:00:00Z' })]]]);
  });

  it('emits the edited tiers through the badge selector', () => {
    createComponent({ freezeWindows: [buildWindow()] });

    findWindows().at(0).findComponent(MultiBadgeSelector).vm.$emit('input', ['staging']);

    expect(wrapper.emitted('input')).toEqual([[[buildWindow({ tiers: ['staging'] })]]]);
  });

  it('removes only the window whose remove button was clicked', () => {
    createComponent({ freezeWindows: [buildWindow(), buildWindow({ name: 'summit' })] });

    findWindows().at(0).findComponent('[data-testid="remove-window"]').vm.$emit('click');

    expect(wrapper.emitted('input')).toEqual([[[buildWindow({ name: 'summit' })]]]);
  });

  it('names each remove button after its window for assistive tech', () => {
    createComponent({ freezeWindows: [buildWindow(), buildWindow({ name: '' })] });

    const labels = findWindows().wrappers.map((row) =>
      row.findComponent('[data-testid="remove-window"]').attributes('aria-label'),
    );

    expect(labels).toEqual(['Remove window eoq-freeze', 'Remove window 2']);
  });

  // sprintf must not escape the name, or the entity is announced verbatim.
  it('does not HTML-escape a window name in the remove button label', () => {
    createComponent({ freezeWindows: [buildWindow({ name: 'Q&A freeze' })] });

    expect(
      findWindows().at(0).findComponent('[data-testid="remove-window"]').attributes('aria-label'),
    ).toBe('Remove window Q&A freeze');
  });

  it('labels the fields in order so the start and end cannot be swapped', () => {
    createComponent({ freezeWindows: [buildWindow()] });

    const row = findWindows().at(0);

    expect(
      row.findAllComponents(GlFormGroup).wrappers.map((group) => group.attributes('label')),
    ).toEqual(['Window name', 'Environment tiers', 'Starts at', 'Ends at']);
    expect(row.findComponent('[data-testid="window-starts-at"]').attributes('placeholder')).toBe(
      '2026-12-24T00:00:00Z',
    );
    expect(row.findComponent('[data-testid="window-ends-at"]').attributes('placeholder')).toBe(
      '2027-01-02T00:00:00Z',
    );
  });
});
