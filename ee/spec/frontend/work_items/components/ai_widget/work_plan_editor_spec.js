import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import WorkPlanEditor from 'ee/work_items/components/ai_widget/work_plan_editor.vue';
import MarkdownEditor from '~/vue_shared/components/markdown/markdown_editor.vue';
import namespacePathsQuery from '~/work_items/graphql/namespace_paths.query.graphql';

Vue.use(VueApollo);

const mockMarkdownPaths = {
  markdownPreviewPath: '/group/project/-/preview_markdown',
  uploadsPath: '/group/project/uploads',
  autocompleteSourcesPath: '/group/project/-/autocomplete_sources',
};

const namespacePathsHandler = jest.fn().mockResolvedValue({
  data: {
    namespace: {
      id: 'gid://gitlab/Group/1',
      markdownPaths: mockMarkdownPaths,
    },
  },
});

const defaultProps = {
  savedContent: 'existing plan',
  draftContent: '',
  isSaving: false,
};

describe('WorkPlanEditor', () => {
  let wrapper;

  const createComponent = ({ fullPath = 'group/project', ...props } = {}) => {
    wrapper = shallowMountExtended(WorkPlanEditor, {
      apolloProvider: createMockApollo([[namespacePathsQuery, namespacePathsHandler]]),
      propsData: {
        ...defaultProps,
        ...props,
      },
      provide: { fullPath },
    });
  };

  const findMarkdownEditor = () => wrapper.findComponent(MarkdownEditor);
  const findSaveButton = () => wrapper.findComponentByTestId('save-work-plan-button');
  const findCancelButton = () => wrapper.findComponentByTestId('cancel-work-plan-button');

  describe('once the markdown paths are loaded', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('renders the markdown editor with the saved content', () => {
      expect(findMarkdownEditor().props()).toMatchObject({
        value: 'existing plan',
        renderMarkdownPath: mockMarkdownPaths.markdownPreviewPath,
        uploadsPath: mockMarkdownPaths.uploadsPath,
      });
    });

    describe('when a draft exists', () => {
      beforeEach(async () => {
        createComponent({ draftContent: 'draft plan' });
        await waitForPromises();
      });

      it('initialises the editor from the draft', () => {
        expect(findMarkdownEditor().props('value')).toBe('draft plan');
      });
    });

    describe('keystrokes', () => {
      it('emits draft-change on every input', async () => {
        await findMarkdownEditor().vm.$emit('input', 'half-typed');
        expect(wrapper.emitted('draft-change')).toEqual([['half-typed']]);
      });
    });

    describe('save', () => {
      it('emits "save" with the trimmed content', async () => {
        await findMarkdownEditor().vm.$emit('input', '  updated plan  ');
        await findSaveButton().vm.$emit('click');
        expect(wrapper.emitted('save')).toEqual([['updated plan']]);
      });
    });

    describe('cancel', () => {
      beforeEach(() => {
        findCancelButton().vm.$emit('click');
      });

      it('emits "cancel-edit"', () => {
        expect(wrapper.emitted('cancel-edit')).toHaveLength(1);
      });
    });
  });
});
