import {
  TYPENAME_ARTIFACT_REGISTRY_IMAGE,
  TYPENAME_ARTIFACT_REGISTRY_MANIFEST_DETAILS,
  TYPENAME_ARTIFACT_REGISTRY_MAVEN_PACKAGE,
  TYPENAME_ARTIFACT_REGISTRY_MAVEN_PACKAGE_DETAILS,
  TYPENAME_ARTIFACT_REGISTRY_NPM_PACKAGE,
  TYPENAME_ARTIFACT_REGISTRY_NPM_PACKAGE_DETAILS,
  TYPENAME_ARTIFACT_REGISTRY_PACKAGE,
  TYPENAME_ARTIFACT_REGISTRY_PACKAGE_DETAILS,
  TYPENAME_ARTIFACT_REGISTRY_REPOSITORY,
  TYPENAME_ARTIFACT_REGISTRY_REPOSITORY_DETAILS,
  TYPENAME_ARTIFACT_REGISTRY_UPSTREAM_REPOSITORY_ASSOCIATION,
  TYPENAME_ARTIFACT_REGISTRY_UPSTREAM_REPOSITORY_SUMMARY,
  TYPENAME_ARTIFACT_REGISTRY_VERSION_DETAILS,
  TYPENAME_ORGANIZATION,
} from '../constants';

export const possibleTypes = {
  [TYPENAME_ARTIFACT_REGISTRY_PACKAGE]: [
    TYPENAME_ARTIFACT_REGISTRY_MAVEN_PACKAGE,
    TYPENAME_ARTIFACT_REGISTRY_NPM_PACKAGE,
  ],
  [TYPENAME_ARTIFACT_REGISTRY_PACKAGE_DETAILS]: [
    TYPENAME_ARTIFACT_REGISTRY_MAVEN_PACKAGE_DETAILS,
    TYPENAME_ARTIFACT_REGISTRY_NPM_PACKAGE_DETAILS,
  ],
};

const ARTIFACT_CONNECTION_POLICY = {
  keyArgs: [],
  merge: (_, incoming) => incoming,
};

const SORTED_ARTIFACT_CONNECTION_POLICY = {
  ...ARTIFACT_CONNECTION_POLICY,
  keyArgs: ['sort'],
};

const MANIFEST_CONNECTION_POLICY = {
  ...SORTED_ARTIFACT_CONNECTION_POLICY,
  keyArgs: ['sort', 'includeReferrers'],
};

export const typePolicies = {
  [TYPENAME_ARTIFACT_REGISTRY_REPOSITORY]: {
    keyFields: ['name'],
  },
  [TYPENAME_ARTIFACT_REGISTRY_REPOSITORY_DETAILS]: {
    keyFields: ['name'],
    fields: {
      images: ARTIFACT_CONNECTION_POLICY,
      packages: ARTIFACT_CONNECTION_POLICY,
      upstreamRepositories: {
        merge: (_, incoming) => incoming,
      },
      userPermissions: {
        merge: true,
      },
    },
  },
  [TYPENAME_ARTIFACT_REGISTRY_UPSTREAM_REPOSITORY_ASSOCIATION]: {
    keyFields: ['id'],
  },
  [TYPENAME_ARTIFACT_REGISTRY_UPSTREAM_REPOSITORY_SUMMARY]: {
    keyFields: false,
  },
  // `versions` is only ever selected under the single-package read, which returns the detail
  // union, so the pager's page-merge policy hangs off the detail types Apollo keys the cache by.
  [TYPENAME_ARTIFACT_REGISTRY_MAVEN_PACKAGE_DETAILS]: {
    fields: {
      versions: SORTED_ARTIFACT_CONNECTION_POLICY,
    },
  },
  [TYPENAME_ARTIFACT_REGISTRY_NPM_PACKAGE_DETAILS]: {
    fields: {
      versions: SORTED_ARTIFACT_CONNECTION_POLICY,
    },
  },
  [TYPENAME_ARTIFACT_REGISTRY_IMAGE]: {
    fields: {
      manifests: MANIFEST_CONNECTION_POLICY,
    },
  },
  [TYPENAME_ARTIFACT_REGISTRY_VERSION_DETAILS]: {
    fields: {
      files: ARTIFACT_CONNECTION_POLICY,
    },
  },
  [TYPENAME_ARTIFACT_REGISTRY_MANIFEST_DETAILS]: {
    fields: {
      referrers: ARTIFACT_CONNECTION_POLICY,
    },
  },
  [TYPENAME_ORGANIZATION]: {
    fields: {
      // The filters and the sort are applied server-side, so each combination is a
      // distinct result rather than a view of one cached list. Without keying on them, a
      // re-sorted page overwrites the entry another one wrote.
      artifactRegistryRepositories: {
        keyArgs: ['format', 'formats', 'kind', 'kinds', 'sort'],
      },
    },
  },
};
