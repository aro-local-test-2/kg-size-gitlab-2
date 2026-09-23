<script>
import { GlDrawer, GlSkeletonLoader, GlToastMixin } from '@gitlab/ui';
import { createAlert } from '~/alert';
import { DRAWER_Z_INDEX } from '~/lib/utils/constants';
import { getContentWrapperHeight } from '~/lib/utils/dom_utils';
import { s__, sprintf } from '~/locale';
import { SCAN_PROFILE_CATEGORIES } from '~/security_configuration/constants';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import groupAvailableSecurityScanProfilesQuery from 'ee/security_configuration/graphql/scan_profiles/group_available_security_scan_profiles.query.graphql';
import securityScanProfileDeleteMutation from 'ee/security_configuration/graphql/scan_profiles/security_scan_profile_delete.mutation.graphql';
import DeleteScanProfileConfirmationModal from './delete_scan_profile_confirmation_modal.vue';
import ScanProfileList from './scan_profile_list.vue';
import ScanProfileDetail from './scan_profile_detail.vue';

const FLASH_CONTAINER_CLASS = 'js-scan-profile-drawer-flash-container';

const i18n = {
  manageProfiles: s__('SecurityConfiguration|Manage profiles'),
  manageScannerProfiles: s__('SecurityConfiguration|Manage %{scannerName} profiles'),
  loadError: s__('SecurityConfiguration|Failed to load scan profiles.'),
  emptyState: s__('SecurityConfiguration|There are no profiles for this scanner yet.'),
  deleteError: s__('SecurityConfiguration|Failed to delete “%{profileName}”.'),
  deleteSuccess: s__('ScanProfiles|Deleted “%{profileName}”'),
};

export default {
  name: 'ScanProfileDrawer',
  components: {
    DeleteScanProfileConfirmationModal,
    GlDrawer,
    GlSkeletonLoader,
    ScanProfileList,
    ScanProfileDetail,
  },
  mixins: [GlToastMixin],
  inject: ['groupFullPath'],
  props: {
    open: {
      type: Boolean,
      required: false,
      default: false,
    },
    scanType: {
      type: String,
      required: false,
      default: '',
    },
  },
  emits: ['close'],
  data() {
    return {
      allProfiles: [],
      selectedId: '',
      loading: 0,
      hasLoadError: false,
      pendingDeletionProfile: null,
      isDeleting: false,
    };
  },
  apollo: {
    allProfiles: {
      query: groupAvailableSecurityScanProfilesQuery,
      skip() {
        return !this.open;
      },
      variables() {
        return { fullPath: this.groupFullPath };
      },
      update(data) {
        return data?.group?.availableSecurityScanProfiles ?? [];
      },
      loadingKey: 'loading',
      result({ data }) {
        if (!data) return;

        this.hasLoadError = false;
        this.selectDefaultProfile();
      },
      error(error) {
        this.hasLoadError = true;
        createAlert({
          message: i18n.loadError,
          containerSelector: `.${FLASH_CONTAINER_CLASS}`,
        });
        Sentry.captureException(error);
      },
    },
  },
  computed: {
    headerHeight() {
      return getContentWrapperHeight();
    },
    title() {
      const displayName = SCAN_PROFILE_CATEGORIES[this.scanType]?.displayName;

      if (!displayName) {
        return i18n.manageProfiles;
      }

      // Only the leading letter is lowered, so acronyms like SAST keep their capitals.
      const scannerName = displayName.charAt(0).toLowerCase() + displayName.slice(1);

      return sprintf(i18n.manageScannerProfiles, { scannerName });
    },
    profiles() {
      return this.allProfiles.filter(({ scanType }) => scanType === this.scanType);
    },
    selectedProfile() {
      return this.profiles.find(({ id }) => id === this.selectedId);
    },
    isLoading() {
      return this.loading > 0;
    },
  },
  watch: {
    open(isOpen) {
      if (isOpen) {
        this.selectedId = '';
        this.pendingDeletionProfile = null;
      }
    },
    scanType() {
      this.selectedId = '';
      this.selectDefaultProfile();
    },
  },
  methods: {
    selectDefaultProfile() {
      if (this.selectedProfile) return;

      this.selectedId = this.profiles[0]?.id ?? '';
    },
    handleDrawerClose() {
      // GlDrawer and GlModal both handle Esc, so when the delete modal is open Esc reaches both.
      // Swallow the drawer close while the modal is pending so only the modal closes.
      if (this.pendingDeletionProfile) return;

      this.$emit('close');
    },
    openDeleteConfirmation(profile) {
      this.pendingDeletionProfile = profile;
    },
    cancelDeleteConfirmation() {
      if (this.isDeleting) return;

      this.pendingDeletionProfile = null;
    },
    async confirmDeleteProfile() {
      if (!this.pendingDeletionProfile || this.isDeleting) return;

      const profileToDelete = this.pendingDeletionProfile;
      this.isDeleting = true;

      try {
        const { data } = await this.$apollo.mutate({
          mutation: securityScanProfileDeleteMutation,
          variables: { input: { id: profileToDelete.id } },
        });

        const errors = data?.securityScanProfileDelete?.errors ?? [];
        if (errors.length) {
          throw new Error(errors.join(', '));
        }

        this.pendingDeletionProfile = null;
        if (this.selectedId === profileToDelete.id) {
          this.selectedId = '';
        }
        await this.$apollo.queries.allProfiles.refetch();
        this.$toast.show(sprintf(i18n.deleteSuccess, { profileName: profileToDelete.name }));
      } catch (error) {
        createAlert({
          message: sprintf(i18n.deleteError, { profileName: profileToDelete.name }),
          containerSelector: `.${FLASH_CONTAINER_CLASS}`,
        });
        Sentry.captureException(error);
      } finally {
        this.isDeleting = false;
      }
    },
  },
  FLASH_CONTAINER_CLASS,
  DRAWER_Z_INDEX,
  i18n,
};
</script>

