<script>
import { GlLink, GlSprintf } from '@gitlab/ui';
import { s__ } from '~/locale';
import HelpPageLink from '~/vue_shared/components/help_page_link/help_page_link.vue';
import CeOrganizationShowApp from '~/organizations/show/components/app.vue';

export default {
  name: 'OrganizationShowAppEE',
  components: { CeOrganizationShowApp, GlLink, GlSprintf, HelpPageLink },
  props: {
    organization: {
      type: Object,
      required: true,
    },
    canAdminOrganization: {
      type: Boolean,
      required: true,
    },
    artifactRegistryPath: {
      type: String,
      required: false,
      default: null,
    },
    canLeaveOrganization: {
      type: Boolean,
      required: false,
      default: false,
    },
    organizationUserGid: {
      type: String,
      required: false,
      default: null,
    },
  },
  computed: {
    showArtifactRegistry() {
      return Boolean(this.artifactRegistryPath);
    },
    artifactRegistryEmptyStateDescription() {
      if (this.canAdminOrganization) {
        return s__(
          "Organization|%{organizationName} is your organization's home. Manage Artifact Registry and settings from the sidebar. %{linkStart}Learn more%{linkEnd}.",
        );
      }

      return s__(
        "Organization|%{organizationName} is your organization's home. Manage Artifact Registry from the sidebar. %{linkStart}Learn more%{linkEnd}.",
      );
    },
  },
};
</script>

<template>
  <ce-organization-show-app
    :organization="organization"
    :can-admin-organization="canAdminOrganization"
    :can-leave-organization="canLeaveOrganization"
    :organization-user-gid="organizationUserGid"
  >
    <template v-if="showArtifactRegistry" #description>
      <gl-sprintf :message="artifactRegistryEmptyStateDescription">
        <template #organizationName
          ><span data-testid="organization-name">{{ organization.name }}</span></template
        >
        <template #link="{ content }">
          <help-page-link href="/user/organization/_index.md">{{ content }}</help-page-link>
        </template>
      </gl-sprintf>
    </template>
    <template v-if="showArtifactRegistry" #actions>
      <gl-link :href="artifactRegistryPath">{{
        s__('Organization|Go to Artifact Registry')
      }}</gl-link>
    </template>
  </ce-organization-show-app>
</template>
