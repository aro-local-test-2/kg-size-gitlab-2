import { nextTick } from 'vue';
import { mount } from '@vue/test-utils';
import { GlCollapsibleListbox, GlPopover } from '@gitlab/ui';
import ChatModelSelectDropdown from 'ee/ai/duo_agentic_chat/components/model_selection/chat_model_select_dropdown.vue';
import { extendedWrapper } from 'helpers/vue_test_utils_helper';

describe('ChatModelSelectDropdown', () => {
  let wrapper;

  const defaultModelItem = {
    text: 'Claude Sonnet 4.0',
    value: '',
    ref: 'claude_sonnet_4',
    isDefault: true,
    provider: 'Anthropic',
    description: 'Fast, cost-effective responses.',
    costIndicator: '$$$',
  };
  const regularModelItem = {
    text: 'Claude Sonnet 3.5',
    value: 'claude_3_5',
    ref: 'claude_3_5',
    isDefault: false,
    provider: 'Anthropic',
    description: 'Cheaper responses.',
    costIndicator: '$$',
  };
  const duplicateModelItemA = {
    text: 'GPT 5',
    value: 'gpt_5_openai',
    ref: 'gpt_5_openai',
    isDefault: false,
    provider: 'OpenAI',
    description: 'Smart responses.',
    costIndicator: '$$$',
  };
  const duplicateModelItemB = {
    text: 'GPT 5',
    value: 'gpt_5_azure',
    ref: 'gpt_5_azure',
    isDefault: false,
    provider: 'Azure',
    description: 'Smart responses.',
    costIndicator: '$$$',
  };
  const bareModelItem = {
    text: 'My self-hosted model',
    value: 'self_hosted_model',
    ref: 'self_hosted_model',
    isDefault: false,
    provider: null,
    description: null,
    costIndicator: null,
  };

  const items = [
    defaultModelItem,
    regularModelItem,
    duplicateModelItemA,
    duplicateModelItemB,
    bareModelItem,
  ];

  const createComponent = ({ props = {}, attachTo } = {}) => {
    wrapper = extendedWrapper(
      mount(ChatModelSelectDropdown, {
        attachTo,
        propsData: {
          items,
          placeholderDropdownText: 'Select a model',
          ...props,
        },
      }),
    );
  };

  const findListbox = () => wrapper.findComponent(GlCollapsibleListbox);
  const findListboxGroups = () => findListbox().props('items');
  const findDropdownToggleText = () => wrapper.findByTestId('dropdown-toggle-text');
  const findModelNames = () => wrapper.findAllByTestId('model-name');
  const findDefaultBadges = () => wrapper.findAllByTestId('default-model-badge');
  const findPopovers = () => wrapper.findAllComponents(GlPopover);
  const findToggleButton = () => wrapper.findComponentByTestId('toggle-button');
  const findMetadataSrText = () => wrapper.findAllByTestId('model-metadata-sr-only');
  const findUseClassicChatButton = () => wrapper.findComponentByTestId('agentic-chat-toggle');

  describe('groups', () => {
    it('renders a single group with a visible All models label when there are no recent models', () => {
      createComponent();

      const groups = findListboxGroups();

      expect(groups).toHaveLength(1);
      expect(groups[0]).toMatchObject({ text: 'All models', textSrOnly: false });
      expect(groups[0].options.map((option) => option.value)).toEqual([
        '',
        'claude_3_5',
        'gpt_5_openai',
        'gpt_5_azure',
        'self_hosted_model',
      ]);
    });

    it('renders the Recent group first with prefixed values, preserving order', () => {
      createComponent({ props: { recentRefs: ['claude_3_5', 'claude_sonnet_4'] } });

      const groups = findListboxGroups();

      expect(groups).toHaveLength(2);
      expect(groups[0].text).toBe('Recent');
      expect(groups[0].options.map((option) => option.value)).toEqual([
        'recent:claude_3_5',
        'recent:claude_sonnet_4',
      ]);
    });

    it('ignores refs that are not in the available models', () => {
      createComponent({ props: { recentRefs: ['removed_model', 'claude_3_5'] } });

      expect(findListboxGroups()[0].options.map((option) => option.value)).toEqual([
        'recent:claude_3_5',
      ]);
    });

    it('hoists the default model to the top of the list without duplicating it', () => {
      createComponent({
        props: { items: [regularModelItem, defaultModelItem, bareModelItem] },
      });

      expect(findListboxGroups()[0].options.map((option) => option.value)).toEqual([
        '',
        'claude_3_5',
        'self_hosted_model',
      ]);
    });

    it('caps the Recent group at 3 models', () => {
      createComponent({
        props: { recentRefs: ['claude_3_5', 'claude_sonnet_4', 'gpt_5_openai', 'gpt_5_azure'] },
      });

      expect(findListboxGroups()[0].options).toHaveLength(3);
    });
  });

  describe('default model badge', () => {
    it('renders the badge only on the default model row, in every group it appears in', () => {
      createComponent({ props: { recentRefs: ['claude_sonnet_4'] } });

      const badges = findDefaultBadges();

      expect(badges).toHaveLength(2);
      expect(badges.at(0).text()).toBe('Default');
    });
  });

  describe('popovers', () => {
    it('renders a popover for every row with metadata, including recent rows', () => {
      createComponent({ props: { recentRefs: ['claude_3_5'] } });

      // 4 models with metadata in the main group + 1 recent clone; the bare model gets none.
      expect(findPopovers()).toHaveLength(5);
    });

    it('anchors each popover to its full listbox row with the model name as title', () => {
      createComponent({ attachTo: document.body });

      const popover = findPopovers().at(0);

      expect(popover.props('title')).toBe('Claude Sonnet 4.0');
      expect(popover.props('target')()).toBe(findModelNames().at(0).element.closest('li'));
      expect(popover.props('placement')).toBe('left');
      expect(popover.props('triggers')).toBe('manual');
    });

    it('shows only the hovered row popover and hides it on mouse leave', async () => {
      createComponent();

      const rows = wrapper.findAllByTestId('model-list-item');

      await rows.at(0).trigger('mousemove');

      expect(findPopovers().at(0).props('show')).toBe(true);
      expect(findPopovers().at(1).props('show')).toBe(false);

      await rows.at(0).trigger('mouseleave');

      expect(findPopovers().at(0).props('show')).toBe(false);
    });

    it('hides the popover when the dropdown closes', async () => {
      createComponent();

      await wrapper.findAllByTestId('model-list-item').at(0).trigger('mousemove');
      findListbox().vm.$emit('hidden');
      await nextTick();

      expect(findPopovers().at(0).props('show')).toBe(false);
    });

    it('shows the popover for the option highlighted with arrow keys from the search input', async () => {
      createComponent();

      const searchInput = wrapper.find('input[type="search"]');

      await searchInput.trigger('keydown', { code: 'ArrowDown', key: 'ArrowDown' });
      jest.runOnlyPendingTimers();
      await nextTick();

      expect(findPopovers().at(0).props('show')).toBe(true);
      expect(findPopovers().at(1).props('show')).toBe(false);

      await searchInput.trigger('keydown', { code: 'ArrowDown', key: 'ArrowDown' });
      jest.runOnlyPendingTimers();
      await nextTick();

      expect(findPopovers().at(0).props('show')).toBe(false);
      expect(findPopovers().at(1).props('show')).toBe(true);
    });

    describe('when the list is scrolled', () => {
      const scrollList = () => wrapper.find('[role="listbox"]').trigger('scroll');
      const navigateWithArrowKey = async () => {
        await wrapper
          .find('input[type="search"]')
          .trigger('keydown', { code: 'ArrowDown', key: 'ArrowDown' });
        // The component syncs the popover to the highlighted row in a macrotask.
        jest.runOnlyPendingTimers();
        await nextTick();
      };

      it('hides a hovered row popover, which would otherwise drift out of the panel', async () => {
        createComponent();

        await wrapper.findAllByTestId('model-list-item').at(0).trigger('mousemove');

        expect(findPopovers().at(0).props('show')).toBe(true);

        await scrollList();

        expect(findPopovers().at(0).props('show')).toBe(false);
      });

      it('stays closed when a row slides under a stationary pointer', async () => {
        createComponent();

        const rows = wrapper.findAllByTestId('model-list-item');

        await rows.at(0).trigger('mousemove');
        await scrollList();

        // Scrolling fires mouseenter on whichever row lands under the pointer,
        // but the pointer has not moved, so no popover should reopen.
        await rows.at(1).trigger('mouseenter');

        expect(findPopovers().at(0).props('show')).toBe(false);
        expect(findPopovers().at(1).props('show')).toBe(false);
      });

      it('keeps the popover of a row highlighted with arrow keys, which scrolls itself into view', async () => {
        createComponent();

        await navigateWithArrowKey();

        await scrollList();

        expect(findPopovers().at(0).props('show')).toBe(true);
      });

      it('closes a keyboard popover once the navigation scroll it was waiting on has finished', async () => {
        createComponent();

        await navigateWithArrowKey();

        expect(findPopovers().at(0).props('show')).toBe(true);

        jest.advanceTimersByTime(500);
        await scrollList();

        expect(findPopovers().at(0).props('show')).toBe(false);
      });
    });

    it('does not render a popover for models without metadata', () => {
      createComponent({ props: { items: [bareModelItem] } });

      expect(findPopovers()).toHaveLength(0);
    });

    it('does not render a popover when only the hosting provider is known', () => {
      createComponent({ props: { items: [{ ...bareModelItem, provider: 'Bedrock' }] } });

      expect(findPopovers()).toHaveLength(0);
    });
  });

  describe('option accessible name', () => {
    it('repeats the popover metadata in the option, since virtual focus never reaches the popover', () => {
      createComponent();

      expect(findMetadataSrText().at(0).text()).toBe('Fast, cost-effective responses. $$$');
    });

    it('joins a description with a cost indicator and omits a missing one', () => {
      createComponent({
        props: {
          items: [
            { ...bareModelItem, description: 'Only a description.' },
            { ...regularModelItem, description: null },
          ],
        },
      });

      expect(findMetadataSrText().wrappers.map((w) => w.text())).toEqual([
        'Only a description',
        '$$',
      ]);
    });

    it('renders nothing for a model without metadata', () => {
      createComponent({ props: { items: [bareModelItem] } });

      expect(findMetadataSrText()).toHaveLength(0);
    });
  });

  describe('toggle button text', () => {
    it('shows the placeholder when no models have loaded yet', () => {
      createComponent({ props: { selectedOption: null, items: [] } });

      expect(findDropdownToggleText().text()).toBe('Select a model');
    });

    it('falls back to the default model name when nothing is explicitly selected', () => {
      createComponent({ props: { selectedOption: null } });

      expect(findDropdownToggleText().text()).toBe('Claude Sonnet 4.0');
    });

    it('renders as a tertiary button', () => {
      createComponent();

      expect(findToggleButton().props('category')).toBe('tertiary');
    });

    it('labels the toggle with the action and the current model', () => {
      createComponent({ props: { selectedOption: { value: 'claude_3_5' } } });

      expect(findToggleButton().attributes('aria-label')).toBe(
        'Select a model. Current: Claude Sonnet 3.5',
      );
    });

    it('labels the toggle with the placeholder alone before a model resolves', () => {
      createComponent({ props: { selectedOption: null, items: [] } });

      expect(findToggleButton().attributes('aria-label')).toBe('Select a model');
    });

    it('resolves the selected model name by value instead of trusting selectedOption text', () => {
      createComponent({
        props: { selectedOption: { value: '', text: 'Claude Sonnet 4.0 - Default' } },
      });

      expect(findDropdownToggleText().text()).toBe('Claude Sonnet 4.0');
    });

    it('strips the exact provider suffix from the selected model name', () => {
      const suffixedItem = {
        text: 'Claude Haiku 4.5 - Bedrock',
        value: 'haiku_bedrock',
        ref: 'haiku_bedrock',
        isDefault: false,
        provider: 'Bedrock',
        description: 'Fast.',
        costIndicator: '$',
      };

      createComponent({
        props: { items: [...items, suffixedItem], selectedOption: { value: 'haiku_bedrock' } },
      });

      expect(findDropdownToggleText().text()).toBe('Claude Haiku 4.5');
    });

    it('leaves the selected model name intact when it does not end with the provider suffix', () => {
      createComponent({ props: { selectedOption: { value: 'claude_3_5' } } });

      expect(findDropdownToggleText().text()).toBe('Claude Sonnet 3.5');
    });
  });

  describe('selection', () => {
    it('re-emits a main list selection unchanged', () => {
      createComponent();

      findListbox().vm.$emit('select', 'gpt_5_azure');

      expect(wrapper.emitted('select')).toEqual([['gpt_5_azure']]);
    });

    it('strips the recent prefix and emits the original value', () => {
      createComponent({ props: { recentRefs: ['claude_3_5'] } });

      findListbox().vm.$emit('select', 'recent:claude_3_5');

      expect(wrapper.emitted('select')).toEqual([['claude_3_5']]);
    });

    it('maps a recent selection of the default model back to the default value', () => {
      createComponent({ props: { recentRefs: ['claude_sonnet_4'] } });

      findListbox().vm.$emit('select', 'recent:claude_sonnet_4');

      expect(wrapper.emitted('select')).toEqual([['']]);
    });
  });

  describe('search', () => {
    it('sets the search placeholder', () => {
      createComponent();

      expect(findListbox().props('searchPlaceholder')).toBe('Search models');
    });

    it('hides the Recent group while searching, even when its models match', async () => {
      createComponent({ props: { recentRefs: ['gpt_5_openai'] } });

      findListbox().vm.$emit('search', 'gpt');
      await nextTick();

      const groups = findListboxGroups();

      expect(groups).toHaveLength(1);
      expect(groups[0].textSrOnly).toBe(true);
      expect(groups[0].options.map((option) => option.value)).toEqual([
        'gpt_5_openai',
        'gpt_5_azure',
      ]);
    });

    it('restores the Recent group when the search is cleared', async () => {
      createComponent({ props: { recentRefs: ['claude_3_5'] } });

      findListbox().vm.$emit('search', 'gpt');
      await nextTick();
      findListbox().vm.$emit('search', '');
      await nextTick();

      expect(findListboxGroups()[0].text).toBe('Recent');
    });

    it('matches case-insensitively', async () => {
      createComponent();

      findListbox().vm.$emit('search', 'SONNET 3.5');
      await nextTick();

      expect(findListboxGroups()[0].options.map((option) => option.value)).toEqual(['claude_3_5']);
    });
  });

  describe('classic chat footer action', () => {
    it('does not render the footer toggle by default', () => {
      createComponent();

      expect(findUseClassicChatButton().exists()).toBe(false);
    });

    describe('when showClassicChatButton is true', () => {
      beforeEach(() => {
        createComponent({
          props: { showClassicChatButton: true, classicChatButtonDisabled: true },
        });
      });

      it('labels the toggle Agentic chat', () => {
        expect(findUseClassicChatButton().props('label')).toBe('Agentic chat');
      });

      it('reflects the agentic mode state in the toggle value', () => {
        expect(findUseClassicChatButton().props('value')).toBe(true);
      });

      it('passes disabled to the toggle', () => {
        expect(findUseClassicChatButton().props('disabled')).toBe(true);
      });

      it('emits switch-to-classic with the new value on change', () => {
        findUseClassicChatButton().vm.$emit('change', false);

        expect(wrapper.emitted('switch-to-classic')).toEqual([[false]]);
      });
    });
  });
});
