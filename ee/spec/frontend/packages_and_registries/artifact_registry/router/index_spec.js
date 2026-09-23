import { mountExtended } from 'helpers/vue_test_utils_helper';
import ArtifactRegistryBreadcrumbs from 'ee/packages_and_registries/artifact_registry/repositories/artifact_registry_breadcrumbs.vue';
import {
  ARTIFACT_VERSIONS_ROUTE_NAME,
  MANIFEST_DETAIL_ROUTE_NAME,
  NOT_FOUND_ROUTE_NAME,
  PAGE_NOT_FOUND_TITLE,
  REPOSITORIES_LIST_ROUTE_NAME,
  REPOSITORY_DETAIL_ROUTE_NAME,
  REPOSITORY_EDIT_ROUTE_NAME,
  REPOSITORY_NEW_HOSTED_ROUTE_NAME,
  REPOSITORY_NEW_REMOTE_ROUTE_NAME,
  REPOSITORY_NEW_VIRTUAL_ROUTE_NAME,
  VERSION_DETAIL_ROUTE_NAME,
} from 'ee/packages_and_registries/artifact_registry/constants';
import { createRouter } from 'ee/packages_and_registries/artifact_registry/router';
import { routeName } from 'ee/packages_and_registries/artifact_registry/utils';
import {
  ARTIFACT_ID_FOR,
  BASE_PATH,
  MANIFEST_DIGEST,
  createBreadCrumbState,
  mockVersionDetails,
  resetBreadCrumbState,
} from '../mock_data';

const ARTIFACT_ID = ARTIFACT_ID_FOR.MAVEN;

