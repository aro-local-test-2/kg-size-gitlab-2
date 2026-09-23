<script>
import { GlBadge, GlIcon } from '@gitlab/ui';
import {
  MANIFEST_DETAIL_ROUTE_NAME,
  REPOSITORY_DETAIL_ROUTE_NAME,
  REPOSITORY_KIND_LABELS,
} from 'ee/packages_and_registries/artifact_registry/constants';
import {
  humanSize,
  platformLabel,
  shortDigest,
} from 'ee/packages_and_registries/artifact_registry/utils';
import { localeDateFormat, newDate } from '~/lib/utils/datetime_utility';
import { s__, sprintf } from '~/locale';

export default {
  name: 'ArtifactRegistryManifestSidebar',
  components: {
    GlBadge,
    GlIcon,
  },
  props: {
    repository: {
      type: Object,
      required: true,
    },
    manifest: {
      type: Object,
      required: true,
    },
    artifactId: {
      type: String,
      required: true,
    },
  },
  computed: {
    kindLabel() {
      return REPOSITORY_KIND_LABELS[this.repository.kind];
    },
    repositoryRoute() {
      return { name: REPOSITORY_DETAIL_ROUTE_NAME, params: { id: this.repository.name } };
    },
    imageName() {
      return this.repository.image?.name ?? '';
    },
    children() {
      return this.manifest.children ?? [];
    },
    platforms() {
      return this.children.map((child) => {
        const label = platformLabel(child);
        const shortened = shortDigest(child.digest);

        return {
          digest: child.digest,
          label,
          shortened,
          route: this.manifestRoute(child.digest),
          linkLabel: label
            ? sprintf(this.$options.i18n.manifestForPlatform, {
                digest: shortened,
                platform: label,
              })
            : sprintf(this.$options.i18n.manifest, { digest: shortened }),
        };
      });
    },
    ownPlatform() {
      return platformLabel(this.manifest);
    },
    parents() {
      return (this.manifest.parentDigests ?? []).map((digest) => ({
        digest,
        shortened: shortDigest(digest),
        route: this.manifestRoute(digest),
        linkLabel: sprintf(this.$options.i18n.manifest, { digest: shortDigest(digest) }),
      }));
    },
    rendersSize() {
      return this.manifest.size != null && Number.isFinite(Number(this.manifest.size));
    },
    size() {
      return humanSize(this.manifest.size);
    },
    publishedDate() {
      const createdAt = newDate(this.manifest.createdAt);

      return createdAt ? localeDateFormat.asDate.format(createdAt) : null;
    },
  },
  methods: {
    manifestRoute(digest) {
      return {
        name: MANIFEST_DETAIL_ROUTE_NAME,
        params: { id: this.repository.name, artifactId: this.artifactId, digest },
      };
    },
  },
  i18n: {
    repository: s__('ArtifactRegistry|Repository'),
    image: s__('ArtifactRegistry|Image'),
    platforms: s__('ArtifactRegistry|Platforms'),
    platform: s__('ArtifactRegistry|Platform'),
    referencedBy: s__('ArtifactRegistry|Referenced by'),
    manifest: s__('ArtifactRegistry|Manifest %{digest}'),
    manifestForPlatform: s__('ArtifactRegistry|Manifest %{digest} for %{platform}'),
    size: s__('ArtifactRegistry|Size'),
    published: s__('ArtifactRegistry|Published'),
    unknown: s__('ArtifactRegistry|Unknown'),
  },
};
</script>

