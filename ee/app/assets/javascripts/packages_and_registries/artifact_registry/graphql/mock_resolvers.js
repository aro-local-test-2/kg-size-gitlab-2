// Runtime Apollo local resolvers standing in for reads the frontend still selects `@client`
// rather than against the schema, so the read flow is exercisable in a browser ahead of the
// frontend being wired to the real field, per doc/development/fe_guide/graphql.md ("Mocking API
// response with local Apollo cache"). The precedent for shipping a runtime mock merged is
// ee/app/assets/javascripts/cd/graphql/mock_resolvers.js.
//
// The single-manifest read and its referrers connection are all that is left. The GraphQL schema
// owns both fields and every manifest type, so there is no local typedef: a client `extend type`
// of a field the schema already declares fails the Apollo schema build. Apollo resolves the two
// `@client` fields against the server schema plus this resolver, the way
// ee/.../cd/graphql/mock_resolvers.js does. To remove once the frontend reads the real fields:
//   1. delete this file,
//   2. drop the `mockResolvers` argument in repositories/index.js,
//   3. remove the `@client` directive from graphql/queries/get_manifest.query.graphql and from
//      graphql/queries/get_manifest_referrers.query.graphql,
//   4. delete the graphql/queries_spec.js document checks, which exist only to police the
//      `@client` split while it lasts.
import {
  TYPENAME_ARTIFACT_REGISTRY_MANIFEST_CONNECTION,
  TYPENAME_ARTIFACT_REGISTRY_MANIFEST_DETAILS,
  TYPENAME_ARTIFACT_REGISTRY_REPOSITORY_DETAILS,
} from '../constants';
import { isContainerFormat } from '../utils';
import { manifestLadderFor } from './mock_artifacts';

// Pauses before resolving, so a consuming view renders its loading state.
const delay = () =>
  new Promise((resolve) => {
    const MOCK_LATENCY_MS = 500;

    setTimeout(resolve, MOCK_LATENCY_MS);
  });

export const mockResolvers = {
  [TYPENAME_ARTIFACT_REGISTRY_REPOSITORY_DETAILS]: {
    manifest: async ({ format }, { digest, artifactId }) => {
      if (!isContainerFormat(format)) return null;

      await delay();

      // Scoped to this image, so a URL pairing one image with another's digest resolves null.
      const found = manifestLadderFor(artifactId).find((manifest) => manifest.digest === digest);

      if (!found) return null;

      // Copied, so a caller writing to the answer cannot reach the ladder row behind it.
      return { ...found };
    },
  },
  [TYPENAME_ARTIFACT_REGISTRY_MANIFEST_DETAILS]: {
    referrers: ({ referrerRows = [] }, { first }) => {
      const nodes = first == null ? referrerRows : referrerRows.slice(0, first);

      return {
        __typename: TYPENAME_ARTIFACT_REGISTRY_MANIFEST_CONNECTION,
        nodes,
        pageInfo: {
          __typename: 'PageInfo',
          hasNextPage: nodes.length < referrerRows.length,
          hasPreviousPage: false,
          startCursor: null,
          endCursor: null,
        },
      };
    },
  },
};
