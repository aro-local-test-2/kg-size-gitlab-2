import Vue from 'vue';
import PipelineAccountVerificationAlert from 'ee/vue_shared/components/pipeline_account_verification_alert.vue';
import { parseBoolean } from '~/lib/utils/common_utils';
import { s__ } from '~/locale';

export function initVerificationAlert() {
  const el = document.querySelector('.js-verification-alert');

  if (!el) {
    return null;
  }

  return new Vue({
    el,
    name: 'PipelineAccountVerificationAlertRoot',
    provide: {
      identityVerificationRequired: parseBoolean(el.dataset.identityVerificationRequired),
      identityVerificationPath: el.dataset.identityVerificationPath,
    },
    render(createElement) {
      return createElement(PipelineAccountVerificationAlert, {
        props: {
          title: s__('IdentityVerification|Verify your identity to run this pipeline'),
          description: s__(
            'IdentityVerification|This step is separate from the verification you completed during registration.',
          ),
          buttonText: s__('IdentityVerification|Verify identity'),
        },
        class: 'gl-mt-3',
      });
    },
  });
}
