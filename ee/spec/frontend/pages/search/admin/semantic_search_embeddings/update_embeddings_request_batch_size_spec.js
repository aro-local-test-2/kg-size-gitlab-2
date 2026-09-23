import MockAdapter from 'axios-mock-adapter';
import { setHTMLFixture, resetHTMLFixture } from 'helpers/fixtures';
import waitForPromises from 'helpers/wait_for_promises';
import { createAlert } from '~/alert';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_OK, HTTP_STATUS_UNPROCESSABLE_ENTITY } from '~/lib/utils/http_status';
import { initUpdateEmbeddingsRequestBatchSize } from 'ee/pages/search/admin/semantic_search_embeddings/update_embeddings_request_batch_size';

jest.mock('~/alert');

describe('initUpdateEmbeddingsRequestBatchSize', () => {
  let mockAxios;

  const UPDATE_PATH =
    '/admin/application_settings/search/semantic_search_embeddings/code/update_embeddings_request_batch_size';

  // form.action resolves the attribute against the document location.
  const UPDATE_URL = `${window.location.origin}${UPDATE_PATH}`;

  const createBatchSizeFixture = ({ currentDisabled = false } = {}) => `
    <span id="semantic-search-current-model-batch-size-display">10</span>
    <span id="semantic-search-next-model-batch-size-display">20</span>
    <input id="semantic-search-embeddings-batch-size-input" value="10" ${
      currentDisabled ? 'disabled' : ''
    } />
    <form action="${UPDATE_PATH}" method="put">
      <input
        name="current_model_embeddings_request_batch_size"
        value="15"
        placeholder="20 (Default)"
      />
      <button
        id="update-current-model-batch-size-button"
        type="button"
      >Update batch size</button>
    </form>
    <form action="${UPDATE_PATH}" method="put">
      <input
        name="next_model_embeddings_request_batch_size"
        value="25"
        placeholder="30 (Default)"
      />
      <button
        id="update-next-model-batch-size-button"
        type="button"
      >Update batch size</button>
    </form>
  `;

  const findCurrentButton = () => document.getElementById('update-current-model-batch-size-button');
  const findNextButton = () => document.getElementById('update-next-model-batch-size-button');
  const findCurrentDisplay = () =>
    document.getElementById('semantic-search-current-model-batch-size-display');
  const findNextDisplay = () =>
    document.getElementById('semantic-search-next-model-batch-size-display');
  const findSyncInput = () =>
    document.getElementById('semantic-search-embeddings-batch-size-input');

  beforeEach(() => {
    setHTMLFixture(createBatchSizeFixture());
    mockAxios = new MockAdapter(axios);
    initUpdateEmbeddingsRequestBatchSize();
  });

  afterEach(() => {
    resetHTMLFixture();
    mockAxios.restore();
  });

  it('does not throw when the buttons are missing', () => {
    resetHTMLFixture();
    setHTMLFixture('<div></div>');

    expect(() => initUpdateEmbeddingsRequestBatchSize()).not.toThrow();
  });

  describe('current model button', () => {
    it('disables the button and shows updating text on click', async () => {
      mockAxios.onPut(UPDATE_URL).replyOnce(HTTP_STATUS_OK, { embeddings_request_batch_size: 15 });

      findCurrentButton().click();

      expect(findCurrentButton().disabled).toBe(true);
      expect(findCurrentButton().innerText).toBe('Updating...');

      await waitForPromises();
    });

    it('sends the batch size and for_next_model=false', async () => {
      mockAxios.onPut(UPDATE_URL).replyOnce(HTTP_STATUS_OK, { embeddings_request_batch_size: 15 });

      findCurrentButton().click();
      await waitForPromises();

      const formData = mockAxios.history.put[0].data;
      expect(formData.get('batch_size')).toBe('15');
      expect(formData.get('for_next_model')).toBe('false');
      expect(formData.get('current_model_embeddings_request_batch_size')).toBeNull();
    });

    describe('on success', () => {
      beforeEach(async () => {
        mockAxios
          .onPut(UPDATE_URL)
          .replyOnce(HTTP_STATUS_OK, { embeddings_request_batch_size: 128 });
        findCurrentButton().click();
        await waitForPromises();
      });

      it('updates the display text', () => {
        expect(findCurrentDisplay().textContent).toBe('128');
      });

      it('keeps the editable input in sync', () => {
        expect(findSyncInput().value).toBe('128');
      });

      it('shows a success alert', () => {
        expect(createAlert).toHaveBeenCalledWith(expect.objectContaining({ variant: 'success' }));
      });

      it('re-enables the button and restores its text', () => {
        expect(findCurrentButton().disabled).toBe(false);
        expect(findCurrentButton().innerText).toBe('Update batch size');
      });
    });

    describe('when the batch size is nil', () => {
      beforeEach(async () => {
        mockAxios
          .onPut(UPDATE_URL)
          .replyOnce(HTTP_STATUS_OK, { embeddings_request_batch_size: null });
        findCurrentButton().click();
        await waitForPromises();
      });

      it('falls back to the input placeholder for the display text', () => {
        expect(findCurrentDisplay().textContent).toBe('20 (Default)');
      });

      it('clears the editable input so it shows its own placeholder', () => {
        expect(findSyncInput().value).toBe('');
      });
    });

    describe('when the editable input is disabled', () => {
      beforeEach(async () => {
        resetHTMLFixture();
        setHTMLFixture(createBatchSizeFixture({ currentDisabled: true }));
        initUpdateEmbeddingsRequestBatchSize();
        mockAxios
          .onPut(UPDATE_URL)
          .replyOnce(HTTP_STATUS_OK, { embeddings_request_batch_size: 128 });
        findCurrentButton().click();
        await waitForPromises();
      });

      it('does not sync the disabled input', () => {
        expect(findSyncInput().value).toBe('10');
      });
    });
  });

  describe('next model button', () => {
    it('sends the batch size and for_next_model=true', async () => {
      mockAxios.onPut(UPDATE_URL).replyOnce(HTTP_STATUS_OK, { embeddings_request_batch_size: 25 });

      findNextButton().click();
      await waitForPromises();

      const formData = mockAxios.history.put[0].data;
      expect(formData.get('batch_size')).toBe('25');
      expect(formData.get('for_next_model')).toBe('true');
      expect(formData.get('next_model_embeddings_request_batch_size')).toBeNull();
    });

    describe('on success', () => {
      beforeEach(async () => {
        mockAxios
          .onPut(UPDATE_URL)
          .replyOnce(HTTP_STATUS_OK, { embeddings_request_batch_size: 256 });
        findNextButton().click();
        await waitForPromises();
      });

      it('updates the next model display text', () => {
        expect(findNextDisplay().textContent).toBe('256');
      });

      it('does not touch the current model editable input', () => {
        expect(findSyncInput().value).toBe('10');
      });

      it('shows a success alert', () => {
        expect(createAlert).toHaveBeenCalledWith(expect.objectContaining({ variant: 'success' }));
      });
    });

    describe('when the batch size is nil', () => {
      beforeEach(async () => {
        mockAxios
          .onPut(UPDATE_URL)
          .replyOnce(HTTP_STATUS_OK, { embeddings_request_batch_size: null });
        findNextButton().click();
        await waitForPromises();
      });

      it('falls back to the input placeholder for the display text', () => {
        expect(findNextDisplay().textContent).toBe('30 (Default)');
      });
    });
  });

  describe('on a failed update', () => {
    beforeEach(async () => {
      mockAxios.onPut(UPDATE_URL).replyOnce(HTTP_STATUS_UNPROCESSABLE_ENTITY, {
        message: 'Batch size too large',
      });
      findCurrentButton().click();
      await waitForPromises();
    });

    it('shows an error alert with the server message', () => {
      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({
          message: expect.stringMatching(/Update failed.*Batch size too large/),
        }),
      );
    });

    it('re-enables the button', () => {
      expect(findCurrentButton().disabled).toBe(false);
    });
  });

  describe('on a non-JSON response (e.g. user has been signed out)', () => {
    beforeEach(async () => {
      mockAxios.onPut(UPDATE_URL).replyOnce(HTTP_STATUS_OK, '<html>Login page</html>');
      findCurrentButton().click();
      await waitForPromises();
    });

    it('shows an unexpected server response alert', () => {
      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({
          message: expect.stringContaining('Unexpected server response'),
        }),
      );
    });

    it('re-enables the button', () => {
      expect(findCurrentButton().disabled).toBe(false);
    });
  });

  describe('on a network error', () => {
    beforeEach(async () => {
      mockAxios.onPut(UPDATE_URL).networkError();
      findCurrentButton().click();
      await waitForPromises();
    });

    it('shows an error alert', () => {
      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({ message: expect.any(String) }),
      );
    });

    it('re-enables the button', () => {
      expect(findCurrentButton().disabled).toBe(false);
    });
  });
});
