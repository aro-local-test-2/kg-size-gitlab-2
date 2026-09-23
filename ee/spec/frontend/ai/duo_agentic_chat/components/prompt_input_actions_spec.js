import { GlDisclosureDropdown, GlToggle } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import PromptInputActions from 'ee/ai/duo_agentic_chat/components/prompt_input_actions.vue';
import { goalSlashCommand } from 'ee/ai/duo_agentic_chat/plugins/goal';

describe('PromptInputActions', () => {
  let wrapper;

  const createComponent = ({
    propsData = {},
    glFeatures = {},
    webSearchAllowedForGroup = true,
  } = {}) => {
    wrapper = shallowMountExtended(PromptInputActions, {
      propsData,
      provide: { glFeatures, webSearchAllowedForGroup },
    });
  };

  // Mounts without providing the group grant at all, to exercise the inject default.
  const createComponentWithoutGroupGrant = ({ glFeatures = {} } = {}) => {
    wrapper = shallowMountExtended(PromptInputActions, {
      provide: { glFeatures },
    });
  };

  const findDropdown = () => wrapper.findComponent(GlDisclosureDropdown);
  const findWebSearchToggle = () => wrapper.findComponent(GlToggle);
  const findWebSearchItem = () => wrapper.findComponentByTestId('web-search-item');
  const findAttachImageItem = () => wrapper.findComponentByTestId('attach-image-item');
  const findGoalItem = () => wrapper.findComponentByTestId('goal-item');

  const webSearchOn = { dapWebSearch: true };
  const attachmentsOn = { dapWebChatFileAttachments: true };

  describe('visibility', () => {
    it.each`
      dapWebSearch | dapWebChatFileAttachments | goalAvailable | exists
      ${false}     | ${false}                  | ${false}      | ${false}
      ${true}      | ${false}                  | ${false}      | ${true}
      ${false}     | ${true}                   | ${false}      | ${true}
      ${false}     | ${false}                  | ${true}       | ${true}
      ${true}      | ${true}                   | ${true}       | ${true}
    `(
      'renders the dropdown: $exists (web search: $dapWebSearch, attachments: $dapWebChatFileAttachments, goal: $goalAvailable)',
      ({ dapWebSearch, dapWebChatFileAttachments, goalAvailable, exists }) => {
        createComponent({
          glFeatures: { dapWebSearch, dapWebChatFileAttachments },
          propsData: { goalAvailable },
        });

        expect(findDropdown().exists()).toBe(exists);
      },
    );

    it('hides the web search item when only the goal row is available', () => {
      createComponent({ propsData: { goalAvailable: true } });

      expect(findWebSearchItem().exists()).toBe(false);
    });

    it('hides the web search item when only attachments are enabled', () => {
      createComponent({ glFeatures: attachmentsOn });

      expect(findWebSearchItem().exists()).toBe(false);
    });

    it('renders the dropdown without a caret', () => {
      createComponent({ glFeatures: webSearchOn });

      expect(findDropdown().props('noCaret')).toBe(true);
    });

    it.each`
      dapWebSearch | webSearchAllowedForGroup | shouldRender
      ${true}      | ${true}                  | ${true}
      ${true}      | ${false}                 | ${false}
      ${false}     | ${true}                  | ${false}
      ${false}     | ${false}                 | ${false}
    `(
      'renders the dropdown as $shouldRender when the flag is $dapWebSearch and the group allows it $webSearchAllowedForGroup',
      ({ dapWebSearch, webSearchAllowedForGroup, shouldRender }) => {
        createComponent({ glFeatures: { dapWebSearch }, webSearchAllowedForGroup });

        expect(findDropdown().exists()).toBe(shouldRender);
      },
    );

    it('renders nothing when the group grant is not provided at all', () => {
      createComponentWithoutGroupGrant({ glFeatures: webSearchOn });

      expect(findDropdown().exists()).toBe(false);
    });
  });

  describe('attach image action', () => {
    it('is not offered when dapWebChatFileAttachments is disabled', () => {
      createComponent({ glFeatures: webSearchOn });

      expect(findAttachImageItem().exists()).toBe(false);
    });

    it.each([true, false])(
      'is offered regardless of the web search flag (dapWebSearch: %p)',
      (dapWebSearch) => {
        createComponent({ glFeatures: { ...attachmentsOn, dapWebSearch } });

        expect(findAttachImageItem().exists()).toBe(true);
      },
    );

    it('emits attach-files when activated', () => {
      createComponent({ glFeatures: attachmentsOn });

      findAttachImageItem().vm.$emit('action');

      expect(wrapper.emitted('attach-files')).toEqual([[]]);
    });

    // The menu does not auto-close, so that the web search toggle stays put when
    // tapped. This item has to close it, or it sits behind the file dialog.
    it('closes the menu', () => {
      createComponent({ glFeatures: attachmentsOn });
      const close = jest.fn();
      wrapper.vm.$refs.dropdown.close = close;

      findAttachImageItem().vm.$emit('action');

      expect(close).toHaveBeenCalled();
    });
  });

  describe('web search toggle', () => {
    it.each([true, false])(
      'reflects the webSearchEnabled prop (%s) as the toggle value',
      (value) => {
        createComponent({ glFeatures: webSearchOn, propsData: { webSearchEnabled: value } });

        expect(findWebSearchToggle().props('value')).toBe(value);
      },
    );

    it('gives the toggle an accessible label', () => {
      createComponent({ glFeatures: webSearchOn });

      expect(findWebSearchToggle().props('label')).toBe('Web search');
    });

    it.each`
      webSearchEnabled | expected
      ${false}         | ${true}
      ${true}          | ${false}
    `(
      'emits update:web-search-enabled with $expected when the row is activated (current: $webSearchEnabled)',
      ({ webSearchEnabled, expected }) => {
        createComponent({ glFeatures: webSearchOn, propsData: { webSearchEnabled } });

        findWebSearchItem().vm.$emit('action');

        expect(wrapper.emitted('update:web-search-enabled')).toEqual([[expected]]);
      },
    );
  });

  describe('goal row', () => {
    // Replacing the `$refs` entry itself is rejected in Vue 3, where `$refs` is readonly,
    // so the method is stubbed on the dropdown instance the ref already holds.
    const stubCloseAndFocus = () => {
      wrapper.vm.$refs.dropdown.closeAndFocus = jest.fn();

      return wrapper.vm.$refs.dropdown.closeAndFocus;
    };

    // The composer answers whether goal mode can run; this row only renders it.
    it.each([true, false])('renders %p when goal mode is that available', (goalAvailable) => {
      createComponent({ propsData: { goalAvailable } });

      expect(findGoalItem().exists()).toBe(goalAvailable);
    });

    // The blocked state view and the light state manager both rely on this default.
    it('hides the row when availability is not supplied at all', () => {
      createComponent({ glFeatures: webSearchOn });

      expect(findGoalItem().exists()).toBe(false);
    });

    it('names the mode it starts', () => {
      createComponent({ propsData: { goalAvailable: true } });

      expect(findGoalItem().text()).toBe('Goal');
    });

    // Dispatches the `/goal` command itself, so this row and the suggestion menu reach
    // goal mode by one path rather than two.
    it('dispatches the goal command', () => {
      createComponent({ propsData: { goalAvailable: true } });
      stubCloseAndFocus();

      findGoalItem().vm.$emit('action');

      expect(wrapper.emitted('dispatch-action')).toEqual([
        ['startGoal', { command: goalSlashCommand }],
      ]);
    });

    // `auto-close` is off so the web search toggle can be flipped without the menu
    // shutting, which leaves a one-shot action to close it.
    it('closes the dropdown, since it is an action rather than a toggle', () => {
      createComponent({ propsData: { goalAvailable: true } });
      const closeAndFocus = stubCloseAndFocus();

      findGoalItem().vm.$emit('action');

      expect(closeAndFocus).toHaveBeenCalledTimes(1);
    });
  });

  describe('disabled state', () => {
    it('disables the dropdown toggle when the disabled prop is true', () => {
      createComponent({ glFeatures: webSearchOn, propsData: { disabled: true } });

      expect(findDropdown().props('disabled')).toBe(true);
    });
  });
});
