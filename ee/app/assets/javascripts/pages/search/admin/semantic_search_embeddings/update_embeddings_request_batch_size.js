import { createAlert } from '~/alert';
import axios from '~/lib/utils/axios_utils';
import { sprintf, s__ } from '~/locale';

const EMBEDDING_MODEL_FORM_BATCH_SIZE_INPUT_ID = 'semantic-search-embeddings-batch-size-input';

const MODEL_FORMS = {
  currentModel: {
    buttonId: 'update-current-model-batch-size-button',
    fieldName: 'current_model_embeddings_request_batch_size',
    displayId: 'semantic-search-current-model-batch-size-display',
    forNextModel: false,
  },
  nextModel: {
    buttonId: 'update-next-model-batch-size-button',
    fieldName: 'next_model_embeddings_request_batch_size',
    displayId: 'semantic-search-next-model-batch-size-display',
    forNextModel: true,
  },
};

const initBatchSizeButton = ({ buttonId, fieldName, displayId, forNextModel }) => {
  const button = document.getElementById(buttonId);
  if (!button) return;

  button.addEventListener('click', (event) => {
    event.preventDefault();

    const { currentTarget } = event;
    const normalText = currentTarget.innerText;

    currentTarget.disabled = true;
    currentTarget.innerText = s__('SemanticSearch|Updating...');

    const form = currentTarget.closest('form');
    const requestPath = form.action;
    const formData = new FormData(form);

    const batchSize = formData.get(fieldName);
    formData.delete(fieldName);
    formData.append('batch_size', batchSize);
    formData.append('for_next_model', forNextModel);

    axios
      .put(requestPath, formData)
      .then(({ data }) => {
        if (typeof data !== 'object' || data === null) {
          throw new Error(
            s__(
              'SemanticSearch|Unexpected server response. Please refresh the page and try again.',
            ),
          );
        }

        const displayText = document.getElementById(displayId);
        if (displayText) {
          // A nil batch size means the default is in use,
          // so we need to get the value from the input's placeholder.
          displayText.textContent =
            data.embeddings_request_batch_size ??
            form.querySelector(`[name="${fieldName}"]`)?.placeholder ??
            '';
        }

        // When the current model's batch size changes,
        // keep batch size field in the embedding model form in sync unless it is disabled.
        if (!forNextModel) {
          const embeddingModelFormBatchSizeInput = document.getElementById(
            EMBEDDING_MODEL_FORM_BATCH_SIZE_INPUT_ID,
          );
          if (embeddingModelFormBatchSizeInput && !embeddingModelFormBatchSizeInput.disabled) {
            embeddingModelFormBatchSizeInput.value = data.embeddings_request_batch_size;
          }
        }

        createAlert({
          message: s__('SemanticSearch|Batch size updated.'),
          variant: 'success',
        });
      })
      .catch((error) => {
        const serverMessage = error.response?.data?.message;
        const message = serverMessage
          ? sprintf(s__('SemanticSearch|Update failed: "%{serverMessage}"'), { serverMessage })
          : error.message || String(error);
        createAlert({ message });
      })
      .finally(() => {
        currentTarget.disabled = false;
        currentTarget.innerText = normalText;
      });
  });
};

export const initUpdateEmbeddingsRequestBatchSize = () => {
  Object.values(MODEL_FORMS).forEach((modelForm) => initBatchSizeButton(modelForm));
};
