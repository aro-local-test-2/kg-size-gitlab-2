import {
  TYPENAME_ARTIFACT_REGISTRY_REPOSITORY,
  TYPENAME_ARTIFACT_REGISTRY_REPOSITORY_DETAILS,
  TYPENAME_ORGANIZATION,
} from '../../constants';

// Evicts the connection field itself rather than one keyed entry. The field is cached
// per filter and sort argument variant, so dropping it by name alone is what clears
// every variant; a keyed eviction would leave a filtered or sorted view serving a
// stale page.
const evictRepositoriesField = (cache, organizationGid) =>
  cache.evict({
    id: cache.identify({ __typename: TYPENAME_ORGANIZATION, id: organizationGid }),
    fieldName: 'artifactRegistryRepositories',
  });

const evictRepositoryDetailsEntry = (cache, name) => {
  cache.evict({
    id: cache.identify({ __typename: TYPENAME_ARTIFACT_REGISTRY_REPOSITORY_DETAILS, name }),
  });
  cache.gc();
};

export const evictRepositoriesList =
  (organizationGid) =>
  (cache, { data }) => {
    if (data.createRepository.errors.length) return;

    evictRepositoriesField(cache, organizationGid);
    cache.gc();
  };

// The repository entity goes too, not just the list: the cache keys it on `name` (see
// cache_config.js), so a cached entity would outlive the repository and let the detail route
// read it back as though it still existed.
//
// Both typenames, because the list and the detail read return unrelated types and the detail
// route reads the entry the list never wrote.
export const evictDeletedRepository =
  (organizationGid, name) =>
  (cache, { data }) => {
    if (data.deleteRepository.errors.length) return;

    [TYPENAME_ARTIFACT_REGISTRY_REPOSITORY, TYPENAME_ARTIFACT_REGISTRY_REPOSITORY_DETAILS].forEach(
      (__typename) => cache.evict({ id: cache.identify({ __typename, name }) }),
    );
    evictRepositoriesField(cache, organizationGid);
    cache.gc();
  };

// The update payload is typed `ArtifactRegistryRepository`, so Apollo's normalization patches
// the list's entry and leaves the detail entry holding the old values. Evicting it makes the
// next detail read a miss rather than a cache-first render of stale text.
//
// Only the detail entry: the list entry is already correct, having just been written from the
// payload.
//
// Pinned in ee/spec/frontend/packages_and_registries/artifact_registry/graphql/
// cache_update_spec.js by `drops the detail entry an update cannot reach`.
export const evictUpdatedRepositoryDetails =
  (name) =>
  (cache, { data }) => {
    if (data.updateRepository.errors.length) return;

    evictRepositoryDetailsEntry(cache, name);
  };

export const evictClearedRepositoryDetails =
  (name) =>
  (cache, { data }) => {
    if (data.clearRepositoryCache.errors.length) return;

    evictRepositoryDetailsEntry(cache, name);
  };
