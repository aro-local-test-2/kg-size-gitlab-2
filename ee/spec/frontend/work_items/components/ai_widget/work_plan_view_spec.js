import { GlLoadingIcon } from '@gitlab/ui';
import { nextTick } from 'vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import WorkPlanView from 'ee/work_items/components/ai_widget/work_plan_view.vue';
import { renderGFM } from '~/behaviors/markdown/render_gfm';
import { destroyImageLightbox } from '~/behaviors/markdown/render_image_lightbox';
import { DUO_CHAT_AGENT_GITLAB_DUO } from 'ee/ai/constants';

jest.mock('~/behaviors/markdown/render_gfm');
jest.mock('~/behaviors/markdown/render_image_lightbox');

const defaultProps = {
  isLoading: false,
  canUpdate: true,
  savedContent: '',
  savedContentHtml: '',
  workItemId: 'gid://gitlab/WorkItem/1',
  workItemWebUrl: 'http://gdk.test/group/project/-/work_items/1',
};

describe('WorkPlanView', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(WorkPlanView, {
      propsData: {
        ...defaultProps,
        ...props,
      },
    });
  };

  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);
  const findEmptyState = () => wrapper.findByTestId('work-plan-empty-state');
  const findEmptyStateComponent = () => wrapper.findComponentByTestId('work-plan-empty-state');
  const findGenerateWithDuoButton = () =>
    wrapper.findComponentByTestId('panel-generate-with-duo-button');
  const findCreateManuallyButton = () =>
    wrapper.findComponentByTestId('panel-create-manually-button');
  const findRenderedMarkdown = () => wrapper.findByTestId('work-plan-rendered');

  describe('while the plan content is loading', () => {
    beforeEach(() => {
      createComponent({ savedContent: '', canUpdate: true, isLoading: true });
    });

    it('shows a loading icon instead of the empty state', () => {
      expect(findLoadingIcon().exists()).toBe(true);
      expect(findEmptyState().exists()).toBe(false);
    });
  });

  describe('when there is no saved content and the user can update', () => {
    beforeEach(() => {
      createComponent({ savedContent: '', canUpdate: true });
    });

    it('shows the empty state', () => {
      expect(findEmptyState().exists()).toBe(true);
      expect(findEmptyStateComponent().props('title')).toBe('Create a workplan');
    });

    it('renders both empty-state actions', () => {
      expect(findGenerateWithDuoButton().exists()).toBe(true);
      expect(findCreateManuallyButton().exists()).toBe(true);
    });

    it('passes the work item id and the GitLab Duo command to the Duo action', () => {
      const props = findGenerateWithDuoButton().props();
      expect(props.resourceId).toBe('gid://gitlab/WorkItem/1');
      expect(props.command.agent.name).toBe(DUO_CHAT_AGENT_GITLAB_DUO);
      expect(props.command.agenticPrompt).toEqual(expect.any(String));
      expect(props.command.agenticPrompt).toContain('http://gdk.test/group/project/-/work_items/1');
      expect(props.trackingInfo).toEqual({ label: 'create_work_plan' });
    });

    describe('when Create manually is clicked', () => {
      beforeEach(() => {
        findCreateManuallyButton().vm.$emit('click');
      });

      it('emits "start-edit"', () => {
        expect(wrapper.emitted('start-edit')).toHaveLength(1);
      });
    });
  });

  describe('when the user cannot update', () => {
    beforeEach(() => {
      createComponent({ savedContent: '', canUpdate: false });
    });

    it('shows a read-only empty state with no actions', () => {
      expect(findEmptyState().text()).toContain("don't have permission");
      expect(findGenerateWithDuoButton().exists()).toBe(false);
      expect(findCreateManuallyButton().exists()).toBe(false);
    });
  });

  describe('when saved content exists', () => {
    beforeEach(() => {
      createComponent({
        savedContent: 'Some plan content',
        savedContentHtml: '<p data-sourcepos="1:1-1:17">Some plan content</p>',
      });
    });

    it('renders the backend-rendered HTML inside a GLFM container', () => {
      expect(findRenderedMarkdown().exists()).toBe(true);
      expect(findRenderedMarkdown().classes()).toContain('md');
      expect(findRenderedMarkdown().element.innerHTML).toContain('Some plan content');
    });

    it('calls renderGFM on mount', async () => {
      await nextTick();

      expect(renderGFM).toHaveBeenCalledWith(findRenderedMarkdown().element);
    });

    describe('when the content changes', () => {
      it('calls renderGFM again', async () => {
        await nextTick();

        expect(renderGFM).toHaveBeenCalledTimes(1);

        await wrapper.setProps({ savedContentHtml: '<p>Updated plan</p>' });
        await nextTick();

        expect(renderGFM).toHaveBeenCalledTimes(2);
        expect(renderGFM).toHaveBeenNthCalledWith(2, findRenderedMarkdown().element);
      });
    });

    describe('when the component is destroyed', () => {
      it('tears down the image lightbox for the rendered content', () => {
        const contentElement = findRenderedMarkdown().element;

        expect(destroyImageLightbox).not.toHaveBeenCalled();

        wrapper.destroy();

        expect(destroyImageLightbox).toHaveBeenCalledTimes(1);
        expect(destroyImageLightbox).toHaveBeenCalledWith(contentElement);
      });
    });
  });

  describe('when the async flow is generating the plan', () => {
    beforeEach(() => {
      createComponent({ canUpdate: true, savedContent: '', isFlowActive: true });
    });

    it('hides Generate so the user cannot start a competing Duo Chat session', () => {
      expect(findGenerateWithDuoButton().exists()).toBe(false);
    });

    it('keeps Create manually available', () => {
      expect(findCreateManuallyButton().exists()).toBe(true);
    });
  });

  describe('while a run is replacing a saved plan', () => {
    beforeEach(() => {
      createComponent({ canUpdate: true, savedContent: 'Old plan', isFlowActive: true });
    });

    it('hides the plan, so the panel does not read as though nothing is happening', () => {
      expect(findRenderedMarkdown().exists()).toBe(false);
    });

    it('shows a loader in its place', () => {
      expect(findLoadingIcon().exists()).toBe(true);
    });
  });

  describe('when async generation is enabled', () => {
    const findGenerateButton = () => wrapper.findComponentByTestId('panel-generate-button');

    beforeEach(() => {
      createComponent({ savedContent: '', canUpdate: true, canGenerateAsync: true });
    });

    it('offers Generate as a plain action rather than a Duo Chat hand-off', () => {
      expect(findGenerateButton().exists()).toBe(true);
      expect(findGenerateWithDuoButton().exists()).toBe(false);
    });

    it('asks the parent to start a run', () => {
      findGenerateButton().vm.$emit('click');

      expect(wrapper.emitted('generate')).toHaveLength(1);
    });
  });
});
