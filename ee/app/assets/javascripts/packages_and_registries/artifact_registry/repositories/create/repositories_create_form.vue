<script>
import { GlAlert, GlSkeletonLoader, GlToastMixin } from '@gitlab/ui';
import { createAlert } from '~/alert';
import { fetchPolicies } from '~/lib/graphql';
import { __, s__ } from '~/locale';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import NotFound from '../../components/not_found.vue';
import {
  NAMESPACE_PERMISSION_CREATE_REPOSITORY,
  REPOSITORY_DETAIL_ROUTE_NAME,
  REPOSITORY_FORMAT_OPTIONS,
  REPOSITORY_KIND_DESCRIPTIONS,
  REPOSITORY_KIND_NEW_TITLES,
  REPOSITORY_VISIBILITY_PRIVATE,
} from '../../constants';
import createRepositoryMutation from '../../graphql/mutations/create_repository.mutation.graphql';
import { evictRepositoriesList } from '../../graphql/utils/cache_update';
import { permissionAllows } from '../../graphql/utils/permissions';
import getRegistryPermissionsQuery from '../../graphql/queries/get_registry_permissions.query.graphql';
import RepositoryForm from '../components/repository_form.vue';

export default {
  name: 'ArtifactRegistryRepositoriesCreateForm',
  i18n: {
    submit: s__('ArtifactRegistry|Create repository'),
    createSuccess: s__('ArtifactRegistry|Repository was successfully created.'),
    unavailable: s__('ArtifactRegistry|The Artifact Registry service is unavailable.'),
    genericError: __('Something went wrong. Please try again.'),
  },
  components: {
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
      registry: undefined,
      hasError: false,
      errorMessages: [],
      submitting: false,
    };
  },
  apollo: {
    registry: {
      query: getRegistryPermissionsQuery,
      fetchPolicy: fetchPolicies.CACHE_AND_NETWORK,
      variables() {
        return { organizationId: this.organizationGid };
      },
      update: ({ organization }) => organization?.artifactRegistry ?? null,
      error(error) {
        this.hasError = true;
        Sentry.captureException(error);
      },
    },
  },
  computed: {
    isLoading() {
      return this.$apollo.queries.registry.loading;
    },
    hasResult() {
      return !this.isLoading && !this.hasError;
    },
    isUnavailable() {
      return !this.isLoading && this.hasError;
    },
    isNotFound() {
      return this.hasResult && !this.canCreate;
    },
    permissions() {
      return this.isLoading ? undefined : this.registry?.userPermissions;
    },
    canCreate() {
      return permissionAllows(this.permissions, NAMESPACE_PERMISSION_CREATE_REPOSITORY);
    },
    kind() {
      return this.$route.meta.kind;
    },
    heading() {
      return REPOSITORY_KIND_NEW_TITLES[this.kind];
    },
    description() {
      return REPOSITORY_KIND_DESCRIPTIONS[this.kind];
    },
  },
  methods: {
    async submit(values) {
      this.submitting = true;
      // A retry starts clean, so errors the last attempt raised cannot linger beside
      // whatever this one produces.
      this.errorMessages = [];

      let created = null;

      // Only the mutation is guarded: what follows a successful write is not part of the
      // write, and a navigation vue-router rejects is not a reason to say it failed.
      try {
        created = await this.createRepository(values);
      } catch (error) {
        // A failure the form cannot act on is page-level rather than field-level, so it
        // surfaces as a dismissible alert and is reported, not as a form error.
        createAlert({ message: this.$options.i18n.genericError, error, captureError: true });
      } finally {
        this.submitting = false;
      }

      if (!created) return;

      this.$toast.show(this.$options.i18n.createSuccess);
      this.$router.push({ name: REPOSITORY_DETAIL_ROUTE_NAME, params: { id: created.name } });
    },
    async createRepository(values) {
      const { data } = await this.$apollo.mutate({
        mutation: createRepositoryMutation,
        variables: {
          input: {
            kind: this.kind,
            ...values,
          },
        },
        update: evictRepositoriesList(this.organizationGid),
      });

      const { repository, errors } = data.createRepository;

      if (errors.length) {
        this.errorMessages = errors;
        return null;
      }

      return repository;
    },
  },
  newRepository: {
    format: REPOSITORY_FORMAT_OPTIONS[0].value,
    name: '',
    description: '',
    visibility: REPOSITORY_VISIBILITY_PRIVATE,
  },
};
</script>

<template>
  <not-found v-if="isNotFound" />

  <gl-alert v-else-if="isUnavailable" variant="danger" :dismissible="false">
    {{ $options.i18n.unavailable }}
  </gl-alert>

  <div v-else>
    <page-heading :heading="heading">
      <template #description>{{ description }}</template>
    </page-heading>

    <gl-skeleton-loader v-if="isLoading" :lines="4" />

    <repository-form
      v-else
      :repository="$options.newRepository"
      :kind="kind"
      create-mode
      :submit-text="$options.i18n.submit"
      :submitting="submitting"
      :error-messages="errorMessages"
      @submit="submit"
      @dismiss-errors="errorMessages = []"
    />
  </div>
</template>
