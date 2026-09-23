import { GlModal, GlFormCharacterCount } from '@gitlab/ui';
import { nextTick } from 'vue';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import waitForPromises from 'helpers/wait_for_promises';
import { confirmAction } from '~/lib/utils/confirm_via_gl_modal/confirm_via_gl_modal';
import DecisionLogFormModal from 'ee/work_items/components/decision_log/decision_log_form_modal.vue';
import { DECISION_REMAINING_COUNT_THRESHOLD } from 'ee/work_items/components/decision_log/constants';
import DecisionLogDeciderSelect from 'ee/work_items/components/decision_log/decision_log_decider_select.vue';

jest.mock('~/lib/utils/confirm_via_gl_modal/confirm_via_gl_modal');

const participants = [
  { id: 'gid://gitlab/User/1', name: 'Avery Patel' },
  { id: 'gid://gitlab/User/2', name: 'Jordan Lee' },
];

const currentUser = {
  id: 'gid://gitlab/User/7',
  username: 'sasha',
  name: 'Sasha Kim',
  avatarUrl: '/uploads/avatar.png',
};

const decision = {
  title: 'Handle common deviations, document limitations, no silent failures',
  resolvedBy: { id: 'gid://gitlab/User/2', name: 'Jordan Lee', avatarUrl: null },
  description: 'Real-world IdPs frequently deviate from the SAML 2.0 profile.',
  resolutionRationale: 'Answers the open question about how tolerant we should be.',
  noteUrl: 'https://gitlab.example.com/acme/web/-/work_items/3745',
};

const buildOptions = (nodes) => ({
  __typename: 'WorkItemDecisionOptionConnection',
  nodes: nodes.map(({ content, selected }, index) => ({
    __typename: 'WorkItemDecisionOption',
    id: `gid://gitlab/WorkItems::DecisionOption/${index + 1}`,
    content,
    selected,
  })),
});