<template>
  <div class="gl-flex gl-flex-col gl-gap-5">
    <div
      class="gl-border-t gl-flex gl-flex-col gl-gap-3 gl-pt-5 first:gl-border-t-0 first:gl-pt-0"
      data-testid="manifest-repository"
    >
      <h2 class="gl-heading-5 gl-mb-0">{{ $options.i18n.repository }}</h2>

      <p class="gl-mb-0 gl-flex gl-flex-wrap gl-items-center gl-gap-2">
        <router-link :to="repositoryRoute" class="gl-wrap-anywhere">{{
          repository.name
        }}</router-link>
        <gl-badge>{{ kindLabel }}</gl-badge>
      </p>
    </div>

    <div
      v-if="imageName"
      class="gl-border-t gl-flex gl-flex-col gl-gap-3 gl-pt-5 first:gl-border-t-0 first:gl-pt-0"
      data-testid="manifest-image"
    >
      <h2 class="gl-heading-5 gl-mb-0">{{ $options.i18n.image }}</h2>

      <p class="gl-mb-0 gl-wrap-anywhere">{{ imageName }}</p>
    </div>

    <div
      v-if="platforms.length"
      class="gl-border-t gl-flex gl-flex-col gl-gap-3 gl-pt-5 first:gl-border-t-0 first:gl-pt-0"
      data-testid="manifest-platforms"
    >
      <h2 class="gl-heading-5 gl-mb-0">{{ $options.i18n.platforms }}</h2>

      <ul class="gl-m-0 gl-flex gl-list-none gl-flex-col gl-gap-3 gl-p-0">
        <li
          v-for="platform in platforms"
          :key="platform.digest"
          class="gl-flex gl-flex-wrap gl-items-center gl-gap-2"
          data-testid="manifest-platform-child"
        >
          <span v-if="platform.label">{{ platform.label }}</span>

          <router-link
            :to="platform.route"
            :aria-label="platform.linkLabel"
            class="gl-font-monospace"
            >{{ platform.shortened }}</router-link
          >
        </li>
      </ul>
    </div>

    <div
      v-else-if="ownPlatform"
      class="gl-border-t gl-flex gl-flex-col gl-gap-3 gl-pt-5 first:gl-border-t-0 first:gl-pt-0"
      data-testid="manifest-platform"
    >
      <h2 class="gl-heading-5 gl-mb-0">{{ $options.i18n.platform }}</h2>

      <p class="gl-mb-0">{{ ownPlatform }}</p>
    </div>

    <div
      v-if="parents.length"
      class="gl-border-t gl-flex gl-flex-col gl-gap-3 gl-pt-5 first:gl-border-t-0 first:gl-pt-0"
      data-testid="manifest-referenced-by"
    >
      <h2 class="gl-heading-5 gl-mb-0">{{ $options.i18n.referencedBy }}</h2>

      <ul class="gl-m-0 gl-flex gl-list-none gl-flex-col gl-gap-3 gl-p-0">
        <li
          v-for="parent in parents"
          :key="parent.digest"
          data-testid="manifest-referenced-by-parent"
        >
          <router-link
            :to="parent.route"
            :aria-label="parent.linkLabel"
            class="gl-font-monospace"
            >{{ parent.shortened }}</router-link
          >
        </li>
      </ul>
    </div>

    <div
      v-if="rendersSize"
      class="gl-border-t gl-flex gl-items-center gl-gap-4 gl-pt-5 first:gl-border-t-0 first:gl-pt-0"
      data-testid="manifest-size"
    >
      <gl-icon name="archive" variant="subtle" />
      <span class="gl-font-bold">{{ size }}</span>
      <span class="gl-text-subtle">{{ $options.i18n.size }}</span>
    </div>

    <div
      class="gl-border-t gl-flex gl-flex-col gl-gap-3 gl-pt-5 first:gl-border-t-0 first:gl-pt-0"
      data-testid="manifest-published"
    >
      <h2 class="gl-heading-5 gl-mb-0">{{ $options.i18n.published }}</h2>

      <p v-if="publishedDate" class="gl-mb-0">{{ publishedDate }}</p>

      <p v-else class="gl-mb-0 gl-text-subtle" data-testid="manifest-published-unknown">
        {{ $options.i18n.unknown }}
      </p>
    </div>
  </div>
</template>
