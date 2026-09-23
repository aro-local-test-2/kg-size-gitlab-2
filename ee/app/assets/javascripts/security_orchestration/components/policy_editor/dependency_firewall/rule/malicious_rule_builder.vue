<script>
import { GlAlert, GlFormGroup } from '@gitlab/ui';
import { s__ } from '~/locale';
import { exceptionsToLines, ruleWithUpdatedExceptions } from '../utils';
import NameListTextarea from './name_list_textarea.vue';

export default {
  name: 'MaliciousRuleBuilder',
  components: { GlAlert, GlFormGroup, NameListTextarea },
  i18n: {
    explanation: s__(
      'SecurityOrchestration|This rule is active as soon as it appears in the rules list, and always denies packages flagged by the malicious packages data feed - it cannot be switched to an allow list. To turn it off, remove this rule using the button on the right.',
    ),
    exceptionsLabel: s__('SecurityOrchestration|Exceptions'),
    exceptionsPlaceholder: s__(
      'SecurityOrchestration|Enter package URLs (PURLs) to exempt, separated by commas',
    ),
  },
  props: {
    initRule: {
      type: Object,
      required: true,
    },
  },
  emits: ['changed'],
  computed: {
    exceptionLines() {
      return exceptionsToLines(this.initRule.exceptions || []);
    },
  },
  methods: {
    handleExceptionsChange(lines) {
      this.$emit('changed', ruleWithUpdatedExceptions(this.initRule, lines));
    },
  },
};
</script>

<template>
  <div class="gl-w-full">
    <gl-alert :dismissible="false" variant="info" class="gl-mb-3">
      {{ $options.i18n.explanation }}
    </gl-alert>

    <gl-form-group :label="$options.i18n.exceptionsLabel" class="gl-w-full">
      <name-list-textarea
        :items="exceptionLines"
        :placeholder="$options.i18n.exceptionsPlaceholder"
        @input="handleExceptionsChange"
      />
    </gl-form-group>
  </div>
</template>
