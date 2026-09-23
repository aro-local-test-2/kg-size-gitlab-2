<script>
import { GlButton, GlFormGroup, GlFormInput } from '@gitlab/ui';
import { formValidators } from '@gitlab/ui/src/utils';
import { omit } from 'lodash-es';
import { createAlert } from '~/alert';
import { s__ } from '~/locale';
import {
  REPOSITORY_CACHE_VALIDITY_DEFAULT,
  REPOSITORY_CACHE_VALIDITY_MAX,
  REPOSITORY_CACHE_VALIDITY_MIN,
  REPOSITORY_FORMAT_NPM,
  REPOSITORY_HEALTH_STATUS_UNKNOWN,
  REPOSITORY_METADATA_CACHE_VALIDITY_MIN,
} from '../../constants';
import testRepositoryConnectionMutation from '../../graphql/mutations/test_repository_connection.mutation.graphql';
import testUpstreamConnectionMutation from '../../graphql/mutations/test_upstream_connection.mutation.graphql';
import { isContainerFormat } from '../../utils';
import ConnectionIndicator from './connection_indicator.vue';
import ConnectionTestResult from './connection_test_result.vue';

const FIELD_URL = 'url';

const CREDENTIAL_USERNAME = 'username';
const CREDENTIAL_PASSWORD = 'password';
const CREDENTIAL_AUTH_TOKEN = 'authToken';

const FIELD_CACHE_VALIDITY = 'cacheValidityHours';
const FIELD_METADATA_CACHE_VALIDITY = 'metadataCacheValidityHours';

const initialWindow = (stored) => stored ?? '';

