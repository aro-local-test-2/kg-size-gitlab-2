import { nextTick } from 'vue';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import FileAttachments from 'ee/ai/duo_agentic_chat/components/prompt_composer/file_attachments.vue';
import AttachmentPreviews from 'ee/ai/duo_agentic_chat/components/prompt_composer/attachment_previews.vue';
import { readFileAsDataURL } from '~/lib/utils/file_utility';

// Stubbed so the base64 payload is deterministic rather than depending on jsdom's
// FileReader actually decoding the synthetic Blobs below.
jest.mock('~/lib/utils/file_utility');

const BASE64 = 'aGVsbG8=';

const createImageFile = ({ name = 'shot.png', type = 'image/png', size = 1024 } = {}) => {
  const file = new File(['x'], name, { type });
  // `size` is read-only on File, so it is redefined rather than passed in.
  Object.defineProperty(file, 'size', { value: size });
  return file;
};

const fileDrag = (files = []) => ({
  dataTransfer: { types: ['Files'], files },
  preventDefault: jest.fn(),
});

describe('FileAttachments', () => {
  let wrapper;

  const createComponent = ({
    attachments = [],
    disabled = false,
    enabled = true,
    ...options
  } = {}) => {
    wrapper = mountExtended(FileAttachments, {
      propsData: { attachments, disabled },
      provide: { glFeatures: { dapWebChatFileAttachments: enabled } },
      ...options,
    });
  };

  const findRoot = () => wrapper.findByTestId('file-attachments');
  const findFileInput = () => wrapper.findByTestId('attachment-file-input');
  const findPreviews = () => wrapper.findComponent(AttachmentPreviews);
  const findDropOverlay = () => wrapper.findByTestId('attachment-drop-overlay');
  const findErrors = () => wrapper.findAllComponentsByTestId('attachment-error');

  // `addFiles` is driven directly because jsdom does not let a FileList be assigned
  // to a file input's `files` property.
  const attach = async (files) => {
    await wrapper.vm.addFiles(files);
    await nextTick();
  };

  // What the parent would hold after acting on the `add` events emitted so far.
  const addedAttachments = () => (wrapper.emitted('add') ?? []).flatMap(([batch]) => batch);

  beforeEach(() => {
    readFileAsDataURL.mockResolvedValue(`data:image/png;base64,${BASE64}`);
  });

  describe('picking files', () => {
    it('opens the file picker when the composer requests it', () => {
      createComponent();
      const clickSpy = jest.spyOn(wrapper.vm.$refs.fileInput, 'click');

      wrapper.vm.openFilePicker();

      expect(clickSpy).toHaveBeenCalled();
    });

    it('restricts the picker to the supported image types', () => {
      createComponent();

      expect(findFileInput().attributes('accept')).toBe('image/png,image/jpeg,image/webp');
      expect(findFileInput().attributes('multiple')).toBeDefined();
    });
  });

  describe('previews', () => {
    it('hands the attachments it was given to the previews', () => {
      const attachments = [
        { id: 'a-1', filename: 'a.png', byteSize: 1 },
        { id: 'a-2', filename: 'b.png', byteSize: 2 },
      ];
      createComponent({ attachments });

      expect(findPreviews().props('attachments')).toEqual(attachments);
    });

    // The draft owns the attachments, so removal is a request rather than a local edit.
    it('asks for a removal when the preview requests one', () => {
      createComponent({ attachments: [{ id: 'a-1', filename: 'a.png', byteSize: 1 }] });

      findPreviews().vm.$emit('remove', 'a-1');

      expect(wrapper.emitted('remove')).toEqual([['a-1']]);
    });

    it('disables the previews when attaching is not allowed', () => {
      createComponent({ disabled: true });

      expect(findPreviews().props('disabled')).toBe(true);
    });
  });

  describe('accepting files', () => {
    it('offers the accepted files to the composer', async () => {
      createComponent();

      await attach([createImageFile({ name: 'a.png' }), createImageFile({ name: 'b.png' })]);

      expect(addedAttachments().map((a) => a.filename)).toEqual(['a.png', 'b.png']);
    });

    it('says nothing when every file was rejected', async () => {
      createComponent();

      await attach([createImageFile({ name: 'notes.pdf', type: 'application/pdf' })]);

      expect(wrapper.emitted('add')).toBeUndefined();
    });

    it('counts the attachments it already has against the limits', async () => {
      // Five is the cap, so a sixth has nowhere to go.
      const existing = Array.from({ length: 5 }, (_, i) => ({
        id: `a-${i}`,
        filename: `${i}.png`,
        byteSize: 1,
      }));
      createComponent({ attachments: existing });

      await attach([createImageFile({ name: 'sixth.png' })]);

      expect(wrapper.emitted('add')).toBeUndefined();
      expect(findErrors().at(0).text()).toContain('You can attach up to 5 images');
    });
  });

  describe('errors', () => {
    it('surfaces a dismissible warning for a rejected file', async () => {
      createComponent();

      await attach([createImageFile({ name: 'notes.pdf', type: 'application/pdf' })]);

      expect(findErrors()).toHaveLength(1);
      expect(findErrors().at(0).text()).toContain('notes.pdf was not attached');

      findErrors().at(0).vm.$emit('dismiss');
      await nextTick();

      expect(findErrors()).toHaveLength(0);
    });

    it('still accepts the usable files from a mixed batch', async () => {
      createComponent();

      await attach([
        createImageFile({ name: 'good.png' }),
        createImageFile({ name: 'bad.pdf', type: 'application/pdf' }),
      ]);

      expect(addedAttachments().map((a) => a.filename)).toEqual(['good.png']);
      expect(findErrors()).toHaveLength(1);
    });

    // The notices are keyed by their text, so a repeat would collide as a key and
    // dismiss with its twin. Pasted images share a generated filename, so a batch
    // can produce the same message twice.
    it('shows one warning when two files are rejected identically', async () => {
      createComponent();
      const rejected = () => createImageFile({ name: 'image-1.pdf', type: 'application/pdf' });

      await attach([rejected(), rejected()]);

      expect(findErrors()).toHaveLength(1);
    });

    it('explains why a draft holding images cannot be queued', async () => {
      createComponent();

      wrapper.vm.rejectQueueing();
      await nextTick();

      expect(findErrors().at(0).text()).toContain('Images cannot be queued');
    });

    it('drops the warnings once the composer has sent the draft', async () => {
      createComponent();
      await attach([createImageFile({ name: 'notes.pdf', type: 'application/pdf' })]);

      wrapper.vm.clearErrors();
      await nextTick();

      expect(findErrors()).toHaveLength(0);
    });
  });

  describe('pasting', () => {
    it('takes a pasted image and stops the default paste', async () => {
      createComponent();
      const event = {
        clipboardData: { files: [createImageFile({ name: 'shot.png' })] },
        preventDefault: jest.fn(),
      };

      wrapper.vm.onPaste(event);
      await waitForPromises();

      expect(event.preventDefault).toHaveBeenCalled();
      expect(addedAttachments()).toHaveLength(1);
    });

    it('leaves a text-only paste alone', () => {
      createComponent();
      const event = { clipboardData: { files: [] }, preventDefault: jest.fn() };

      wrapper.vm.onPaste(event);

      expect(event.preventDefault).not.toHaveBeenCalled();
    });

    // Rich text can carry a file alongside the text. Claiming that paste would
    // lose the text, which is worse than not taking a file we cannot use anyway.
    it('leaves a paste carrying no supported image alone', () => {
      createComponent();
      const event = {
        clipboardData: { files: [createImageFile({ name: 'a.pdf', type: 'application/pdf' })] },
        preventDefault: jest.fn(),
      };

      wrapper.vm.onPaste(event);

      expect(event.preventDefault).not.toHaveBeenCalled();
    });

    it('reports an unsupported file pasted alongside an image', async () => {
      createComponent();
      const event = {
        clipboardData: {
          files: [
            createImageFile({ name: 'shot.png' }),
            createImageFile({ name: 'a.pdf', type: 'application/pdf' }),
          ],
        },
        preventDefault: jest.fn(),
      };

      wrapper.vm.onPaste(event);
      await waitForPromises();

      expect(addedAttachments()).toHaveLength(1);
      expect(findErrors().at(0).text()).toContain('a.pdf was not attached');
    });
  });

  describe('drag and drop', () => {
    it('shows an overlay while files are dragged over the composer', async () => {
      createComponent();

      expect(findDropOverlay().exists()).toBe(false);

      wrapper.vm.onDragEnter(fileDrag());
      await nextTick();

      expect(findDropOverlay().exists()).toBe(true);
    });

    it('keeps the overlay up until the last nested dragleave', async () => {
      createComponent();

      wrapper.vm.onDragEnter(fileDrag());
      wrapper.vm.onDragEnter(fileDrag());
      wrapper.vm.onDragLeave(fileDrag());
      await nextTick();

      expect(findDropOverlay().exists()).toBe(true);

      wrapper.vm.onDragLeave(fileDrag());
      await nextTick();

      expect(findDropOverlay().exists()).toBe(false);
    });

    it('ignores drags that are not carrying files', async () => {
      createComponent();

      wrapper.vm.onDragEnter({ dataTransfer: { types: ['text/plain'] } });
      await nextTick();

      expect(findDropOverlay().exists()).toBe(false);
    });

    it('preventDefault on dragover, so the browser does not navigate to the file', () => {
      createComponent();
      const event = fileDrag();

      wrapper.vm.onDragOver(event);

      expect(event.preventDefault).toHaveBeenCalled();
    });

    it('takes dropped images and hides the overlay', async () => {
      createComponent();
      wrapper.vm.onDragEnter(fileDrag());
      const event = fileDrag([createImageFile({ name: 'dropped.png' })]);

      wrapper.vm.onDrop(event);
      await waitForPromises();

      expect(event.preventDefault).toHaveBeenCalled();
      expect(findDropOverlay().exists()).toBe(false);
      expect(addedAttachments().map((a) => a.filename)).toEqual(['dropped.png']);
    });

    // Matches the picker: a rejected drop says so instead of doing nothing.
    it('warns about a dropped file it cannot take, and takes the rest', async () => {
      createComponent();
      const event = fileDrag([
        createImageFile({ name: 'good.png' }),
        createImageFile({ name: 'notes.pdf', type: 'application/pdf' }),
      ]);

      wrapper.vm.onDrop(event);
      await waitForPromises();

      expect(addedAttachments().map((a) => a.filename)).toEqual(['good.png']);
      expect(findErrors().at(0).text()).toContain('notes.pdf was not attached');
    });
  });

  // Every route a file can take is refused, rather than only the removal buttons being
  // disabled, which would leave the user holding an attachment they cannot take back.
  describe('when disabled', () => {
    it('ignores files pushed at it', async () => {
      createComponent({ disabled: true });

      await attach([createImageFile({ name: 'a.png' })]);

      expect(wrapper.emitted('add')).toBeUndefined();
    });

    it('does not open the file picker', () => {
      createComponent({ disabled: true });
      const clickSpy = jest.spyOn(wrapper.vm.$refs.fileInput, 'click');

      wrapper.vm.openFilePicker();

      expect(clickSpy).not.toHaveBeenCalled();
    });

    it('leaves a pasted image to the browser', () => {
      createComponent({ disabled: true });
      const event = {
        clipboardData: { files: [createImageFile({ name: 'a.png' })] },
        preventDefault: jest.fn(),
      };

      wrapper.vm.onPaste(event);

      expect(event.preventDefault).not.toHaveBeenCalled();
    });

    it('does not show the drop overlay', async () => {
      createComponent({ disabled: true });

      wrapper.vm.onDragEnter(fileDrag());
      await nextTick();

      expect(findDropOverlay().exists()).toBe(false);
    });

    // The draft can outlive the chat becoming unavailable, and what it is holding
    // still has to be visible.
    it('keeps showing the attachments it already has', () => {
      createComponent({ disabled: true, attachments: [{ id: 'a-1', filename: 'a.png' }] });

      expect(findPreviews().props('attachments')).toHaveLength(1);
    });
  });

  describe('when dapWebChatFileAttachments is disabled', () => {
    it('renders nothing at all', () => {
      createComponent({ enabled: false });

      expect(findRoot().exists()).toBe(false);
      expect(findFileInput().exists()).toBe(false);
    });

    it('ignores files pushed at it', async () => {
      createComponent({ enabled: false });

      await attach([createImageFile({ name: 'a.png' })]);

      expect(wrapper.emitted('add')).toBeUndefined();
    });

    it('leaves a pasted image to the browser', () => {
      createComponent({ enabled: false });
      const event = {
        clipboardData: { files: [createImageFile({ name: 'a.png' })] },
        preventDefault: jest.fn(),
      };

      wrapper.vm.onPaste(event);

      expect(event.preventDefault).not.toHaveBeenCalled();
    });

    it('does not show the drop overlay', async () => {
      createComponent({ enabled: false });

      wrapper.vm.onDragEnter(fileDrag());
      await nextTick();

      expect(findDropOverlay().exists()).toBe(false);
    });
  });
});
