import { GlBadge } from '@gitlab/ui';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import MultipleChoiceSelector from '~/vue_shared/components/multiple_choice_selector.vue';
import MultipleChoiceSelectorItem from '~/vue_shared/components/multiple_choice_selector_item.vue';
import DuoMultiSelectOptions from 'ee/work_items/components/notes/duo_multi_select_options.vue';

const OPTIONS = [
  { id: 'sp_sso', label: 'SP-initiated SSO', description: 'Starts at GitLab.', recommended: true },
  { id: 'jit', label: 'Just-in-time provisioning', description: '', recommended: true },
  { id: 'idp_sso', label: 'IdP-initiated SSO', description: '', recommended: false },
];

const DISABLED_CLASSES = ['gl-cursor-not-allowed'];
const TICKABLE_CLASSES = [
  'gl-cursor-pointer',
  'gl-bg-default',
  'hover:gl-bg-subtle',
  'focus-within:gl-bg-subtle',
  'dark:gl-bg-neutral-700',
  'dark:hover:gl-bg-neutral-600',
  'dark:focus-within:gl-bg-neutral-600',
];

describe('DuoMultiSelectOptions', () => {
  let wrapper;

  const createComponent = ({
    checkedIds = [],
    disabled = false,
    mount = shallowMountExtended,
  } = {}) => {
    wrapper = mount(DuoMultiSelectOptions, {
      propsData: { options: OPTIONS, checkedIds, disabled },
    });
  };

  const findSelector = () => wrapper.findComponent(MultipleChoiceSelector);
  const findItems = () => wrapper.findAllComponents(MultipleChoiceSelectorItem);
  const treatmentOf = (index, names) => {
    const classes = findItems().at(index).classes();

    return names.filter((name) => classes.includes(name));
  };

  beforeEach(() => createComponent());

  it('offers a checkbox per option, so nothing settles on the first click', () => {
    expect(findItems()).toHaveLength(3);
    expect(findItems().at(0).text()).toContain('SP-initiated SSO');
    expect(findItems().at(0).props('description')).toBe('Starts at GitLab.');
  });

  it('badges every option the agent recommends, not just one', () => {
    expect(findItems().at(0).findComponent(GlBadge).exists()).toBe(true);
    expect(findItems().at(1).findComponent(GlBadge).exists()).toBe(true);
    expect(findItems().at(2).findComponent(GlBadge).exists()).toBe(false);
  });

  it('shows what is already ticked, so the note owns the selection', () => {
    createComponent({ checkedIds: ['jit'] });

    expect(findSelector().props('checked')).toEqual(['jit']);
  });

  it('stops the rows reacting while an answer is being posted', () => {
    createComponent({ disabled: true });

    expect(findItems().at(0).props('disabled')).toBe(true);
  });

  it.each`
    state         | disabled | expected            | unexpected
    ${'disabled'} | ${true}  | ${DISABLED_CLASSES} | ${TICKABLE_CLASSES}
    ${'tickable'} | ${false} | ${TICKABLE_CLASSES} | ${DISABLED_CLASSES}
  `(
    'gives a $state row the $state treatment and nothing from the other',
    ({ disabled, expected, unexpected }) => {
      createComponent({ disabled });

      expect(treatmentOf(0, expected)).toEqual(expected);
      expect(treatmentOf(0, unexpected)).toEqual([]);
    },
  );

  describe('when a row is ticked', () => {
    beforeEach(() => createComponent({ checkedIds: ['sp_sso'], mount: mountExtended }));

    const setChecked = (index, checked) =>
      wrapper.findAll('input[type="checkbox"]').at(index).setChecked(checked);

    it('adds the option to the selection', async () => {
      await setChecked(1, true);

      expect(wrapper.emitted('input').at(-1)).toEqual([['sp_sso', 'jit']]);
    });

    it('removes an option that was already ticked', async () => {
      await setChecked(0, false);

      expect(wrapper.emitted('input').at(-1)).toEqual([[]]);
    });
  });
});
