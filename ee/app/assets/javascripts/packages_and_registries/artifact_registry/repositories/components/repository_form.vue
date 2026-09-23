<script>
import {
  GlButton,
  GlCollapsibleListbox,
  GlForm,
  GlFormFields,
  GlFormRadio,
  GlFormRadioGroup,
  GlFormTextarea,
  GlIcon,
} from '@gitlab/ui';
import { formValidators } from '@gitlab/ui/src/utils';
import { __, n__, s__, sprintf } from '~/locale';
import ErrorsAlert from '~/vue_shared/components/errors_alert.vue';
import {
  REPOSITORIES_LIST_ROUTE_NAME,
  REPOSITORY_DESCRIPTION_MAX_LENGTH,
  REPOSITORY_FORMAT_LABELS,
  REPOSITORY_FORMAT_LOGO_SIZE_LISTBOX,
  REPOSITORY_FORMAT_OPTIONS,
  REPOSITORY_KIND_HOSTED,
  REPOSITORY_KIND_NAME_PLACEHOLDERS,
  REPOSITORY_KIND_REMOTE,
  REPOSITORY_KIND_VIRTUAL,
  REPOSITORY_NAME_MAX_LENGTH,
  REPOSITORY_NAME_PATTERN,
  REPOSITORY_VISIBILITY_DESCRIPTIONS,
  REPOSITORY_VISIBILITY_ICONS,
  REPOSITORY_VISIBILITY_LABELS,
  REPOSITORY_VISIBILITY_PRIVATE,
} from '../../constants';
import FormatLogo from './format_logo.vue';
import RemoteSourceSection from './remote_source_section.vue';
import UpstreamRepositoriesSection from './upstream_repositories_section.vue';

const FORM_ID = 'artifact-registry-repository-form';

