<script>
import { GlAlert, GlButton, GlFormInput } from '@gitlab/ui';
import { cloneDeep } from 'lodash-es';
import { MountingPortal } from 'portal-vue';
import { __, createListFormat, n__, s__ } from '~/locale';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import DynamicPanel from '~/vue_shared/components/dynamic_panel.vue';
import { ARTIFACT_SOURCE_TYPE } from '../constants';
import cdApplicationCreateMutation from '../graphql/applications/cd_application_create.mutation.graphql';
import PanelFormField from './shared/panel_form_field.vue';

export default {
  name: 'NewApplicationPanel',
  components: {
    GlAlert,
    DynamicPanel,
    GlButton,
    GlFormInput,
    MountingPortal,
    PanelFormField,
  },
  props: {
    open: {
      type: Boolean,
      required: true,
    },
    organizationId: {
      type: String,
      required: false,
      default: '',
    },
  },
  emits: ['close', 'create'],
  data() {
    return {
      errors: undefined,
      isSubmitting: false,
      serviceIndex: null,
      services: [],
      showServiceForm: false,
      // application form data
      name: '',
      description: '',
      // service form data
      serviceName: '',
      artifacts: [this.buildArtifactSource()],
      // validation errors
      showValidationErrors: false,
      showServiceValidationErrors: false,
      showEmptyServicesError: false,
      showEmptyArtifactsError: false,
    };
  },
  computed: {
    serviceFormButton() {
      return this.serviceIndex == null
        ? s__('ContinuousDeployment|Add service')
        : s__('ContinuousDeployment|Save service');
    },
    isNameValid() {
      return this.name.trim().length > 0;
    },
    nameState() {
      return this.showValidationErrors && !this.isNameValid ? false : null;
    },
    isServiceNameValid() {
      return this.serviceName.trim().length > 0;
    },
    serviceNameState() {
      return this.showServiceValidationErrors && !this.isServiceNameValid ? false : null;
    },
  },
  methods: {
    getArtifactsCountText(service) {
      return n__('%d artifact', '%d artifacts', service.artifactSources.length);
    },
    getArtifactsListText(service) {
      return createListFormat({ style: 'narrow' }).format(
        service.artifactSources.map((artifact) => artifact.name),
      );
    },
    cancelService() {
      if (this.serviceIndex != null) {
        // If user cancels a new form, we let the user resume with their data.
        // But if user cancels an editing form, we should clear the data
        // because it's confusing to continue showing it when re-displaying the form.
        this.clearServiceInputData();
      }
      this.showServiceForm = false;
      this.serviceIndex = null;
    },
    addService() {
      this.showServiceValidationErrors = true;

      this.showEmptyArtifactsError = this.artifacts.some(
        (artifact) => !artifact.name.trim() || !artifact.sourceRef.trim(),
      );

      if (!this.isServiceNameValid || this.showEmptyArtifactsError) {
        return;
      }

      if (this.serviceIndex == null) {
        // Add new service
        this.services.push({
          name: this.serviceName,
          artifactSources: [...this.artifacts],
        });
      } else {
        // Edit existing service
        this.services[this.serviceIndex].name = this.serviceName;
        this.services[this.serviceIndex].artifactSources = [...this.artifacts];
      }
      this.clearServiceInputData();
      this.showServiceForm = false;
      this.serviceIndex = null;
    },
    editService(index) {
      this.serviceIndex = index;
      this.serviceName = this.services[index].name;
      this.artifacts = cloneDeep(this.services[index].artifactSources);
      this.startEditingServiceForm();
    },
    removeService(index) {
      this.services.splice(index, 1);
    },
    addArtifact() {
      this.artifacts.push(this.buildArtifactSource());
    },
    removeArtifact(index) {
      this.artifacts.splice(index, 1);
    },
    buildArtifactSource() {
      return { name: '', sourceRef: '' };
    },
    getInputState(value) {
      return this.showEmptyArtifactsError && !value.trim() ? false : null;
    },
    async startEditingServiceForm() {
      this.showServiceForm = true;
      await this.$nextTick();
      this.$refs.serviceName.$el.focus();
    },
    closePanel() {
      this.$emit('close');
    },
    clearServiceInputData() {
      this.serviceName = '';
      this.artifacts = [this.buildArtifactSource()];
      this.showServiceValidationErrors = false;
      this.showEmptyServicesError = false;
      this.showEmptyArtifactsError = false;
    },
    clearForm() {
      this.name = '';
      this.description = '';
      this.clearServiceInputData();
      this.serviceIndex = null;
      this.services = [];
      this.errors = undefined;
      this.showValidationErrors = false;
    },
    async submitForm() {
      this.showValidationErrors = true;

      if (!this.services.length) {
        this.showEmptyServicesError = true;
        return;
      }

      if (!this.isNameValid) {
        return;
      }

      try {
        this.isSubmitting = true;

        const { data } = await this.$apollo.mutate({
          mutation: cdApplicationCreateMutation,
          variables: {
            input: {
              name: this.name,
              description: this.description,
              organizationId: this.organizationId,
              services: this.services.map((service) => ({
                ...service,
                artifactSources: service.artifactSources.map((artifactSource) => ({
                  ...artifactSource,
                  // sourceConfig is required for rollouts to start; ARTIFACT_SOURCE_TYPE is the only
                  // driver type supported today, so it's set here rather than exposed as a field.
                  sourceConfig: { name: artifactSource.name, type: ARTIFACT_SOURCE_TYPE },
                })),
              })),
            },
          },
        });

        if (data.cdApplicationCreate.errors.length) {
          this.errors = data.cdApplicationCreate.errors;
          return;
        }

        this.$emit('create');
        this.clearForm();
        this.closePanel();
      } catch (error) {
        Sentry.captureException(error);
        this.errors = [__('An error occurred. Please try again.')];
      } finally {
        this.isSubmitting = false;
      }
    },
  },
};
</script>

