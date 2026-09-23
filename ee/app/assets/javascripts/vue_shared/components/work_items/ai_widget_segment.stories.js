import AiWidgetSegment from './ai_widget_segment.vue';

export default {
  component: AiWidgetSegment,
  title: 'ee/vue_shared/work_items/ai_widget_segment',
  argTypes: {
    label: { control: { type: 'text' } },
  },
};

const Template = (args) => ({
  components: { AiWidgetSegment },
  props: Object.keys(args),
  template: `
    <ai-widget-segment v-bind="$props">
      <span class="gl-text-subtle">No decisions yet</span>
    </ai-widget-segment>
  `,
});

export const Default = Template.bind({});
Default.args = {
  label: 'Decision log',
};

// The help popover the confidence score puts next to its label.
export const WithLabelAppend = () => ({
  components: { AiWidgetSegment },
  template: `
    <ai-widget-segment label="Confidence">
      <template #label-append>
        <button type="button" aria-label="What is the confidence score?">?</button>
      </template>
      <span>High</span>
    </ai-widget-segment>
  `,
});

// How the segments read side by side in the AI planning metadata row.
export const MetadataRow = () => ({
  components: { AiWidgetSegment },
  template: `
    <div class="gl-flex gl-gap-6">
      <ai-widget-segment label="Workplan"><span>Ready</span></ai-widget-segment>
      <ai-widget-segment label="Confidence"><span>High</span></ai-widget-segment>
      <ai-widget-segment label="Decision log">
        <span class="gl-text-subtle">No decisions yet</span>
      </ai-widget-segment>
    </div>
  `,
});
