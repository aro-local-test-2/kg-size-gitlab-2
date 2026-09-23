<script>
import { GlAlert, GlButton } from '@gitlab/ui';
import { sprintf, __ } from '~/locale';
import { logError } from '~/lib/logger';
import { joinPaths, escapeFileUrl } from '~/lib/utils/url_utility';
import { projectTreePath } from '~/lib/utils/path_helpers/repository';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import glFeatureFlagMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import glLicensedFeaturesMixin from '~/vue_shared/mixins/gl_licensed_features_mixin';
import projectInfoQuery from 'ee_else_ce/repository/queries/project_info.query.graphql';
import LockButton from 'ee/repository/components/header_area/lock_button.vue';

export default {
  name: 'BlobControlsLockButton',
  i18n: {
    upstreamLockAlert: __(
      'The parent directory "%{path}" is locked. To unlock this file, unlock "%{path}".',
    ),
    viewLock: __('View lock'),
  },
  components: {
    GlAlert,
    GlButton,
    LockButton,
  },
  mixins: [glFeatureFlagMixin(), glLicensedFeaturesMixin()],
  inject: {
    currentRef: {
      default: '',
    },
  },
  props: {
    projectPath: {
      type: String,
      required: true,
    },
    path: {
      type: String,
      required: true,
    },
  },
  apollo: {
    projectInfo: {
      query: projectInfoQuery,
      variables() {
        return {
          projectPath: this.projectPath,
        };
      },
      skip() {
        return !this.isLockAvailable;
      },
      update: (data) => data.project || {},
      error(error) {
        logError(
          `Failed to fetch project info. See exception details for more information.`,
          error,
        );
        Sentry.captureException(error);
      },
    },
  },
  data() {
    return {
      projectInfo: {},
    };
  },
  computed: {
    isLockAvailable() {
      return Boolean(
        this.glFeatures.repositoryLockInformation && this.glLicensedFeatures.fileLocks,
      );
    },
    pathLock() {
      return this.projectInfo?.pathLocks?.nodes?.find((node) => node.path === this.path);
    },
    upstreamLock() {
      if (this.pathLock) return null;
      return this.projectInfo?.pathLocks?.nodes?.find((node) =>
        this.path.startsWith(`${node.path}/`),
      );
    },
    activeLock() {
      return this.pathLock ?? this.upstreamLock ?? null;
    },
    lockState() {
      return {
        isLocked: Boolean(this.activeLock),
        lockUser: this.activeLock?.user ?? null,
        lockedAt: this.activeLock?.createdAt ?? null,
        // An upstream lock can only be removed on the locked directory itself.
        canDestroyLock: Boolean(this.pathLock?.userPermissions?.destroyPathLock),
        canCreateLock: Boolean(this.projectInfo?.userPermissions?.createPathLock),
      };
    },
    upstreamLockAlert() {
      if (!this.upstreamLock) return null;
      return sprintf(this.$options.i18n.upstreamLockAlert, { path: this.upstreamLock.path }, false);
    },
    lockedPathHref() {
      // The route helper's glob encoding misses `#` and `?`, so escape the lock path ourselves.
      // The parent provides currentRef as null when the page has no explicit ref,
      // which bypasses the inject default, so fall back to the repository root ref.
      return joinPaths(
        projectTreePath(this.projectPath, this.currentRef || this.projectInfo?.repository?.rootRef),
        escapeFileUrl(this.upstreamLock.path),
      );
    },
  },
};
</script>

<template>
  <lock-button
    v-if="isLockAvailable"
    :is-locked="lockState.isLocked"
    :lock-user="lockState.lockUser"
    :locked-at="lockState.lockedAt"
    :can-destroy-lock="lockState.canDestroyLock"
    :can-create-lock="lockState.canCreateLock"
    :project-path="projectPath"
    :path="path"
  >
    <template v-if="upstreamLockAlert" #disclosure-alert>
      <gl-alert
        variant="warning"
        :dismissible="false"
        class="gl-mx-4 gl-my-3 gl-rounded-base"
        data-testid="related-lock-alert"
      >
        {{ upstreamLockAlert }}
      </gl-alert>
    </template>
    <template v-if="upstreamLockAlert" #footer>
      <gl-button size="small" :href="lockedPathHref" data-testid="view-locked-path-button">
        {{ $options.i18n.viewLock }}
      </gl-button>
    </template>
  </lock-button>
</template>
