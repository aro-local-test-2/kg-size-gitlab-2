<script>
import { GlButton } from '@gitlab/ui';
import { MountingPortal } from 'portal-vue';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import DynamicPanel from '~/vue_shared/components/dynamic_panel.vue';

export default {
  name: 'ManageAccessPanel',
  components: {
    CrudComponent,
    DynamicPanel,
    GlButton,
    MountingPortal,
  },
  props: {
    application: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    open: {
      type: Boolean,
      required: true,
    },
  },
  emits: ['close'],
  methods: {
    closePanel() {
      this.$emit('close');
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
            {{ s__('ContinuousDeployment|Access for') }}
          </p>
          <h2 class="gl-my-0 gl-text-base">
            {{ application.name }}
          </h2>
        </div>
      </template>

      <crud-component
        class="gl-mt-5"
        :title="s__('ContinuousDeployment|Direct members')"
        title-tag="h3"
      >
        <template #actions>
          <gl-button size="small">
            {{ s__('ContinuousDeployment|Add members') }}
          </gl-button>
        </template>
      </crud-component>

      <crud-component
        class="gl-mt-5"
        :title="s__('ContinuousDeployment|Inherited members')"
        title-tag="h3"
      >
        <template #actions>
          <gl-button size="small">
            {{ s__('ContinuousDeployment|Manage access') }}
          </gl-button>
        </template>
      </crud-component>
    </dynamic-panel>
  </mounting-portal>
</template>