<template>
  <mounting-portal v-if="open" mount-to="#contextual-panel-portal" append>
    <dynamic-panel @close="closePanel">
      <template #header>
        <div class="gl-py-3">
          <p
            class="gl-mb-2 gl-text-xs gl-font-bold gl-uppercase gl-tracking-wider gl-text-status-brand"
          >
            {{ s__('ContinuousDeployment|Add application') }}
          </p>
          <h2 class="gl-my-0 gl-text-base">
            {{ s__('ContinuousDeployment|Register application') }}
          </h2>
        </div>
      </template>

      <p class="gl-my-5 gl-text-subtle">
        {{
          s__(
            "ContinuousDeployment|Declare your application's topology — its services and their artifacts. Where each service deploys is configured later, per environment.",
          )
        }}
      </p>

      <gl-alert v-if="errors" class="gl-my-4" variant="danger" @dismiss="errors = undefined">
        <ul class="gl-m-0 gl-pl-4">
          <li v-for="error in errors" :key="error">
            {{ error }}
          </li>
        </ul>
      </gl-alert>

      <h3 class="gl-mt-7 gl-text-base">{{ s__('ContinuousDeployment|Application identity') }}</h3>

      <div class="gl-border-b gl-mb-5 gl-flex gl-gap-3 gl-pb-6">
        <panel-form-field
          class="gl-grow"
          :label="s__('ContinuousDeployment|Application name')"
          :state="nameState"
          :invalid-feedback="s__('ContinuousDeployment|Application name is required.')"
        >
          <gl-form-input
            id="application-name"
            v-model="name"
            autofocus
            :state="nameState"
            :placeholder="s__('ContinuousDeployment|e.g. acme-platform')"
          />
        </panel-form-field>
        <panel-form-field class="gl-grow" :label="s__('ContinuousDeployment|Description')">
          <gl-form-input
            id="application-description"
            v-model="description"
            :placeholder="s__('ContinuousDeployment|Brief description')"
          />
        </panel-form-field>
      </div>

      <div class="gl-mb-3 gl-flex gl-items-center gl-justify-between">
        <h3 class="gl-m-0 gl-text-base">{{ s__('ContinuousDeployment|Services') }}</h3>
        <gl-button
          class="gl-shrink-0"
          category="secondary"
          :disabled="showServiceForm"
          size="small"
          variant="confirm"
          data-testid="add-service-header"
          @click="startEditingServiceForm"
        >
          {{ s__('ContinuousDeployment|+ Add service') }}
        </gl-button>
      </div>

      <p class="gl-mb-3 gl-text-sm gl-text-subtle">
        {{
          s__(
            'ContinuousDeployment|The deployable units. A service produces one or more artifacts (container images).',
          )
        }}
      </p>

      <ul v-if="services.length" class="gl-m-0 gl-list-none gl-p-0" data-testid="services-list">
        <li
          v-for="(service, index) in services"
          :key="index"
          class="gl-border gl-mb-4 gl-flex gl-items-center gl-rounded-lg gl-px-4 gl-py-3"
        >
          <div class="gl-mr-auto">
            <div class="gl-font-bold">{{ service.name }}</div>
            <div class="gl-font-monospace gl-text-sm gl-text-subtle">
              {{ getArtifactsCountText(service) }}
              &middot;
              {{ getArtifactsListText(service) }}
            </div>
          </div>
          <gl-button
            category="tertiary"
            icon="pencil"
            size="small"
            data-testid="edit-service"
            @click="editService(index)"
          >
            {{ s__('ContinuousDeployment|Edit') }}
          </gl-button>
          <gl-button
            category="tertiary"
            icon="remove"
            size="small"
            variant="danger"
            data-testid="remove-service"
            @click="removeService(index)"
          >
            {{ s__('ContinuousDeployment|Remove') }}
          </gl-button>
        </li>
      </ul>
      <p
        v-else-if="!showServiceForm"
        class="gl-text-sm gl-text-subtle"
        data-testid="service-empty-state"
      >
        {{ s__('ContinuousDeployment|No services yet — add at least one.') }}
      </p>

      <div
        v-if="showServiceForm"
        class="gl-border gl-rounded-lg gl-border-subtle gl-bg-subtle gl-px-4 gl-py-3"
        data-testid="service-form"
      >
        <div class="gl-mt-3 gl-flex gl-gap-3">
          <panel-form-field
            class="gl-grow"
            :label="s__('ContinuousDeployment|Service name')"
            :state="serviceNameState"
            :invalid-feedback="s__('ContinuousDeployment|Service name is required.')"
          >
            <gl-form-input
              id="service-name"
              ref="serviceName"
              v-model="serviceName"
              :state="serviceNameState"
              :placeholder="s__('ContinuousDeployment|e.g. api-gateway')"
            />
          </panel-form-field>
        </div>
        <div class="gl-mb-3 gl-flex gl-items-center gl-justify-between">
          <span class="gl-text-sm">
            {{ s__('ContinuousDeployment|Artifacts') }}
          </span>
          <gl-button
            category="tertiary"
            size="small"
            data-testid="add-artifact"
            @click="addArtifact"
          >
            {{ s__('ContinuousDeployment|+ Add artifact') }}
          </gl-button>
        </div>
        <ul v-if="artifacts.length" class="gl-m-0 gl-list-none gl-p-0" data-testid="artifacts-list">
          <li v-for="(artifact, index) in artifacts" :key="index" class="gl-mb-2 gl-flex">
            <gl-form-input
              v-model="artifact.name"
              class="gl-mr-3"
              :placeholder="s__('ContinuousDeployment|Name (e.g. api-gateway)')"
              :state="getInputState(artifact.name)"
              :aria-label="s__('ContinuousDeployment|Artifact name')"
            />
            <gl-form-input
              v-model="artifact.sourceRef"
              class="gl-mr-2"
              :placeholder="
                s__('ContinuousDeployment|URL (e.g. registry.example.com/acme/api-gateway)')
              "
              :state="getInputState(artifact.sourceRef)"
              :aria-label="s__('ContinuousDeployment|Artifact URL')"
            />
            <gl-button
              category="tertiary"
              :disabled="artifacts.length === 1"
              icon="remove"
              variant="danger"
              :aria-label="s__('ContinuousDeployment|Remove')"
              data-testid="remove-artifact"
              @click="removeArtifact(index)"
            />
          </li>
        </ul>
        <div role="status">
          <div
            v-if="showEmptyArtifactsError"
            class="gl-mt-2 gl-text-danger"
            data-testid="empty-artifacts-error"
          >
            {{ s__('ContinuousDeployment|Artifact details must not be empty.') }}
          </div>
        </div>
        <div class="gl-mb-2 gl-mt-4 gl-flex gl-justify-end">
          <gl-button
            category="tertiary"
            size="small"
            data-testid="cancel-service"
            @click="cancelService"
          >
            {{ s__('ContinuousDeployment|Cancel') }}
          </gl-button>
          <gl-button variant="confirm" size="small" data-testid="add-service" @click="addService">
            {{ serviceFormButton }}
          </gl-button>
        </div>
      </div>
      <div role="status">
        <div
          v-if="showEmptyServicesError"
          class="gl-mt-2 gl-text-danger"
          data-testid="empty-services-error"
        >
          {{ s__('ContinuousDeployment|Add at least one service.') }}
        </div>
      </div>

      <template #footer>
        <div class="gl-flex gl-justify-end gl-gap-3">
          <gl-button data-testid="cancel-button" @click="closePanel">
            {{ __('Cancel') }}
          </gl-button>
          <gl-button
            :loading="isSubmitting"
            variant="confirm"
            data-testid="register-button"
            @click="submitForm"
          >
            {{ s__('ContinuousDeployment|Register application') }}
          </gl-button>
        </div>
      </template>
    </dynamic-panel>
  </mounting-portal>
</template>
