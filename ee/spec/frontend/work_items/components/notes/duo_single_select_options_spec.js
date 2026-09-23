import { GlBadge, GlLoadingIcon } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DuoSingleSelectOptions from 'ee/work_items/components/notes/duo_single_select_options.vue';

const OPTIONS = [
  { id: 'hard_removal', label: 'Hard removal', description: 'One patch.', recommended: false },
  { id: 'staged', label: 'Staged deprecation', description: '', recommended: true },
];

const DISABLED_CLASSES = ['!gl-cursor-not-allowed', 'gl-bg-disabled', 'gl-text-disabled'];
const PRESSABLE_CLASSES = [
  'gl-bg-default',
  'gl-text-default',
  'hover:gl-bg-subtle',
  'focus:gl-bg-subtle',
  'dark:gl-bg-neutral-700',
  'dark:hover:gl-bg-neutral-600',
  'dark:focus:gl-bg-neutral-600',
];

describe('DuoSingleSelectOptions', () => {
  let wrapper;

  const createComponent = ({ options = OPTIONS, disabled = false, submittingId = null } = {}) => {
    wrapper = shallowMountExtended(DuoSingleSelectOptions, {
      propsData: { options, disabled, submittingId },
    });
  };

  const findOptions = () => wrapper.findAllByTestId('duo-question-option');
  const treatmentOf = (index, names) => {
    const classes = findOptions().at(index).classes();

    return names.filter((name) => classes.includes(name));
  };

  beforeEach(() => createComponent());

  it('renders one control per option, labelled', () => {
    expect(findOptions()).toHaveLength(2);
    expect(findOptions().at(0).text()).toContain('Hard removal');
    expect(findOptions().at(0).text()).toContain('One patch.');
    expect(findOptions().at(1).text()).toContain('Staged deprecation');
  });

  it('badges only the option the agent recommends', () => {
    expect(findOptions().at(0).findComponent(GlBadge).exists()).toBe(false);
    expect(findOptions().at(1).findComponent(GlBadge).text()).toBe('Recommended');
  });

  // Picking settles the question, so the row is a button rather than a div with a handler.
  it('reports the chosen option, so the note can post it', async () => {
    await findOptions().at(1).trigger('click');

    expect(wrapper.emitted('select')).toEqual([[OPTIONS[1]]]);
  });

  it('spins only on the option being posted, and stops every row from being pressed', () => {
    createComponent({ disabled: true, submittingId: 'staged' });

    expect(findOptions().at(0).findComponent(GlLoadingIcon).exists()).toBe(false);
    expect(findOptions().at(1).findComponent(GlLoadingIcon).exists()).toBe(true);
    expect(findOptions().at(0).attributes('disabled')).toBeDefined();
  });

  it.each`
    state          | disabled | expected             | unexpected
    ${'disabled'}  | ${true}  | ${DISABLED_CLASSES}  | ${PRESSABLE_CLASSES}
    ${'pressable'} | ${false} | ${PRESSABLE_CLASSES} | ${DISABLED_CLASSES}
  `(
    'gives a $state row the $state treatment and nothing from the other',
    ({ disabled, expected, unexpected }) => {
      createComponent({ disabled });

      expect(treatmentOf(0, expected)).toEqual(expected);
      expect(treatmentOf(0, unexpected)).toEqual([]);
    },
  );

  // The payload is model-authored, so nothing from it may reach the DOM as markup.
  it('renders a label and description as text, never as markup', () => {
    createComponent({
      options: [
        {
          id: 'a',
          label: '<img src=x onerror=alert(1)>',
          description: '<script>alert(2)</script>',
        },
      ],
    });
    const row = findOptions().at(0);

    expect(row.text()).toContain('<img src=x onerror=alert(1)>');
    expect(row.text()).toContain('<script>alert(2)</script>');
    expect(row.find('img').exists()).toBe(false);
    expect(row.find('script').exists()).toBe(false);
  });
});