export default {
  name: 'ArtifactRegistryRemoteSourceSection',
  i18n: {
    heading: s__('ArtifactRegistry|Source'),
    urlLabel: s__('ArtifactRegistry|URL'),
    urlRequired: s__('ArtifactRegistry|URL is required.'),
    urlDescription: s__(
      'ArtifactRegistry|You can add GitLab-hosted repositories as upstreams. Use your GitLab username and a personal access token as the password.',
    ),
    authenticationHeading: s__('ArtifactRegistry|Authentication (optional)'),
    authenticationDescription: s__(
      'ArtifactRegistry|Required only if the upstream registry is private or rate-limited. Credentials are stored encrypted.',
    ),
    usernameLabel: s__('ArtifactRegistry|Username'),
    passwordLabel: s__('ArtifactRegistry|Token or password'),
    tokenLabel: s__('ArtifactRegistry|Access token'),
    cacheLabel: s__('ArtifactRegistry|Artifact caching period'),
    cacheRequired: s__('ArtifactRegistry|Artifact caching period is required.'),
    cacheDescription: s__('ArtifactRegistry|Time in hours'),
    metadataCacheLabel: s__('ArtifactRegistry|Metadata caching period'),
    metadataCacheRequired: s__('ArtifactRegistry|Metadata caching period is required.'),
    metadataCacheDescription: s__('ArtifactRegistry|Time in hours'),
    credentialsIncomplete: s__(
      'ArtifactRegistry|Enter both a username and a token or password, or leave both empty to keep the stored credentials.',
    ),
    testConnection: s__('ArtifactRegistry|Test upstream connection'),
    testingConnection: s__('ArtifactRegistry|Testing upstream connection'),
    unavailable: s__('ArtifactRegistry|The Artifact Registry service is unavailable.'),
  },
  components: {
    ConnectionIndicator,
    ConnectionTestResult,
    GlButton,
    GlFormGroup,
    GlFormInput,
  },
  props: {
    format: {
      type: String,
      required: true,
    },
    name: {
      type: String,
      required: false,
      default: '',
    },
    settings: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    createMode: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['input'],
  data() {
    return {
      url: this.settings.url ?? '',
      cacheValidityHours: initialWindow(this.settings.cacheValidityHours),
      metadataCacheValidityHours: initialWindow(this.settings.metadataCacheValidityHours),
      username: '',
      password: '',
      token: '',
      fieldDirtyStatuses: {},
      testing: false,
      testResult: null,
      probedVerdict: null,
    };
  },
  computed: {
    validators() {
      const { cacheRequired, credentialsIncomplete, metadataCacheRequired, urlRequired } =
        this.$options.i18n;
      const present = (value) => String(value).trim() !== '';

      return {
        [FIELD_URL]: formValidators.factory(urlRequired, (value) => Boolean(value.trim())),
        [FIELD_CACHE_VALIDITY]: formValidators.factory(cacheRequired, present),
        [FIELD_METADATA_CACHE_VALIDITY]: formValidators.factory(metadataCacheRequired, present),
        [CREDENTIAL_USERNAME]: formValidators.factory(
          credentialsIncomplete,
          (value) => Boolean(value) || !this.password,
        ),
        [CREDENTIAL_PASSWORD]: formValidators.factory(
          credentialsIncomplete,
          (value) => Boolean(value) || !this.username,
        ),
      };
    },
    errors() {
      return {
        [FIELD_URL]: this.validators[FIELD_URL](this.url),
        ...this.credentialErrors,
        ...this.windowErrors,
      };
    },
    credentialErrors() {
      if (this.takesToken) return {};

      return {
        [CREDENTIAL_USERNAME]: this.validators[CREDENTIAL_USERNAME](this.username),
        [CREDENTIAL_PASSWORD]: this.validators[CREDENTIAL_PASSWORD](this.password),
      };
    },
    windowErrors() {
      if (this.createMode) return {};

      return {
        [FIELD_CACHE_VALIDITY]: this.validators[FIELD_CACHE_VALIDITY](this.cacheValidityHours),
        ...(this.hasMetadataWindow
          ? {
              [FIELD_METADATA_CACHE_VALIDITY]: this.validators[FIELD_METADATA_CACHE_VALIDITY](
                this.metadataCacheValidityHours,
              ),
            }
          : {}),
      };
    },
    urlState() {
      return this.stateOf(FIELD_URL);
    },
    cacheValidityState() {
      return this.stateOf(FIELD_CACHE_VALIDITY);
    },
    metadataCacheValidityState() {
      return this.stateOf(FIELD_METADATA_CACHE_VALIDITY);
    },
    hasMetadataWindow() {
      return !isContainerFormat(this.format);
    },
    takesToken() {
      return this.format === REPOSITORY_FORMAT_NPM;
    },
    credentials() {
      if (this.takesToken) {
        return this.token ? { [CREDENTIAL_AUTH_TOKEN]: this.token } : null;
      }

      if (!this.username || !this.password) return null;

      return {
        [CREDENTIAL_USERNAME]: this.username,
        [CREDENTIAL_PASSWORD]: this.password,
      };
    },
    usernameState() {
      return this.stateOf(CREDENTIAL_USERNAME);
    },
    passwordState() {
      return this.stateOf(CREDENTIAL_PASSWORD);
    },
    verdict() {
      return (
        this.probedVerdict ?? {
          healthStatus: this.settings.lastHealthStatus ?? REPOSITORY_HEALTH_STATUS_UNKNOWN,
          lastHealthCheckedAt: this.settings.lastHealthCheckedAt ?? null,
        }
      );
    },
    testConnectionText() {
      return this.testing
        ? this.$options.i18n.testingConnection
        : this.$options.i18n.testConnection;
    },
    hasIncompleteCredentials() {
      return Object.values(this.credentialErrors).some(Boolean);
    },
    testDisabled() {
      return (
        this.testing || (this.createMode && (!this.url.trim() || this.hasIncompleteCredentials))
      );
    },
    collectedSettings() {
      return {
        url: this.url.trim(),
        ...this.collectedWindow('cacheValidityHours', this.cacheValidityHours),
        ...(this.hasMetadataWindow
          ? this.collectedWindow('metadataCacheValidityHours', this.metadataCacheValidityHours)
          : {}),
        ...(this.credentials ? { credentials: this.credentials } : {}),
      };
    },
  },
  watch: {
    format() {
      this.username = '';
      this.password = '';
      this.token = '';
      this.fieldDirtyStatuses = omit(this.fieldDirtyStatuses, [
        CREDENTIAL_USERNAME,
        CREDENTIAL_PASSWORD,
      ]);
      this.clearStaleResult();
    },
    url() {
      this.clearStaleResult();
    },
    credentials() {
      this.clearStaleResult();
    },
    collectedSettings: {
      immediate: true,
      handler(settings) {
        this.$emit('input', settings);
      },
    },
  },
  methods: {
    setFieldDirty(field) {
      this.fieldDirtyStatuses = { ...this.fieldDirtyStatuses, [field]: true };
    },
    setAllFieldsDirty() {
      Object.keys(this.errors).forEach((field) => this.setFieldDirty(field));
    },
    stateOf(field) {
      return this.fieldDirtyStatuses[field] && this.errors[field] ? false : null;
    },
    collectedWindow(field, value) {
      if (this.createMode && value === '') return {};

      return { [field]: Number(value) };
    },
    // eslint-disable-next-line vue/no-unused-properties -- public API, called via $refs in repository_form.vue
    validate() {
      this.setAllFieldsDirty();

      return Object.values(this.errors).every((message) => !message);
    },
    clearStaleResult() {
      if (this.createMode) this.testResult = null;
    },
    connectionTestRequest() {
      if (this.createMode) {
        const input = { format: this.format, url: this.url.trim() };
        if (this.credentials) input.credentials = this.credentials;

        return { mutation: testUpstreamConnectionMutation, variables: { input } };
      }

      return {
        mutation: testRepositoryConnectionMutation,
        variables: { input: { name: this.name } },
      };
    },
    async testConnection() {
      if (this.testDisabled) return;

      this.testing = true;
      this.testResult = null;

      try {
        const { mutation, variables } = this.connectionTestRequest();
        const { data } = await this.$apollo.mutate({ mutation, variables });

        const { passed, httpStatus, errors } = data.testConnection;

        if (errors.length) throw new Error(errors.join(' '));

        this.testResult = { passed, httpStatus };

        if (!this.createMode) {
          const { lastHealthStatus, lastHealthCheckedAt } = data.testConnection;
          this.probedVerdict = { healthStatus: lastHealthStatus, lastHealthCheckedAt };
        }
      } catch (error) {
        createAlert({ message: this.$options.i18n.unavailable, error, captureError: true });
      } finally {
        this.testing = false;
      }
    },
  },
  fieldNames: {
    url: FIELD_URL,
    username: CREDENTIAL_USERNAME,
    password: CREDENTIAL_PASSWORD,
    cacheValidity: FIELD_CACHE_VALIDITY,
    metadataCacheValidity: FIELD_METADATA_CACHE_VALIDITY,
  },
  cacheValidityDefault: String(REPOSITORY_CACHE_VALIDITY_DEFAULT),
  cacheValidityMin: REPOSITORY_CACHE_VALIDITY_MIN,
  metadataCacheValidityMin: REPOSITORY_METADATA_CACHE_VALIDITY_MIN,
  cacheValidityMax: REPOSITORY_CACHE_VALIDITY_MAX,
};
</script>

<template>
  <section class="gl-mb-5" data-testid="remote-source-section">
    <hr class="gl-my-5" />

    <h2 class="gl-heading-4">{{ $options.i18n.heading }}</h2>

    <gl-form-group
      :label="$options.i18n.urlLabel"
      :state="urlState"
      :invalid-feedback="$options.i18n.urlRequired"
      label-for="artifact-registry-remote-source-url"
    >
      <gl-form-input
        id="artifact-registry-remote-source-url"
        v-model="url"
        :state="urlState"
        type="url"
        aria-describedby="artifact-registry-remote-source-url-hint"
        aria-required="true"
        data-testid="remote-source-url"
        @blur="setFieldDirty($options.fieldNames.url)"
      />
      <p
        id="artifact-registry-remote-source-url-hint"
        class="gl-mb-0 gl-mt-2 gl-text-md gl-text-subtle"
      >
        {{ $options.i18n.urlDescription }}
      </p>
    </gl-form-group>

    <fieldset>
      <legend class="gl-mb-0 gl-border-0 gl-text-base gl-font-bold gl-leading-heading">
        {{ $options.i18n.authenticationHeading }}
      </legend>
      <p class="gl-mb-5 gl-text-md gl-text-subtle">{{ $options.i18n.authenticationDescription }}</p>

      <div class="gl-grid gl-grid-cols-2 gl-gap-5">
        <gl-form-group
          v-if="takesToken"
          :label="$options.i18n.tokenLabel"
          label-for="artifact-registry-remote-source-token"
        >
          <gl-form-input
            id="artifact-registry-remote-source-token"
            v-model="token"
            type="password"
            autocomplete="new-password"
            data-testid="remote-source-token"
          />
        </gl-form-group>

        <template v-else>
          <gl-form-group
            :label="$options.i18n.usernameLabel"
            :state="usernameState"
            :invalid-feedback="$options.i18n.credentialsIncomplete"
            label-for="artifact-registry-remote-source-username"
          >
            <gl-form-input
              id="artifact-registry-remote-source-username"
              v-model="username"
              :state="usernameState"
              autocomplete="off"
              data-testid="remote-source-username"
              @blur="setFieldDirty($options.fieldNames.username)"
            />
          </gl-form-group>

          <gl-form-group
            :label="$options.i18n.passwordLabel"
            :state="passwordState"
            :invalid-feedback="$options.i18n.credentialsIncomplete"
            label-for="artifact-registry-remote-source-password"
          >
            <gl-form-input
              id="artifact-registry-remote-source-password"
              v-model="password"
              :state="passwordState"
              type="password"
              autocomplete="new-password"
              data-testid="remote-source-password"
              @blur="setFieldDirty($options.fieldNames.password)"
            />
          </gl-form-group>
        </template>
      </div>
    </fieldset>

    <div class="gl-mb-5 gl-flex gl-flex-col gl-items-start gl-gap-3">
      <gl-button
        category="secondary"
        :loading="testing"
        :disabled="testDisabled"
        data-testid="remote-source-test-connection"
        @click="testConnection"
      >
        {{ testConnectionText }}
      </gl-button>

      <div aria-live="polite" data-testid="connection-test-result-region">
        <connection-test-result
          v-if="testResult"
          :passed="testResult.passed"
          :http-status="testResult.httpStatus"
        />
      </div>

      <connection-indicator
        v-if="!createMode && !testResult"
        :health-status="verdict.healthStatus"
        :last-health-checked-at="verdict.lastHealthCheckedAt"
        inline
      />
    </div>

    <div class="gl-grid gl-grid-cols-2 gl-gap-5">
      <gl-form-group
        :label="$options.i18n.cacheLabel"
        :state="cacheValidityState"
        :invalid-feedback="$options.i18n.cacheRequired"
        label-for="artifact-registry-remote-source-cache-validity"
      >
        <p
          id="artifact-registry-remote-source-cache-validity-hint"
          class="gl-mb-2 gl-text-md gl-text-subtle"
        >
          {{ $options.i18n.cacheDescription }}
        </p>
        <gl-form-input
          id="artifact-registry-remote-source-cache-validity"
          v-model="cacheValidityHours"
          :state="cacheValidityState"
          aria-describedby="artifact-registry-remote-source-cache-validity-hint"
          :placeholder="$options.cacheValidityDefault"
          type="number"
          :min="$options.cacheValidityMin"
          :max="$options.cacheValidityMax"
          data-testid="remote-source-cache-validity"
          @blur="setFieldDirty($options.fieldNames.cacheValidity)"
        />
      </gl-form-group>

      <gl-form-group
        v-if="hasMetadataWindow"
        :label="$options.i18n.metadataCacheLabel"
        :state="metadataCacheValidityState"
        :invalid-feedback="$options.i18n.metadataCacheRequired"
        label-for="artifact-registry-remote-source-metadata-cache-validity"
      >
        <p
          id="artifact-registry-remote-source-metadata-cache-validity-hint"
          class="gl-mb-2 gl-text-md gl-text-subtle"
        >
          {{ $options.i18n.metadataCacheDescription }}
        </p>
        <gl-form-input
          id="artifact-registry-remote-source-metadata-cache-validity"
          v-model="metadataCacheValidityHours"
          :state="metadataCacheValidityState"
          aria-describedby="artifact-registry-remote-source-metadata-cache-validity-hint"
          :placeholder="$options.cacheValidityDefault"
          type="number"
          :min="$options.metadataCacheValidityMin"
          :max="$options.cacheValidityMax"
          data-testid="remote-source-metadata-cache-validity"
          @blur="setFieldDirty($options.fieldNames.metadataCacheValidity)"
        />
      </gl-form-group>
    </div>
  </section>
</template>
