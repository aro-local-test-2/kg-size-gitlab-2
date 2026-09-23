import { InMemoryCache } from '@apollo/client/core';
import { typePolicies as globalTypePolicies } from '~/lib/graphql';
import {
  typePolicies,
  possibleTypes,
} from 'ee/packages_and_registries/artifact_registry/graphql/cache_config';
import {
  evictClearedRepositoryDetails,
  evictRepositoriesList,
  evictUpdatedRepositoryDetails,
} from 'ee/packages_and_registries/artifact_registry/graphql/utils/cache_update';
import { ORGANIZATION_GID, mockRepository } from '../mock_data';

// One repository normalizes under two unrelated typenames, so these assertions read the cache
// keys directly rather than through a query: which entry a write reaches is the whole point.
describe('Artifact registry cache updates', () => {
  const { name } = mockRepository;
  const OLD_DESCRIPTION = 'The description before the edit';

  let cache;

  const keyFor = (__typename) => cache.identify({ __typename, name });

  const listKey = () => keyFor('ArtifactRegistryRepository');
  const detailKey = () => keyFor('ArtifactRegistryRepositoryDetails');

  const organizationKey = () =>
    cache.identify({ __typename: 'Organization', id: ORGANIZATION_GID });

  // Both entries are referenced from ROOT_QUERY, as a real read leaves them. Seeding them
  // unreachable would let `cache.gc()` sweep both and the eviction would look broader than it
  // is.
  const seedBothEntries = () => {
    cache.restore({
      ROOT_QUERY: {
        __typename: 'Query',
        listed: { __ref: listKey() },
        detailed: { __ref: detailKey() },
      },
      [listKey()]: {
        __typename: 'ArtifactRegistryRepository',
        name,
        description: OLD_DESCRIPTION,
      },
      [detailKey()]: {
        __typename: 'ArtifactRegistryRepositoryDetails',
        name,
        description: OLD_DESCRIPTION,
      },
    });
  };

  const runUpdate = (errors = []) =>
    evictUpdatedRepositoryDetails(name)(cache, { data: { updateRepository: { errors } } });

  beforeEach(() => {
    cache = new InMemoryCache({
      possibleTypes,
      typePolicies: { ...globalTypePolicies, ...typePolicies },
    });

    seedBothEntries();
  });

  describe('evictRepositoriesList', () => {
    const UNFILTERED = 'artifactRegistryRepositories({})';
    const FILTERED = 'artifactRegistryRepositories({"kind":"REMOTE"})';

    const cachedVariants = () =>
      Object.keys(cache.extract()[organizationKey()] ?? {}).filter((field) =>
        field.startsWith('artifactRegistryRepositories'),
      );

    const runCreate = (errors = []) =>
      evictRepositoriesList(ORGANIZATION_GID)(cache, {
        data: { createRepository: { errors } },
      });

    beforeEach(() => {
      cache.restore({
        ROOT_QUERY: { __typename: 'Query', organization: { __ref: organizationKey() } },
        [organizationKey()]: {
          __typename: 'Organization',
          id: ORGANIZATION_GID,
          [UNFILTERED]: { nodes: [] },
          [FILTERED]: { nodes: [] },
        },
      });
    });

    it('seeds both variants, so the assertions below distinguish them', () => {
      expect(cachedVariants()).toEqual([UNFILTERED, FILTERED]);
    });

    it('drops every cached variant of the list field', () => {
      runCreate();

      expect(cachedVariants()).toEqual([]);
    });

    it('leaves them alone when the create reported errors', () => {
      runCreate(['Name has already been taken']);

      expect(cachedVariants()).toEqual([UNFILTERED, FILTERED]);
    });
  });

  describe('evictUpdatedRepositoryDetails', () => {
    it('seeds both entries, so the assertions below distinguish them', () => {
      expect(Object.keys(cache.extract())).toEqual(
        expect.arrayContaining([listKey(), detailKey()]),
      );
    });

    it('drops the detail entry an update cannot reach', () => {
      runUpdate();

      expect(cache.extract()[detailKey()]).toBeUndefined();
    });

    it('keeps the list entry, which the payload just rewrote', () => {
      runUpdate();

      expect(cache.extract()[listKey()]).toMatchObject({ description: OLD_DESCRIPTION });
    });

    it('leaves both entries alone when the update reported errors', () => {
      runUpdate(['Repository could not be updated']);

      expect(cache.extract()[detailKey()]).toMatchObject({ description: OLD_DESCRIPTION });
      expect(cache.extract()[listKey()]).toMatchObject({ description: OLD_DESCRIPTION });
    });
  });

  describe('evictClearedRepositoryDetails', () => {
    const runClear = (errors = []) =>
      evictClearedRepositoryDetails(name)(cache, { data: { clearRepositoryCache: { errors } } });

    it('drops the detail entry of the named repository', () => {
      runClear();

      expect(cache.extract()[detailKey()]).toBeUndefined();
    });

    it('leaves the list entry, which the clear does not touch', () => {
      runClear();

      expect(cache.extract()[listKey()]).toMatchObject({ description: OLD_DESCRIPTION });
    });

    it('leaves the detail entry alone when the clear was refused', () => {
      runClear(['Repository not found.']);

      expect(cache.extract()[detailKey()]).toMatchObject({ description: OLD_DESCRIPTION });
    });
  });
});
