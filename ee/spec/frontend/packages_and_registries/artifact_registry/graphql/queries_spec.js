import { removeClientSetsFromDocument } from '@apollo/client/utilities';
import { visit } from 'graphql';
import getManifestQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_manifest.query.graphql';
import getManifestReferrersQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_manifest_referrers.query.graphql';
import getRepositoriesQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repositories.query.graphql';
import getRepositoryQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository.query.graphql';
import getRepositoryDetailQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_detail.query.graphql';
import getRepositoryImagesQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_images.query.graphql';
import getRepositoryPackagesQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_packages.query.graphql';
import getRepositoryUpstreamRepositoriesQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_upstream_repositories.query.graphql';
import getVersionQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_version.query.graphql';
import getVersionFilesQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_version_files.query.graphql';

// A variable left declared but unused is rejected by the endpoint, and nothing before the
// request catches it: the source document does use the variable, so schema validation passes.
const unusedVariablesInServerDocument = (document) => {
  const serverDocument = removeClientSetsFromDocument(document);

  if (!serverDocument) return [];

  const referenced = new Set();

  visit(serverDocument, {
    VariableDefinition: () => false,
    Variable: ({ name }) => {
      referenced.add(name.value);
    },
  });

  return serverDocument.definitions
    .flatMap(({ variableDefinitions = [] }) => variableDefinitions)
    .map(({ variable }) => variable.name.value)
    .filter((name) => !referenced.has(name));
};

const variableNames = (document) =>
  document.definitions
    .flatMap(({ variableDefinitions = [] }) => variableDefinitions)
    .map(({ variable }) => variable.name.value);

// The top-level field names a repository selection carries, without descending into it.
const fieldsUnder = (document, fieldName) => {
  const fields = [];

  visit(document, {
    Field: ({ name, selectionSet }) => {
      if (name.value !== fieldName) return undefined;

      fields.push(...selectionSet.selections.map((selection) => selection.name.value));

      return false;
    },
  });

  return fields;
};

const repositoryFields = (document) => {
  const fields = [];

  if (!document) return fields;

  visit(document, {
    Field: ({ name, selectionSet }) => {
      if (name.value !== 'artifactRegistryRepository') return undefined;

      fields.push(...selectionSet.selections.map((selection) => selection.name.value));

      return false;
    },
  });

  return fields;
};