describe('Artifact registry repositories router', () => {
  let router;
  let state;

  const getBase = () => router.options.history?.base || router.options.base;

  // The organization crumbs are static, injected from the Rails page, so mounting with
  // none leaves a trail of whatever the routes themselves contribute.
  const findCrumbs = () =>
    mountExtended(ArtifactRegistryBreadcrumbs, {
      router,
      propsData: { staticBreadcrumbs: [] },
    }).findAll('a');

  const crumbTexts = () => findCrumbs().wrappers.map((crumb) => crumb.text());
  const crumbHrefs = () => findCrumbs().wrappers.map((crumb) => crumb.attributes('href'));

  beforeEach(() => {
    state = createBreadCrumbState();
    router = createRouter(BASE_PATH, state);
  });

  afterEach(() => {
    resetBreadCrumbState();
  });

  it('builds a history-mode router based at the slug-scoped repositories path', () => {
    expect(getBase()).toBe(BASE_PATH);
  });

  describe('the repositories list route', () => {
    it('owns the router base, ahead of the not-found fallback', async () => {
      await router.push('/');

      expect(router.currentRoute.name).toBe(REPOSITORIES_LIST_ROUTE_NAME);
    });

    it('contributes the Repositories crumb once, in place of the Rails one', async () => {
      await router.push('/');

      expect(crumbTexts()).toEqual(['Repositories']);
    });
  });

  describe('the hosted create route', () => {
    it('resolves ahead of the not-found fallback', async () => {
      await router.push('/new/hosted');

      expect(router.currentRoute.name).toBe(REPOSITORY_NEW_HOSTED_ROUTE_NAME);
    });

    it('carries the breadcrumb and document title text', async () => {
      await router.push('/new/hosted');

      expect(router.currentRoute.meta.text).toBe('New hosted repository');
    });

    it('takes over a kind-less /new rather than letting it fall through to not-found', async () => {
      await router.push('/new');

      expect(router.currentRoute.name).toBe(REPOSITORY_NEW_HOSTED_ROUTE_NAME);
      expect(router.currentRoute.path).toBe('/new/hosted');
    });
  });

  describe('the remote create route', () => {
    it('resolves rather than falling through to the repository-scoped routes', async () => {
      await router.push('/new/remote');

      expect(router.currentRoute.name).toBe(REPOSITORY_NEW_REMOTE_ROUTE_NAME);
    });

    it('names the kind it creates, so the crumb and the document title both do', async () => {
      await router.push('/new/remote');

      expect(router.currentRoute.meta.text).toBe('New remote repository');
    });
  });

  describe('the virtual create route', () => {
    it('resolves rather than falling through to the repository-scoped routes', async () => {
      await router.push('/new/virtual');

      expect(router.currentRoute.name).toBe(REPOSITORY_NEW_VIRTUAL_ROUTE_NAME);
    });

    it('names the kind it creates, so the crumb and the document title both do', async () => {
      await router.push('/new/virtual');

      expect(router.currentRoute.meta.text).toBe('New virtual repository');
    });

    it('carries the kind the create form builds from', async () => {
      await router.push('/new/virtual');

      expect(router.currentRoute.meta.kind).toBe('VIRTUAL');
    });
  });

  describe('the repository detail route', () => {
    it('claims a single path segment as the name of the repository it shows', async () => {
      await router.push('/payment-core');

      expect(router.currentRoute.name).toBe(REPOSITORY_DETAIL_ROUTE_NAME);
      expect(router.currentRoute.params.id).toBe('payment-core');
    });

    it('renders the repository name as the trailing breadcrumb, behind Repositories', async () => {
      await router.push('/payment-core');

      expect(crumbTexts()).toEqual(['Repositories', 'payment-core']);
    });

    // A crumb whose target never resolves still renders its text, so the href is the
    // assertion that holds: naming this route without the current params renders the
    // uninterpolated `/:id`.
    it('links the trail to paths that resolve, not to the route pattern', async () => {
      await router.push('/payment-core');

      expect(crumbHrefs()).toEqual([`${BASE_PATH}/`, `${BASE_PATH}/payment-core`]);
    });

    it('leaves the reserved new-repository segment to the create route', async () => {
      await router.push('/new');

      expect(router.currentRoute.name).toBe(REPOSITORY_NEW_HOSTED_ROUTE_NAME);
    });
  });

  describe('the repository edit route', () => {
    it.each(['my-repository', 'my.repo_1', '0abc'])(
      'addresses the repository named %p',
      async (name) => {
        await router.push(`/${name}/edit`);

        expect(router.currentRoute.name).toBe(REPOSITORY_EDIT_ROUTE_NAME);
        expect(router.currentRoute.params.id).toBe(name);
      },
    );

    // The breadcrumb trail is built from the matched ancestry, so nesting is what puts
    // the repository between Repositories and Edit.
    it('sits under the repository it edits', async () => {
      await router.push('/my-repository/edit');

      const ancestry = router.currentRoute.matched.map(({ path }) => path);

      // The root record spells its own path differently across the two router versions,
      // so the assertion is on the nesting below it.
      expect(ancestry).toHaveLength(3);
      expect(ancestry.slice(1)).toEqual(['/:id', '/:id/edit']);
    });

    // The repository segment is a single wildcard, so it would swallow the create routes
    // if it were registered ahead of them.
    it.each`
      path              | route
      ${'/new/hosted'}  | ${REPOSITORY_NEW_HOSTED_ROUTE_NAME}
      ${'/new/remote'}  | ${REPOSITORY_NEW_REMOTE_ROUTE_NAME}
      ${'/new/virtual'} | ${REPOSITORY_NEW_VIRTUAL_ROUTE_NAME}
      ${'/new'}         | ${REPOSITORY_NEW_HOSTED_ROUTE_NAME}
    `('does not take over $path', async ({ path, route }) => {
      await router.push(path);

      expect(router.currentRoute.name).toBe(route);
    });
  });

  describe('the artifact version list route', () => {
    it('addresses the artifact the id names', async () => {
      await router.push(`/payment-core/${ARTIFACT_ID}`);

      expect(router.currentRoute.name).toBe(ARTIFACT_VERSIONS_ROUTE_NAME);
      expect(router.currentRoute.params).toMatchObject({
        id: 'payment-core',
        artifactId: ARTIFACT_ID,
      });
    });

    it('sits under the repository the artifact belongs to', async () => {
      await router.push(`/payment-core/${ARTIFACT_ID}`);

      const ancestry = router.currentRoute.matched.map(({ path }) => path);

      expect(ancestry).toHaveLength(4);
      expect(ancestry.slice(1)).toEqual(['/:id', '/:id/:artifactId', '/:id/:artifactId']);
    });

    it('leaves the edit segment to the edit route', async () => {
      await router.push('/payment-core/edit');

      expect(router.currentRoute.name).toBe(REPOSITORY_EDIT_ROUTE_NAME);
    });

    it('names itself by the published artifact name, and by the id until there is one', async () => {
      await router.push(`/payment-core/${ARTIFACT_ID}`);

      const { params } = router.currentRoute;
      const [node, page] = router.currentRoute.matched.slice(-2);

      expect(routeName({ meta: node.meta, params })).toBe(ARTIFACT_ID);
      expect(routeName({ meta: page.meta, params })).toBeUndefined();

      state.updateArtifactName('com.company.payment:core');

      expect(routeName({ meta: node.meta, params })).toBe('com.company.payment:core');
    });

    it('contributes one artifact crumb, not one per matched record', async () => {
      await router.push(`/payment-core/${ARTIFACT_ID}`);
      state.updateArtifactName('com.company.payment:core');

      expect(crumbTexts()).toEqual(['Repositories', 'payment-core', 'com.company.payment:core']);
    });
  });

  describe('the version detail route', () => {
    const VERSION_ID = mockVersionDetails().id;

    const pushVersion = () => router.push(`/payment-core/${ARTIFACT_ID}/versions/${VERSION_ID}`);

    it('addresses the version the id names, under its artifact and repository', async () => {
      await pushVersion();

      expect(router.currentRoute.name).toBe(VERSION_DETAIL_ROUTE_NAME);
      expect(router.currentRoute.params).toMatchObject({
        id: 'payment-core',
        artifactId: ARTIFACT_ID,
        versionId: VERSION_ID,
      });
    });

    it('sits under the artifact the version belongs to', async () => {
      await pushVersion();

      const ancestry = router.currentRoute.matched.map(({ path }) => path);

      expect(ancestry).toHaveLength(4);
      expect(ancestry.slice(1)).toEqual([
        '/:id',
        '/:id/:artifactId',
        '/:id/:artifactId/versions/:versionId',
      ]);
    });

    it('resolves at the pushed path exactly, with nothing appended or normalized away', async () => {
      await pushVersion();

      expect(router.currentRoute.path).toBe(`/payment-core/${ARTIFACT_ID}/versions/${VERSION_ID}`);
    });

    it('names itself by the published version, and by the id until there is one', async () => {
      await pushVersion();

      const { params } = router.currentRoute;
      const page = router.currentRoute.matched.at(-1);

      expect(routeName({ meta: page.meta, params })).toBe(VERSION_ID);

      state.updateVersionName('3.2.1');

      expect(routeName({ meta: page.meta, params })).toBe('3.2.1');
    });

    it('runs the whole trail once both names are published', async () => {
      await pushVersion();
      state.updateArtifactName('com.company.payment:core');
      state.updateVersionName('3.2.1');

      expect(crumbTexts()).toEqual([
        'Repositories',
        'payment-core',
        'com.company.payment:core',
        '3.2.1',
      ]);
    });

    it('resolves by name onto the versions-prefixed path', () => {
      const resolved = router.resolve({
        name: VERSION_DETAIL_ROUTE_NAME,
        params: { id: 'payment-core', artifactId: ARTIFACT_ID, versionId: VERSION_ID },
      });

      expect((resolved.route ?? resolved).path).toBe(
        `/payment-core/${ARTIFACT_ID}/versions/${VERSION_ID}`,
      );
    });

    it('links each crumb to a path that resolves, not to the route pattern', async () => {
      await pushVersion();

      expect(crumbHrefs()).toEqual([
        `${BASE_PATH}/`,
        `${BASE_PATH}/payment-core`,
        `${BASE_PATH}/payment-core/${ARTIFACT_ID}`,
        `${BASE_PATH}/payment-core/${ARTIFACT_ID}/versions/${VERSION_ID}`,
      ]);
    });
  });

  describe('the manifest detail route', () => {
    const SHORT_DIGEST = 'a1b2c3d4a1b2';

    const pushManifest = () =>
      router.push({
        name: MANIFEST_DETAIL_ROUTE_NAME,
        params: { id: 'payment-core', artifactId: ARTIFACT_ID, digest: MANIFEST_DIGEST },
      });

    it('addresses the manifest the digest names, under its image and repository', async () => {
      await pushManifest();

      expect(router.currentRoute.name).toBe(MANIFEST_DETAIL_ROUTE_NAME);
      expect(router.currentRoute.params).toMatchObject({
        id: 'payment-core',
        artifactId: ARTIFACT_ID,
        digest: MANIFEST_DIGEST,
      });
    });

    it('hands back the canonical digest, whatever the URL does with the separator', async () => {
      await pushManifest();

      expect(decodeURIComponent(router.currentRoute.path)).toContain(MANIFEST_DIGEST);
      expect(router.currentRoute.params.digest).toBe(MANIFEST_DIGEST);
    });

    it('resolves the encoded path a reader would paste back to the same manifest', async () => {
      await router.push(
        `/payment-core/${ARTIFACT_ID}/manifests/${encodeURIComponent(MANIFEST_DIGEST)}`,
      );

      expect(router.currentRoute.name).toBe(MANIFEST_DETAIL_ROUTE_NAME);
      expect(router.currentRoute.params.digest).toBe(MANIFEST_DIGEST);
    });

    it('sits under the image the manifest belongs to', async () => {
      await pushManifest();

      const ancestry = router.currentRoute.matched.map(({ path }) => path);

      expect(ancestry).toHaveLength(4);
      expect(ancestry.slice(1)).toEqual([
        '/:id',
        '/:id/:artifactId',
        '/:id/:artifactId/manifests/:digest',
      ]);
    });

    it('names itself by the published digest, and by the param until there is one', async () => {
      await pushManifest();

      const { params } = router.currentRoute;
      const page = router.currentRoute.matched.at(-1);

      expect(routeName({ meta: page.meta, params })).toBe(MANIFEST_DIGEST);

      state.updateManifestName(SHORT_DIGEST);

      expect(routeName({ meta: page.meta, params })).toBe(SHORT_DIGEST);
    });

    it('runs the whole trail once both names are published', async () => {
      await pushManifest();
      state.updateArtifactName('payment-service');
      state.updateManifestName(SHORT_DIGEST);

      expect(crumbTexts()).toEqual([
        'Repositories',
        'payment-core',
        'payment-service',
        SHORT_DIGEST,
      ]);
    });
  });

  describe('third-segment resolution under an artifact', () => {
    // From the path, not by name: a name push bypasses path matching and cannot fail.
    it.each`
      path                                                   | route
      ${`/payment-core/${ARTIFACT_ID}/manifests/sha256:abc`} | ${MANIFEST_DETAIL_ROUTE_NAME}
      ${`/payment-core/${ARTIFACT_ID}/versions/3.2.1`}       | ${VERSION_DETAIL_ROUTE_NAME}
      ${`/payment-core/${ARTIFACT_ID}/manifests`}            | ${NOT_FOUND_ROUTE_NAME}
      ${`/payment-core/${ARTIFACT_ID}/versions`}             | ${NOT_FOUND_ROUTE_NAME}
      ${`/payment-core/${ARTIFACT_ID}/3.2.1`}                | ${NOT_FOUND_ROUTE_NAME}
    `('resolves $path to $route', ({ path, route }) => {
      // vue-router 3 nests the match under `route`; vue-router 4 returns it flat.
      const resolved = router.resolve(path);

      expect((resolved.route ?? resolved).name).toBe(route);
    });
  });

  describe('unregistered routes', () => {
    it('resolves a path deeper than any route to the not-found fallback route', async () => {
      await router.push('/some/unregistered/nested/tab');

      expect(router.currentRoute.name).toBe(NOT_FOUND_ROUTE_NAME);
      expect(router.currentRoute.meta.text).toBe(PAGE_NOT_FOUND_TITLE);
    });

    it('resolves a bare third segment to not-found, since no route claims one now', async () => {
      await router.push('/some/unregistered/tab');

      expect(router.currentRoute.name).toBe(NOT_FOUND_ROUTE_NAME);
    });
  });
});
