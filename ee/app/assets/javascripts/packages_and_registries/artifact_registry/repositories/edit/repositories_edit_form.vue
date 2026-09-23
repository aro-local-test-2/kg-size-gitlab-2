<script>
import { GlAlert, GlSkeletonLoader, GlToastMixin } from '@gitlab/ui';
import { createAlert } from '~/alert';
import { fetchPolicies } from '~/lib/graphql';
import { __, s__ } from '~/locale';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import NotFound from '../../components/not_found.vue';
import {
  REPOSITORY_DETAIL_ROUTE_NAME,
  REPOSITORY_FORMAT_LOGO_SIZE_HEADING,
  REPOSITORY_KIND_EDIT_TITLES,
  REPOSITORY_PERMISSION_UPDATE_REPOSITORY,
} from '../../constants';
import updateRepositoryMutation from '../../graphql/mutations/update_repository.mutation.graphql';
import { evictUpdatedRepositoryDetails } from '../../graphql/utils/cache_update';
import { permissionAllows } from '../../graphql/utils/permissions';
import getRepositoryQuery from '../../graphql/queries/get_repository.query.graphql';
import FormatLogo from '../components/format_logo.vue';
import RepositoryForm from '../components/repository_form.vue';

export default {
  name: 'ArtifactRegistryRepositoriesEditForm',
  i18n: {
    submit: __('Save changes'),
    updateSuccess: s__('ArtifactRegistry|Repository was successfully updated.'),
    unavailable: s__('ArtifactRegistry|The Artifact Registry service is unavailable.'),
    genericError: __('Something went wrong. Please try again.'),
  },
  components: {
    FormatLogo,
    GlAlert,
    GlSkeletonLoader,
    NotFound,
    PageHeading,
    RepositoryForm,
  },
  mixins: [GlToastMixin],
  inject: ['organizationGid'],
  data() {
    return {
      repository: undefined,
      hasError: false,
      errorMessages: [],
      submitting: false,
    };
  },
  apollo: {
    repository: {
      query: getRepositoryQuery,
      fetchPolicy: fetchPolicies.CACHE_AND_NETWORK,
      variables() {
        return { organizationId: this.organizationGid, name: this.repositoryName };
      },
      update: ({ organization }) => organization?.artifactRegistryRepository ?? null,
      error() {
        this.hasError = true;
      },
    },
  },
  computed: {
    repositoryName() {
      return this.$route.params.id;
    },
    isLoading() {
      return this.$apollo.queries.repository.loading;
    },
    hasResult() {
      return !this.isLoading && !this.hasError;
    },
    isUnavailable() {
      return !this.isLoading && this.hasError;
    },
    // A repository the viewer cannot see and one that does not exist resolve the same
    // way, so the view renders the not-found state alone rather than confirming which.
    isNotFound() {
      return this.hasResult && (this.repository === null || !this.canUpdate);
    },
    permissions() {
      return this.isLoading ? undefined : this.repository?.userPermissions;
    },
    canUpdate() {
      return permissionAllows(this.permissions, REPOSITORY_PERMISSION_UPDATE_REPOSITORY);
    },
    // The heading renders before the query answers, so it carries a logo only once the
    // repository names a format to render one for.
    format() {
      return this.repository?.format;
    },
    // Until the prefill answers there is no kind to name, so the repository the route
    // names stands in behind the skeleton.
    heading() {
      return REPOSITORY_KIND_EDIT_TITLES[this.repository?.kind] ?? this.repositoryName;
    },
    // An edit is reached from the repository it edits, so abandoning one returns there
    // rather than to the list the viewer has already left.
    cancelRoute() {
      return { name: REPOSITORY_DETAIL_ROUTE_NAME, params: { id: this.repository?.name } };
    },
  },
  methods: {
    async submit(values) {
      this.errorMessages = [];
      this.submitting = true;

      let updated = null;

      // Only the mutation is guarded: what follows a successful write is not part of the
      // write, and a navigation vue-router rejects is not a reason to say it failed.
      try {
        updated = await this.updateRepository(values);
      } catch (error) {
        // A failure the form cannot act on is page-level rather than field-level, so it
        // surfaces as a dismissible alert and is reported, not as a form error.
        createAlert({ message: this.$options.i18n.genericError, error, captureError: true });
      } finally {
        this.submitting = false;
      }

      if (!updated) return;

      this.$toast.show(this.$options.i18n.updateSuccess);
      this.$router.push({ name: REPOSITORY_DETAIL_ROUTE_NAME, params: { id: updated.name } });
    },
    async updateRepository({ description, visibility, settings }) {
      const { data } = await this.$apollo.mutate({
        mutation: updateRepositoryMutation,
        variables: {
          input: {
            name: this.repositoryName,
            description,
            // The form omits visibility while the control is hidden, and omitting it
            // leaves the stored value alone rather than rewriting it.
            ...(visibility ? { visibility } : {}),
            ...(settings ? { settings } : {}),
          },
        },
        update: evictUpdatedRepositoryDetails(this.repositoryName),
      });

      return this.takeRepository(data.updateRepository);
    },
    takeRepository({ repository, errors }) {
      if (errors.length) {
        this.errorMessages = errors;
        return null;
      }

      return repository;
    },
  },
  logoSize: REPOSITORY_FORMAT_LOGO_SIZE_HEADING,
};
</script>

<template>
  <not-found v-if="isNotFound" />

  <gl-alert v-else-if="isUnavailable" variant="danger" :dismissible="false">
    {{ $options.i18n.unavailable }}
  </gl-alert>

  <div v-else>
    <page-heading>
      <template #heading>
        <span class="gl-flex gl-items-center gl-gap-4">
          <format-logo
            v-if="format"
            :format="format"
            :size="$options.logoSize"
            data-testid="repository-format-logo"
          />
          <gl-skeleton-loader v-if="isLoading" :lines="1" :width="240" />
          <template v-else>{{ heading }}</template>
        </span>
      </template>
    </page-heading>

    <gl-skeleton-loader v-if="isLoading" :lines="4" />

    <repository-form
      v-else
      :repository="repository"
      :submit-text="$options.i18n.submit"
      :submitting="submitting"
      :error-messages="errorMessages"
      name-readonly
      :show-format="false"
      :cancel-route="cancelRoute"
      @submit="submit"
      @dismiss-errors="errorMessages = []"
    />
  </div>
</template>
