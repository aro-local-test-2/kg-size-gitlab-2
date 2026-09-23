import Vue from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { createAlert } from '~/alert';
import deleteArtifactMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/delete_artifact.mutation.graphql';
import deleteVersionMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/delete_version.mutation.graphql';
import deleteManifestMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/delete_manifest.mutation.graphql';
import getRepositoryDetailQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_detail.query.graphql';
import { executeDeleteMutation } from 'ee/packages_and_registries/artifact_registry/graphql/utils/delete_mutation';
import {
  mockDeleteArtifactResponse,
  mockDeleteVersionResponse,
  mockDeleteManifestResponse,
} from '../../mock_data';

jest.mock('~/alert');

Vue.use(VueApollo);

describe('executeDeleteMutation', () => {
  const input = { name: 'payment-core', id: 'pkg-1' };

  let apollo;

  const request = (options = {}) =>
    executeDeleteMutation(apollo, { mutation: deleteArtifactMutation, input, ...options });

  beforeEach(() => {
    apollo = { mutate: jest.fn().mockResolvedValue(mockDeleteArtifactResponse()) };
  });

  it('sends the document the caller named, with its input', async () => {
    await request();

    expect(apollo.mutate).toHaveBeenCalledWith({
      mutation: deleteArtifactMutation,
      variables: { input },
    });
  });

  it('forwards any further mutation options', async () => {
    await request({ refetchQueries: [getRepositoryDetailQuery], awaitRefetchQueries: true });

    expect(apollo.mutate).toHaveBeenCalledWith(
      expect.objectContaining({
        refetchQueries: [getRepositoryDetailQuery],
        awaitRefetchQueries: true,
      }),
    );
  });

  it('reports acceptance and raises no alert when the payload is clean', async () => {
    await expect(request()).resolves.toBe(true);
    expect(createAlert).not.toHaveBeenCalled();
  });

  it('surfaces the errors the payload carries, joined into one message', async () => {
    apollo.mutate.mockResolvedValue(
      mockDeleteArtifactResponse({ errors: ['Artifact not found.', 'Try again.'] }),
    );

    await expect(request()).resolves.toBe(false);
    expect(createAlert).toHaveBeenCalledWith({ message: 'Artifact not found. Try again.' });
  });

  it('reports a failed request as a page-level alert', async () => {
    const error = new Error('Artifact Registry is down');
    apollo.mutate.mockRejectedValue(error);

    await expect(request()).resolves.toBe(false);
    expect(createAlert).toHaveBeenCalledWith({
      message: 'Something went wrong. Please try again.',
      error,
      captureError: true,
    });
  });

  describe('over a second document', () => {
    it('reads the payload back under that document’s own alias', async () => {
      apollo.mutate.mockResolvedValue(mockDeleteVersionResponse());

      await expect(
        executeDeleteMutation(apollo, { mutation: deleteVersionMutation, input }),
      ).resolves.toBe(true);
      expect(apollo.mutate).toHaveBeenCalledWith({
        mutation: deleteVersionMutation,
        variables: { input },
      });
    });

    it('surfaces the errors that payload carries', async () => {
      apollo.mutate.mockResolvedValue(
        mockDeleteVersionResponse({ errors: ['Version not found.'] }),
      );

      await expect(
        executeDeleteMutation(apollo, { mutation: deleteVersionMutation, input }),
      ).resolves.toBe(false);
      expect(createAlert).toHaveBeenCalledWith({ message: 'Version not found.' });
    });
  });

  describe('over a real client', () => {
    const overApollo = (mutation, handler) =>
      executeDeleteMutation(createMockApollo([[mutation, handler]]).defaultClient, {
        mutation,
        input,
      });

    it.each([
      ['artifact', deleteArtifactMutation, mockDeleteArtifactResponse],
      ['version', deleteVersionMutation, mockDeleteVersionResponse],
      ['manifest', deleteManifestMutation, mockDeleteManifestResponse],
    ])('derives the %s payload key from the document', async (_, mutation, response) => {
      const handler = jest.fn().mockResolvedValue(response());

      await expect(overApollo(mutation, handler)).resolves.toBe(true);
      expect(handler).toHaveBeenCalledWith({ input });
      expect(createAlert).not.toHaveBeenCalled();
    });
  });
});