describe('DecisionLogFormModal', () => {
  let wrapper;

  beforeEach(() => {
    window.gon = {
      ...window.gon,
      current_user_id: 7,
      current_username: currentUser.username,
      current_user_fullname: currentUser.name,
      current_user_avatar_url: currentUser.avatarUrl,
    };
  });

  const createComponent = ({
    visible = true,
    decision: editedDecision = null,
    participants: deciders = participants,
    fullPath = 'group/project',
    isGroup = false,
  } = {}) => {
    wrapper = mountExtended(DecisionLogFormModal, {
      propsData: {
        visible,
        decision: editedDecision,
        participants: deciders,
        fullPath,
        isGroup,
      },
      stubs: {
        GlModal: stubComponent(GlModal),
        DecisionLogDeciderSelect: stubComponent(DecisionLogDeciderSelect),
      },
    });
  };

  const findModal = () => wrapper.findComponent(GlModal);
  const findSummaryInput = () => wrapper.findByTestId('decision-summary-input');
  const findDecidedBySelect = () => wrapper.findComponent(DecisionLogDeciderSelect);
  const selectDecider = async (user) => {
    findDecidedBySelect().vm.$emit('input', user.id);
    findDecidedBySelect().vm.$emit('select-user', user);
    await nextTick();
  };
  const findContextInput = () => wrapper.findByTestId('decision-context-input');
  const findWhyInput = () => wrapper.findByTestId('decision-why-input');
  const findSourceLinkInput = () => wrapper.findByTestId('decision-source-link-input');

  const isFlagged = (input) => input.classes('is-invalid');

  const findCharacterCount = (countTextId) =>
    wrapper
      .findAllComponents(GlFormCharacterCount)
      .wrappers.find((count) => count.props('countTextId') === countTextId);

  const submit = async () => {
    findModal().vm.$emit('primary', { preventDefault: jest.fn() });
    await nextTick();
  };

  const fillRequiredFields = async () => {
    await findSummaryInput().setValue('Enforce strict conformance');
    await findContextInput().setValue('Two options were on the table.');
  };

  const dismiss = async (trigger = 'cancel') => {
    const event = { trigger, preventDefault: jest.fn() };
    findModal().vm.$emit('hide', event);
    await waitForPromises();

    return event;
  };

  describe('when no decision is given', () => {
    beforeEach(() => {
      createComponent();
    });

    it('titles the modal "New decision"', () => {
      expect(findModal().props('title')).toBe('New decision');
    });

    it('labels the primary action "Create decision"', () => {
      expect(findModal().props('actionPrimary').text).toBe('Create decision');
    });

    it('starts the text fields empty', () => {
      expect(findSummaryInput().element.value).toBe('');
      expect(findContextInput().element.value).toBe('');
      expect(findWhyInput().element.value).toBe('');
      expect(findSourceLinkInput().element.value).toBe('');
    });

    it('preselects the current user as the decider', () => {
      expect(findDecidedBySelect().props('value')).toBe(currentUser.id);
    });

    it('passes the current user through, so the dropdown can name them', () => {
      expect(findDecidedBySelect().props('selectedUser')).toEqual(currentUser);
    });

    it('hands the participants to the decider dropdown', () => {
      expect(findDecidedBySelect().props('participants')).toEqual(participants);
    });

    it('hands the workspace to the decider dropdown, so it can search', () => {
      expect(findDecidedBySelect().props()).toMatchObject({
        fullPath: 'group/project',
        isGroup: false,
      });
    });

    it('leaves the source link editable', () => {
      expect(findSourceLinkInput().attributes('disabled')).toBeUndefined();
    });

    it('says where a source link can come from', () => {
      expect(wrapper.text()).toContain(
        'Slack, Google Docs, GitLab, or anywhere the discussion lives.',
      );
    });

    it('flags nothing', () => {
      expect(isFlagged(findSummaryInput())).toBe(false);
      expect(isFlagged(findContextInput())).toBe(false);
    });
  });

  describe('when there is no current user', () => {
    beforeEach(() => {
      delete window.gon.current_user_id;
      createComponent();
    });

    it('leaves the decider unselected', () => {
      expect(findDecidedBySelect().props('value')).toBe(null);
    });

    it('gives the dropdown nobody to name', () => {
      expect(findDecidedBySelect().props('selectedUser')).toBe(null);
    });

    describe('and the form is submitted', () => {
      beforeEach(async () => {
        await fillRequiredFields();
        await submit();
      });

      it('flags the decider field', () => {
        expect(findDecidedBySelect().props('isInvalid')).toBe(true);
      });

      it('does not save', () => {
        expect(wrapper.emitted('save')).toBeUndefined();
      });
    });
  });

  describe('when a decision is given', () => {
    beforeEach(() => {
      createComponent({ decision });
    });

    it('titles the modal "Edit decision"', () => {
      expect(findModal().props('title')).toBe('Edit decision');
    });

    it('labels the primary action "Save changes"', () => {
      expect(findModal().props('actionPrimary').text).toBe('Save changes');
    });

    it('fills every field from the decision', () => {
      expect(findSummaryInput().element.value).toBe(decision.title);
      expect(findDecidedBySelect().props('value')).toBe(decision.resolvedBy.id);
      expect(findContextInput().element.value).toBe(decision.description);
      expect(findWhyInput().element.value).toBe(decision.resolutionRationale);
      expect(findSourceLinkInput().element.value).toBe(decision.noteUrl);
    });

    it('locks the source link', () => {
      expect(findSourceLinkInput().attributes('disabled')).toBeDefined();
    });

    it('locks the decision, because it cannot be changed once it is logged', () => {
      expect(findSummaryInput().attributes('disabled')).toBeDefined();
    });

    it('locks the decider, because the update mutation cannot change it', () => {
      expect(findDecidedBySelect().props('disabled')).toBe(true);
    });

    it('leaves the fields that can still be changed editable', () => {
      expect(findContextInput().attributes('disabled')).toBeUndefined();
      expect(findWhyInput().attributes('disabled')).toBeUndefined();
    });

    it('explains why the source link is locked', () => {
      expect(wrapper.text()).toContain(
        'Captured automatically from the source and cannot be changed.',
      );
    });
  });

  describe('when a decision is edited and submitted', () => {
    beforeEach(async () => {
      createComponent({ decision });
      await findContextInput().setValue('Two IdPs were tested first.');
      await submit();
    });

    it('sends the fields the user changed', () => {
      expect(wrapper.emitted('save')[0][0]).toMatchObject({
        description: 'Two IdPs were tested first.',
      });
    });

    it('sends no decision text, because the field that holds it is locked', () => {
      expect(wrapper.emitted('save')[0][0].title).toBe('');
    });
  });

  describe('when a saved why is cleared on edit', () => {
    beforeEach(async () => {
      createComponent({ decision });
      await findWhyInput().setValue('   ');
      await submit();
    });

    it('flags the why field', () => {
      expect(isFlagged(findWhyInput())).toBe(true);
    });

    it('explains that the value cannot be removed', () => {
      expect(wrapper.text()).toContain('You can change this value, but you cannot remove it.');
    });

    it('does not save, because the update mutation cannot clear a value', () => {
      expect(wrapper.emitted('save')).toBeUndefined();
    });
  });

  describe('when an editable source link is cleared on edit', () => {
    beforeEach(async () => {
      createComponent({
        decision: { ...decision, noteUrl: null, sourceLink: 'https://docs.example.com/saml' },
      });
      await findSourceLinkInput().setValue('');
      await submit();
    });

    it('flags the source link', () => {
      expect(isFlagged(findSourceLinkInput())).toBe(true);
    });

    it('explains that the value cannot be removed', () => {
      expect(wrapper.text()).toContain('You can change this value, but you cannot remove it.');
    });

    it('does not save', () => {
      expect(wrapper.emitted('save')).toBeUndefined();
    });
  });

  describe('when an empty why is left empty on edit', () => {
    beforeEach(async () => {
      createComponent({ decision: { ...decision, resolutionRationale: null } });
      await findContextInput().setValue('Two IdPs were tested first.');
      await submit();
    });

    it('saves, because nothing was removed', () => {
      expect(wrapper.emitted('save')).toHaveLength(1);
    });
  });

  describe('when the given decision holds no text', () => {
    beforeEach(async () => {
      createComponent({ decision: { ...decision, title: '' } });
      await submit();
    });

    it('saves anyway, because nobody can fill in a locked field', () => {
      expect(wrapper.emitted('save')).toHaveLength(1);
    });
  });

  describe('when the decision settled on an option', () => {
    beforeEach(() => {
      createComponent({
        decision: {
          ...decision,
          // Recorded by hand, so the question line is empty and the text lives on the option.
          title: null,
          options: buildOptions([{ content: 'Ship SAML first, SCIM follows', selected: true }]),
        },
      });
    });

    it('fills the decision field from the settled option', () => {
      expect(findSummaryInput().element.value).toBe('Ship SAML first, SCIM follows');
    });
  });

  describe('when the decision settled on an option and submits untouched', () => {
    beforeEach(async () => {
      createComponent({
        decision: {
          ...decision,
          options: buildOptions([{ content: 'Ship SAML first, SCIM follows', selected: true }]),
        },
      });
      await submit();
    });

    it('sends no decision text, so the option cannot overwrite the question', () => {
      expect(wrapper.emitted('save')[0][0].title).toBe('');
    });
  });

  describe('when the decision settled on nothing', () => {
    beforeEach(() => {
      createComponent({
        decision: {
          ...decision,
          options: buildOptions([{ content: 'An option nobody picked', selected: false }]),
        },
      });
    });

    it('falls back to the title, because no option holds the decision', () => {
      expect(findSummaryInput().element.value).toBe(decision.title);
    });
  });

  describe('when the decision carries a source link instead of a note', () => {
    const sourceLink = 'https://docs.example.com/saml-rollout';

    beforeEach(() => {
      createComponent({ decision: { ...decision, noteUrl: null, sourceLink } });
    });

    it('fills the link field from the source link', () => {
      expect(findSourceLinkInput().element.value).toBe(sourceLink);
    });

    it('leaves the link editable, because no note owns it', () => {
      expect(findSourceLinkInput().attributes('disabled')).toBeUndefined();
    });
  });

  describe('when the work item lives in a group', () => {
    beforeEach(() => {
      createComponent({ isGroup: true });
    });

    it('tells the decider dropdown to search the group', () => {
      expect(findDecidedBySelect().props('isGroup')).toBe(true);
    });
  });

  describe('when a decision without a note URL is given', () => {
    beforeEach(() => {
      createComponent({
        decision: { ...decision, noteUrl: '', sourceLink: 'https://example.com/doc' },
      });
    });

    it('leaves the source link editable', () => {
      expect(findSourceLinkInput().attributes('disabled')).toBeUndefined();
    });

    it('fills the source link from the decision', () => {
      expect(findSourceLinkInput().element.value).toBe('https://example.com/doc');
    });
  });

  describe('when the given decision names its decider as a user', () => {
    const decider = { id: 'gid://gitlab/User/9', name: 'Robin Diaz' };

    beforeEach(() => {
      createComponent({ decision: { ...decision, resolvedBy: decider } });
    });

    it('selects them by id', () => {
      expect(findDecidedBySelect().props('value')).toBe(decider.id);
    });

    it('passes the user through, so the dropdown can name them', () => {
      expect(findDecidedBySelect().props('selectedUser')).toEqual(decider);
    });
  });

  describe('when the user picks a different decider', () => {
    beforeEach(async () => {
      createComponent();
      await fillRequiredFields();
      await selectDecider(participants[1]);
      await submit();
    });

    it('saves the decider they picked', () => {
      expect(wrapper.emitted('save')[0][0]).toMatchObject({ resolvedBy: participants[1] });
    });
  });

  describe('when the required fields are empty on submit', () => {
    beforeEach(async () => {
      createComponent();
      await submit();
    });

    it('flags the decision summary', () => {
      expect(isFlagged(findSummaryInput())).toBe(true);
    });

    it('asks for a decision summary', () => {
      expect(wrapper.text()).toContain('Enter a summary of the decision');
    });

    it('flags the context', () => {
      expect(isFlagged(findContextInput())).toBe(true);
    });

    it('asks for the context', () => {
      expect(wrapper.text()).toContain('Describe the context for this decision');
    });

    it('leaves the optional fields alone', () => {
      expect(isFlagged(findWhyInput())).toBe(false);
      expect(isFlagged(findSourceLinkInput())).toBe(false);
    });

    it('does not save', () => {
      expect(wrapper.emitted('save')).toBeUndefined();
    });

    it('keeps the modal open', () => {
      expect(wrapper.emitted('hide')).toBeUndefined();
    });
  });

  describe('when the required fields hold only whitespace on submit', () => {
    beforeEach(async () => {
      createComponent();
      await findSummaryInput().setValue('   ');
      await findContextInput().setValue('   ');
      await submit();
    });

    it('flags the decision summary', () => {
      expect(isFlagged(findSummaryInput())).toBe(true);
    });

    it('does not save', () => {
      expect(wrapper.emitted('save')).toBeUndefined();
    });
  });

  describe('when the required fields are corrected after a failed submit', () => {
    beforeEach(async () => {
      createComponent();
      await submit();
      await fillRequiredFields();
    });

    it('clears the flags', () => {
      expect(isFlagged(findSummaryInput())).toBe(false);
      expect(isFlagged(findContextInput())).toBe(false);
    });
  });

  describe('when a complete form is submitted', () => {
    beforeEach(async () => {
      createComponent();
      await fillRequiredFields();
      await findWhyInput().setValue('It is the cheapest option.');
      await findSourceLinkInput().setValue('https://example.com/thread');
      await submit();
    });

    it('emits the decision', () => {
      expect(wrapper.emitted('save')).toEqual([
        [
          {
            title: 'Enforce strict conformance',
            resolvedBy: currentUser,
            description: 'Two options were on the table.',
            resolutionRationale: 'It is the cheapest option.',
            sourceLink: 'https://example.com/thread',
          },
        ],
      ]);
    });

    it('leaves closing to the parent', () => {
      expect(wrapper.emitted('hide')).toBeUndefined();
    });
  });

  describe('when the participants arrive after the form has opened', () => {
    beforeEach(async () => {
      createComponent({ participants: [] });
      await wrapper.setProps({ participants });
    });

    it('keeps the current user selected', () => {
      expect(findDecidedBySelect().props('value')).toBe(currentUser.id);
    });

    describe('and the form is then dismissed', () => {
      beforeEach(async () => {
        await dismiss();
      });

      it('does not ask the user to confirm, because the form still reads as untouched', () => {
        expect(confirmAction).not.toHaveBeenCalled();
      });
    });
  });

  describe('when an untouched form is dismissed', () => {
    let event;

    beforeEach(async () => {
      createComponent();
      event = await dismiss();
    });

    it('does not ask the user to confirm', () => {
      expect(confirmAction).not.toHaveBeenCalled();
    });

    it('lets the modal close', () => {
      expect(event.preventDefault).not.toHaveBeenCalled();
    });
  });

  describe('when an edited new decision form is dismissed', () => {
    let event;

    beforeEach(async () => {
      confirmAction.mockResolvedValue(false);
      createComponent();
      await findSummaryInput().setValue('Enforce strict conformance');
      event = await dismiss();
    });

    it('holds the modal open while it asks', () => {
      expect(event.preventDefault).toHaveBeenCalled();
    });

    it('asks about cancelling the creation', () => {
      expect(confirmAction).toHaveBeenCalledWith(
        'Are you sure you want to cancel creating this decision?',
        {
          primaryBtnText: 'Discard changes',
          primaryBtnVariant: 'danger',
          cancelBtnText: 'Continue editing',
        },
      );
    });

    it('keeps the form open, because the user chose to keep editing', () => {
      expect(wrapper.emitted('hide')).toBeUndefined();
    });
  });

  describe('when an edited existing decision form is dismissed', () => {
    beforeEach(async () => {
      confirmAction.mockResolvedValue(false);
      createComponent({ decision });
      await findContextInput().setValue('Two options were on the table.');
      await dismiss();
    });

    it('asks about cancelling the edit', () => {
      expect(confirmAction).toHaveBeenCalledWith(
        'Are you sure you want to cancel editing this decision?',
        expect.any(Object),
      );
    });
  });

  describe('when the user discards the changes', () => {
    beforeEach(async () => {
      confirmAction.mockResolvedValue(true);
      createComponent();
      await findSummaryInput().setValue('Enforce strict conformance');
      await dismiss();
    });

    it('closes the form', () => {
      expect(wrapper.emitted('hide')).toHaveLength(1);
    });
  });

  describe.each(['headerclose', 'esc', 'backdrop'])(
    'when an edited form is dismissed by %s',
    (trigger) => {
      beforeEach(async () => {
        confirmAction.mockResolvedValue(false);
        createComponent();
        await findSummaryInput().setValue('Enforce strict conformance');
        await dismiss(trigger);
      });

      it('asks the user to confirm', () => {
        expect(confirmAction).toHaveBeenCalled();
      });
    },
  );

  describe('when the parent closes an edited form through the visible prop', () => {
    let event;

    beforeEach(async () => {
      createComponent();
      await findSummaryInput().setValue('Enforce strict conformance');
      event = await dismiss(null);
    });

    it('does not ask the user to confirm', () => {
      expect(confirmAction).not.toHaveBeenCalled();
    });

    it('lets the modal close', () => {
      expect(event.preventDefault).not.toHaveBeenCalled();
    });
  });

  describe('when the modal closes', () => {
    beforeEach(() => {
      createComponent();
      findModal().vm.$emit('hidden');
    });

    it('emits hide', () => {
      expect(wrapper.emitted('hide')).toHaveLength(1);
    });
  });

  describe('the source link field', () => {
    beforeEach(() => {
      createComponent();
    });

    it('reads as a url', () => {
      expect(findSourceLinkInput().attributes('type')).toBe('url');
    });

    it('shows the format by example, rather than a scheme to complete', () => {
      expect(findSourceLinkInput().attributes('placeholder')).toBe('https://example.com');
    });
  });

  describe.each([
    ['no protocol', 'example.com/thread'],
    ['an unsupported protocol', 'ftp://example.com/thread'],
    ['no top-level domain', 'https://example'],
    ['a space', 'https://exa mple.com'],
  ])('when the source link has %s on submit', (_, sourceLink) => {
    beforeEach(async () => {
      createComponent();
      await fillRequiredFields();
      await findSourceLinkInput().setValue(sourceLink);
      await submit();
    });

    it('flags the source link', () => {
      expect(isFlagged(findSourceLinkInput())).toBe(true);
    });

    it('asks for a full URL', () => {
      expect(wrapper.text()).toContain('Enter a full URL, like https://example.com');
    });

    it('does not save', () => {
      expect(wrapper.emitted('save')).toBeUndefined();
    });
  });

  describe.each([
    'http://example.com',
    'https://example.com/thread?tab=1#reply',
    'https://sub.example.co.uk/a_b-c',
    'https://example.com/issues?label_name[]=bug',
  ])('when the source link is "%s" on submit', (sourceLink) => {
    beforeEach(async () => {
      createComponent();
      await fillRequiredFields();
      await findSourceLinkInput().setValue(sourceLink);
      await submit();
    });

    it('accepts it', () => {
      expect(isFlagged(findSourceLinkInput())).toBe(false);
      expect(wrapper.emitted('save')).toHaveLength(1);
    });
  });

  describe.each([
    {
      field: 'decision summary',
      countTextId: 'decision-log-summary-character-count',
      findInput: findSummaryInput,
      limit: 255,
    },
    {
      field: 'context',
      countTextId: 'decision-log-context-character-count',
      findInput: findContextInput,
      limit: 1000,
    },
    {
      field: 'why',
      countTextId: 'decision-log-why-character-count',
      findInput: findWhyInput,
      limit: 800,
    },
  ])('the $field field', ({ countTextId, findInput, limit }) => {
    beforeEach(() => {
      createComponent();
    });

    it('points at its character count, so a screen reader reads the two together', () => {
      expect(findInput().attributes('aria-describedby').split(' ')).toContain(countTextId);
    });

    describe('when it is empty', () => {
      it('says nothing about the limit', () => {
        expect(findCharacterCount(countTextId).text()).toBe('');
      });
    });

    describe('when it is well under the limit', () => {
      beforeEach(async () => {
        await findInput().setValue('a'.repeat(limit - DECISION_REMAINING_COUNT_THRESHOLD - 1));
      });

      it('says nothing about the limit', () => {
        expect(findCharacterCount(countTextId).text()).toBe('');
      });
    });

    describe(`when it comes within ${DECISION_REMAINING_COUNT_THRESHOLD} characters of the limit`, () => {
      beforeEach(async () => {
        await findInput().setValue('a'.repeat(limit - DECISION_REMAINING_COUNT_THRESHOLD));
      });

      it('counts down the characters left', () => {
        expect(findCharacterCount(countTextId).text()).toContain(
          `${DECISION_REMAINING_COUNT_THRESHOLD} characters remaining.`,
        );
      });
    });

    describe('when it has one character left', () => {
      beforeEach(async () => {
        await findInput().setValue('a'.repeat(limit - 1));
      });

      it('counts in the singular', () => {
        expect(findCharacterCount(countTextId).text()).toContain('1 character remaining.');
      });
    });

    describe('when it is filled to the limit', () => {
      beforeEach(async () => {
        await findInput().setValue('a'.repeat(limit));
      });

      it('says nothing is left', () => {
        expect(findCharacterCount(countTextId).text()).toContain('0 characters remaining.');
      });
    });

    describe('when it goes over the limit', () => {
      beforeEach(async () => {
        await findInput().setValue('a'.repeat(limit + 3));
      });

      it('counts how far over the limit it is', () => {
        expect(findCharacterCount(countTextId).text()).toContain('3 characters over limit.');
      });
    });

    describe('when it goes one character over the limit', () => {
      beforeEach(async () => {
        await findInput().setValue('a'.repeat(limit + 1));
      });

      it('counts in the singular', () => {
        expect(findCharacterCount(countTextId).text()).toContain('1 character over limit.');
      });
    });
  });

  describe.each([
    { field: 'decision summary', findInput: findSummaryInput, limit: 255 },
    { field: 'context', findInput: findContextInput, limit: 1000 },
    { field: 'why', findInput: findWhyInput, limit: 800 },
  ])('when the $field is over the limit on submit', ({ findInput, limit }) => {
    beforeEach(async () => {
      createComponent();
      await fillRequiredFields();
      await findInput().setValue('a'.repeat(limit + 1));
      await submit();
    });

    it('flags the field', () => {
      expect(isFlagged(findInput())).toBe(true);
    });

    it('does not save', () => {
      expect(wrapper.emitted('save')).toBeUndefined();
    });
  });

  describe.each([
    {
      field: 'decision summary',
      findInput: findSummaryInput,
      limit: 255,
      requiredMessage: 'Enter a summary of the decision',
    },
    {
      field: 'context',
      findInput: findContextInput,
      limit: 1000,
      requiredMessage: 'Describe the context for this decision',
    },
  ])(
    'when the required $field is over the limit on submit',
    ({ findInput, limit, requiredMessage }) => {
      beforeEach(async () => {
        createComponent();
        await fillRequiredFields();
        await findInput().setValue('a'.repeat(limit + 1));
        await submit();
      });

      it('does not also ask the user to fill the field in', () => {
        expect(wrapper.text()).not.toContain(requiredMessage);
      });
    },
  );

  describe('when the modal reopens after a failed submit', () => {
    beforeEach(async () => {
      createComponent({ visible: false });
      await wrapper.setProps({ visible: true });
      await submit();

      await wrapper.setProps({ visible: false });
      await wrapper.setProps({ visible: true });
    });

    it('empties the fields', () => {
      expect(findSummaryInput().element.value).toBe('');
    });

    it('clears the flags', () => {
      expect(isFlagged(findSummaryInput())).toBe(false);
    });
  });
});