<template>
  <gl-drawer
    :header-height="headerHeight"
    :header-sticky="true"
    :open="open"
    :z-index="$options.DRAWER_Z_INDEX"
    class="!gl-w-full !gl-max-w-5xl"
    data-testid="scan-profile-drawer"
    @close="handleDrawerClose"
  >
    <template #title>
      <h4 class="gl-my-0 gl-mr-3 gl-text-size-h2">{{ title }}</h4>
    </template>

    <div :class="$options.FLASH_CONTAINER_CLASS" class="empty:gl-hidden"></div>

    <div v-if="isLoading" data-testid="scan-profile-drawer-loader">
      <gl-skeleton-loader :lines="4" />
    </div>

    <template v-else-if="!hasLoadError">
      <p v-if="!profiles.length" class="gl-text-subtle" data-testid="scan-profile-drawer-empty">
        {{ $options.i18n.emptyState }}
      </p>

      <div v-else class="gl-flex gl-h-full gl-gap-5 !gl-pb-0">
        <scan-profile-list
          class="gl-border-r gl-w-1/3 gl-shrink-0 gl-overflow-y-auto"
          :profiles="profiles"
          :selected-id="selectedId"
          @select="selectedId = $event"
        />
        <scan-profile-detail
          v-if="selectedProfile"
          class="gl-min-w-0 gl-grow gl-overflow-y-auto gl-pb-5"
          :profile="selectedProfile"
          @delete="openDeleteConfirmation(selectedProfile)"
        />
      </div>
    </template>

    <delete-scan-profile-confirmation-modal
      :visible="Boolean(pendingDeletionProfile)"
      :profile-name="pendingDeletionProfile ? pendingDeletionProfile.name : ''"
      :project-count="pendingDeletionProfile ? pendingDeletionProfile.projectCount : 0"
      @confirm="confirmDeleteProfile"
      @cancel="cancelDeleteConfirmation"
    />
  </gl-drawer>
</template>