describe('Artifact registry query documents', () => {
  describe.each([
    ['getArtifactRegistryManifest', getManifestQuery],
    ['getArtifactRegistryManifestReferrers', getManifestReferrersQuery],
    ['getArtifactRegistryRepositories', getRepositoriesQuery],
    ['getArtifactRegistryRepository', getRepositoryQuery],
    ['getArtifactRegistryRepositoryDetail', getRepositoryDetailQuery],
    ['getArtifactRegistryRepositoryImages', getRepositoryImagesQuery],
    ['getArtifactRegistryRepositoryPackages', getRepositoryPackagesQuery],
    ['getArtifactRegistryRepositoryUpstreamRepositories', getRepositoryUpstreamRepositoriesQuery],
    ['getArtifactRegistryVersion', getVersionQuery],
    ['getArtifactRegistryVersionFiles', getVersionFilesQuery],
  ])('%s, with its client fields stripped as Apollo strips them', (_name, document) => {
    it('leaves behind no variable the server rejects as declared but not used', () => {
      expect(unusedVariablesInServerDocument(document)).toEqual([]);
    });
  });

  describe.each([
    ['getArtifactRegistryRepositoryImages', getRepositoryImagesQuery, 'images'],
    ['getArtifactRegistryRepositoryPackages', getRepositoryPackagesQuery, 'packages'],
  ])('%s', (_name, document, connection) => {
    it('asks the server for the connection itself, so the page it renders is the schema’s', () => {
      expect(repositoryFields(removeClientSetsFromDocument(document))).toEqual([
        'id',
        'name',
        'format',
        connection,
      ]);
    });

    it('declares every paging variable to the server, so a cursor reaches Artifact Registry', () => {
      expect(variableNames(removeClientSetsFromDocument(document))).toEqual([
        'organizationId',
        'name',
        'first',
        'last',
        'before',
        'after',
      ]);
    });
  });

  describe('getArtifactRegistryRepositoryUpstreamRepositories', () => {
    it('sends the whole document to the server, upstream list included', () => {
      const fields = ['id', 'name', 'kind', 'upstreamRepositories'];

      expect(
        repositoryFields(removeClientSetsFromDocument(getRepositoryUpstreamRepositoriesQuery)),
      ).toEqual(fields);
      expect(repositoryFields(getRepositoryUpstreamRepositoriesQuery)).toEqual(fields);
    });

    it('selects the association fields the table and the cache need', () => {
      expect(fieldsUnder(getRepositoryUpstreamRepositoriesQuery, 'upstreamRepositories')).toEqual([
        'id',
        'position',
        'upstreamRepository',
      ]);
    });

    it('selects the upstream summary without its format', () => {
      expect(fieldsUnder(getRepositoryUpstreamRepositoriesQuery, 'upstreamRepository')).toEqual([
        'id',
        'name',
        'kind',
      ]);
    });

    it('declares the identity variables alone, since the list is unpaginated', () => {
      expect(
        variableNames(removeClientSetsFromDocument(getRepositoryUpstreamRepositoriesQuery)),
      ).toEqual(['organizationId', 'name']);
    });
  });

  describe('getArtifactRegistryManifest', () => {
    it('asks the server for the repository identity, the format, the kind, and the image', () => {
      expect(repositoryFields(removeClientSetsFromDocument(getManifestQuery))).toEqual([
        'id',
        'name',
        'format',
        'kind',
        'image',
      ]);
    });

    it('keeps the manifest alone as a client field, so the server read omits it', () => {
      expect(repositoryFields(getManifestQuery)).toEqual([
        'id',
        'name',
        'format',
        'kind',
        'image',
        'manifest',
      ]);
    });

    it('selects the two fields that tell a referrer from an image', () => {
      expect(fieldsUnder(getManifestQuery, 'manifest')).toEqual(
        expect.arrayContaining(['artifactType', 'subjectDigest']),
      );
    });

    it('leaves the digest behind with the client field, keeping the image id', () => {
      expect(variableNames(removeClientSetsFromDocument(getManifestQuery))).toEqual([
        'organizationId',
        'name',
        'artifactId',
      ]);
    });
  });

  describe('getArtifactRegistryManifestReferrers', () => {
    it('asks the server for the repository identity, the format, and the manifest itself', () => {
      expect(repositoryFields(removeClientSetsFromDocument(getManifestReferrersQuery))).toEqual([
        'id',
        'name',
        'format',
        'manifest',
      ]);
      expect(
        fieldsUnder(removeClientSetsFromDocument(getManifestReferrersQuery), 'manifest'),
      ).toEqual(['id']);
    });

    it('keeps only the connection back as a client field, under the real manifest', () => {
      expect(repositoryFields(getManifestReferrersQuery)).toEqual([
        'id',
        'name',
        'format',
        'manifest',
      ]);
      expect(fieldsUnder(getManifestReferrersQuery, 'manifest')).toEqual(['id', 'referrers']);
    });

    it('selects the three columns the table renders, plus the identity the cache keys on', () => {
      expect(fieldsUnder(getManifestReferrersQuery, 'nodes')).toEqual([
        'id',
        'digest',
        'mediaType',
        'artifactType',
        'subjectDigest',
        'createdAt',
      ]);
    });

    it('leaves the server the manifest lookup variables, but not the paging one', () => {
      expect(variableNames(removeClientSetsFromDocument(getManifestReferrersQuery))).toEqual([
        'organizationId',
        'name',
        'artifactId',
        'digest',
      ]);
    });

    it('repeats the paging variable on the client field, not on the connection alone', () => {
      const argumentsOf = (fieldName) => {
        const names = [];

        visit(getManifestReferrersQuery, {
          Field: ({ name, arguments: args = [] }) => {
            if (name.value !== fieldName) return undefined;

            names.push(...args.map(({ name: argument }) => argument.value));

            return undefined;
          },
        });

        return names;
      };

      expect(argumentsOf('manifest')).toEqual(['digest', 'artifactId']);
      expect(argumentsOf('referrers')).toEqual(['first']);
    });
  });

  describe('getArtifactRegistryVersionFiles', () => {
    it('asks the server for the version and the files under it', () => {
      expect(repositoryFields(removeClientSetsFromDocument(getVersionFilesQuery))).toEqual([
        'id',
        'name',
        'format',
        'kind',
        'version',
      ]);
      expect(fieldsUnder(removeClientSetsFromDocument(getVersionFilesQuery), 'version')).toEqual([
        'id',
        'files',
      ]);
    });

    it('declares the identity variables, both ids, and every paging variable', () => {
      expect(variableNames(removeClientSetsFromDocument(getVersionFilesQuery))).toEqual([
        'organizationId',
        'name',
        'artifactId',
        'versionId',
        'first',
        'last',
        'before',
        'after',
      ]);
    });
  });
});