export default {
  name: 'ArtifactRegistryRepositoryForm',
  i18n: {
    formatLabel: s__('ArtifactRegistry|Format'),
    formatDescription: s__(
      'ArtifactRegistry|The format cannot be changed after the repository is created.',
    ),
    virtualFormatDescription: s__(
      'ArtifactRegistry|The format cannot be changed after the repository is created. Upstream repositories must use the same format.',
    ),
    nameLabel: s__('ArtifactRegistry|Repository name'),
    nameRequired: s__('ArtifactRegistry|Repository name is required.'),
    nameDescription: s__(
      'ArtifactRegistry|Lowercase letters, numbers, hyphens (-), and underscores (_) only. The repository name cannot be changed after creation.',
    ),
    nameInvalid: s__(
      'ArtifactRegistry|Name must use lowercase letters, digits, periods, underscores, and hyphens, and start and end with a letter or digit.',
    ),
    nameTooLong: sprintf(
      s__('ArtifactRegistry|Name cannot be longer than %{maxLength} characters.'),
      { maxLength: REPOSITORY_NAME_MAX_LENGTH },
    ),
    descriptionLabel: s__('ArtifactRegistry|Description (optional)'),
    descriptionTooLong: sprintf(
      s__('ArtifactRegistry|Description cannot be longer than %{maxLength} characters.'),
      { maxLength: REPOSITORY_DESCRIPTION_MAX_LENGTH },
    ),
    visibilityLabel: s__('ArtifactRegistry|Visibility level'),
    cancel: __('Cancel'),
  },
  components: {
    ErrorsAlert,
    FormatLogo,
    GlButton,
    GlCollapsibleListbox,
    GlForm,
    GlFormFields,
    GlFormRadio,
    GlFormRadioGroup,
    GlFormTextarea,
    GlIcon,
    RemoteSourceSection,
    UpstreamRepositoriesSection,
  },
  props: {
    repository: {
      type: Object,
      required: true,
    },
    submitText: {
      type: String,
      required: true,
    },
    submitting: {
      type: Boolean,
      required: false,
      default: false,
    },
    errorMessages: {
      type: Array,
      required: false,
      default: () => [],
    },
    // Read-only rather than disabled: a disabled input leaves the tab order and some
    // screen readers skip it, so the name a viewer cannot change would also be a name
    // they cannot reach.
    nameReadonly: {
      type: Boolean,
      required: false,
      default: false,
    },
    showFormat: {
      type: Boolean,
      required: false,
      default: true,
    },
    showVisibility: {
      type: Boolean,
      required: false,
      default: false,
    },
    createMode: {
      type: Boolean,
      required: false,
      default: false,
    },
    // The placeholder is an example name, so it names the kind being created. Edit passes
    // none: the name is read-only there and a placeholder never renders.
    kind: {
      type: String,
      required: false,
      default: REPOSITORY_KIND_HOSTED,
    },
    // Cancel returns the viewer to wherever the flow started, which differs by mode: a
    // create has no repository to go back to, an edit does. The page that owns the flow
    // decides, the same way it decides the submit label and which fields to show.
    cancelRoute: {
      type: Object,
      required: false,
      default: () => ({ name: REPOSITORIES_LIST_ROUTE_NAME }),
    },
    upstreamRepositories: {
      type: Array,
      required: false,
      default: () => [],
    },
  },
  emits: ['submit', 'dismiss-errors'],
  data() {
    return {
      values: {
        format: this.repository.format ?? REPOSITORY_FORMAT_OPTIONS[0].value,
        name: this.repository.name ?? '',
        description: this.repository.description ?? '',
        visibility: this.repository.visibility ?? REPOSITORY_VISIBILITY_PRIVATE,
      },
      remoteSettings: null,
      upstreamSources: [...this.upstreamRepositories],
    };
  },
  computed: {
    isRemote() {
      const kind = this.createMode ? this.kind : this.repository.kind;

      return kind === REPOSITORY_KIND_REMOTE;
    },
    isVirtual() {
      const kind = this.createMode ? this.kind : this.repository.kind;

      return kind === REPOSITORY_KIND_VIRTUAL;
    },
    formatDescription() {
      const { formatDescription, virtualFormatDescription } = this.$options.i18n;

      return this.isVirtual ? virtualFormatDescription : formatDescription;
    },
    remotePrefill() {
      return this.repository.settings ?? {};
    },
    namePlaceholder() {
      return REPOSITORY_KIND_NAME_PLACEHOLDERS[this.kind];
    },
    fields() {
      return {
        ...(this.showFormat
          ? {
              format: {
                label: this.$options.i18n.formatLabel,
                fieldset: true,
                groupAttrs: {
                  description: this.formatDescription,
                },
              },
            }
          : {}),
        name: {
          label: this.$options.i18n.nameLabel,
          // A field that takes no input cannot become invalid, so it carries no
          // validators.
          validators: this.nameReadonly
            ? []
            : [
                formValidators.required(this.$options.i18n.nameRequired),
                formValidators.factory(this.$options.i18n.nameInvalid, (value) =>
                  REPOSITORY_NAME_PATTERN.test(value),
                ),
                formValidators.factory(
                  this.$options.i18n.nameTooLong,
                  (value) => value.length <= REPOSITORY_NAME_MAX_LENGTH,
                ),
              ],
          inputAttrs: {
            'data-testid': 'repository-name',
            placeholder: this.namePlaceholder,
            readonly: this.nameReadonly,
            // Not `required`: GlFormInput's prop also sets the native attribute, whose
            // validation pre-empts the submit event GlFormFields and the section validate on.
            'aria-required': this.nameReadonly ? null : 'true',
          },
          groupAttrs: {
            description: this.nameReadonly ? null : this.$options.i18n.nameDescription,
          },
        },
        description: {
          label: this.$options.i18n.descriptionLabel,
          validators: [
            formValidators.factory(
              this.$options.i18n.descriptionTooLong,
              (value) => (value || '').length <= REPOSITORY_DESCRIPTION_MAX_LENGTH,
            ),
          ],
        },
        ...(this.showVisibility
          ? {
              visibility: {
                label: this.$options.i18n.visibilityLabel,
                fieldset: true,
              },
            }
          : {}),
      };
    },
    selectedFormat() {
      return this.values.format ?? this.repository.format;
    },
    selectedFormatLabel() {
      return REPOSITORY_FORMAT_LABELS[this.selectedFormat];
    },
  },
  watch: {
    selectedFormat() {
      if (this.createMode) this.upstreamSources = [];
    },
  },
  methods: {
    submit() {
      this.$emit('dismiss-errors');

      if (this.isRemote && !this.$refs.sourceSection.validate()) return;

      this.$emit('submit', {
        ...this.values,
        ...(this.remoteSettings ? { settings: this.remoteSettings } : {}),
      });
    },
    addUpstreamSources(rows) {
      this.upstreamSources = [...this.upstreamSources, ...rows];
    },
    moveUpstreamSource({ from, to }) {
      const next = [...this.upstreamSources];
      const [moved] = next.splice(from, 1);
      next.splice(to, 0, moved);

      this.upstreamSources = next;
    },
    removeUpstreamSource(index) {
      this.upstreamSources = this.upstreamSources.filter((_, position) => position !== index);
    },
  },
  formId: FORM_ID,
  logoSize: REPOSITORY_FORMAT_LOGO_SIZE_LISTBOX,
  formatOptions: REPOSITORY_FORMAT_OPTIONS,
  visibilityOptions: Object.entries(REPOSITORY_VISIBILITY_LABELS).map(([value, text]) => ({
    value,
    text,
    icon: REPOSITORY_VISIBILITY_ICONS[value],
    description: REPOSITORY_VISIBILITY_DESCRIPTIONS[value],
  })),
  descriptionMaxLength: REPOSITORY_DESCRIPTION_MAX_LENGTH,
  charactersRemaining: (count) => n__('%d character remaining.', '%d characters remaining.', count),
  charactersOverLimit: (count) =>
    n__('%d character over limit.', '%d characters over limit.', count),
};
</script>

