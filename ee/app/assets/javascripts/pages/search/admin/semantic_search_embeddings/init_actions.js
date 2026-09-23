import { initTestModelConfiguration } from './test_model_configuration';
import { initUpdateEmbeddingsRequestBatchSize } from './update_embeddings_request_batch_size';

export const initSemanticSearchEmbeddings = () => {
  initTestModelConfiguration();
  initUpdateEmbeddingsRequestBatchSize();
};