<template>
  <gl-form :id="$options.formId" class="@md/panel:gl-w-9/12">
    <errors-alert :errors="errorMessages" @dismiss="$emit('dismiss-errors')" />

    <gl-form-fields
      v-model="values"
      :fields="fields"
      :form-id="$options.formId"
      data-testid="repository-form"
      @submit="submit"
    >
      <template #input(format)="{ value, input }">
        <gl-collapsible-listbox
          :selected="value"
          :items="$options.formatOptions"
          :toggle-text="selectedFormatLabel"
          data-testid="repository-format"
          @select="input"
        >
          <!-- The toggle is custom so the chosen format keeps its logo once the list
               closes. `id` belongs on the text, which is what names the toggle. -->
          <template #toggle="{ accessibilityAttributes: { id, ...accessibilityAttributes } }">
            <gl-button
              class="!gl-min-w-26"
              button-text-classes="gl-flex gl-w-full gl-items-center gl-gap-3"
              aria-required="true"
              v-bind="accessibilityAttributes"
            >
              <format-logo
                :format="selectedFormat"
                :size="$options.logoSize"
                data-testid="repository-format-toggle-logo"
              />
              <span :id="id" class="gl-grow gl-text-left">{{ selectedFormatLabel }}</span>
              <gl-icon name="chevron-down" class="gl-button-icon gl-new-dropdown-chevron" />
            </gl-button>
          </template>
          <template #list-item="{ item }">
            <span class="gl-flex gl-items-center gl-gap-3">
              <format-logo
                :format="item.value"
                :size="$options.logoSize"
                data-testid="repository-format-logo"
              />
              {{ item.text }}
            </span>
          </template>
        </gl-collapsible-listbox>
      </template>

      <template #input(description)="{ id, value, input }">
        <gl-form-textarea
          :id="id"
          :value="value"
          :character-count-limit="$options.descriptionMaxLength"
          data-testid="repository-description"
          @input="input"
        >
          <template #remaining-character-count-text="{ count }">
            {{ $options.charactersRemaining(count) }}
          </template>
          <template #character-count-over-limit-text="{ count }">
            {{ $options.charactersOverLimit(count) }}
          </template>
        </gl-form-textarea>
      </template>

      <template #input(visibility)="{ value, input }">
        <gl-form-radio-group :checked="value" data-testid="repository-visibility" @input="input">
          <gl-form-radio
            v-for="option in $options.visibilityOptions"
            :key="option.value"
            :value="option.value"
          >
            <span class="gl-flex gl-items-center gl-gap-2">
              <gl-icon :name="option.icon" variant="subtle" />
              {{ option.text }}
            </span>
            <template #help>{{ option.description }}</template>
          </gl-form-radio>
        </gl-form-radio-group>
      </template>
    </gl-form-fields>

    <remote-source-section
      v-if="isRemote"
      ref="sourceSection"
      :format="selectedFormat"
      :name="repository.name"
      :settings="remotePrefill"
      :create-mode="createMode"
      @input="remoteSettings = $event"
    />

    <upstream-repositories-section
      v-if="isVirtual"
      :format="selectedFormat"
      :sources="upstreamSources"
      @add="addUpstreamSources"
      @move="moveUpstreamSource"
      @remove="removeUpstreamSource"
    />

    <div class="gl-flex gl-gap-3">
      <gl-button
        class="js-no-auto-disable"
        variant="confirm"
        type="submit"
        :loading="submitting"
        data-testid="submit-repository"
      >
        {{ submitText }}
      </gl-button>
      <gl-button :to="cancelRoute" :disabled="submitting" data-testid="cancel-repository">
        {{ $options.i18n.cancel }}
      </gl-button>
    </div>
  </gl-form>
</template>
