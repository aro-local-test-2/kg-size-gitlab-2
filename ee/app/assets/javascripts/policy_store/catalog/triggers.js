import { s__ } from '~/locale';
import { CATEGORY_DEPLOYMENT } from './categories';

// Triggers a policy can respond to. `id` is persisted as the policy's `trigger_type`, so it
// is the wire value and must match what the metadata endpoint returns.
//
// The CD deployment gate experiment ships the three deployment lifecycle triggers.
// See https://gitlab.com/gitlab-org/gitlab/-/issues/607341 for scope.
export const TRIGGER_DEPLOYMENT_REQUESTED = 'deployment_requested';
export const TRIGGER_ENVIRONMENT_ADVANCED = 'environment_advanced';
export const TRIGGER_DEPLOYMENT_PROMOTED = 'deployment_promoted';

export const TRIGGERS = [
  {
    id: TRIGGER_DEPLOYMENT_REQUESTED,
    category: CATEGORY_DEPLOYMENT,
    label: s__('PolicyStore|Deployment requested'),
    description: s__('PolicyStore|When a deployment to a gated environment is requested'),
    icon: 'deployments',
    fields: [],
  },
  {
    id: TRIGGER_ENVIRONMENT_ADVANCED,
    category: CATEGORY_DEPLOYMENT,
    label: s__('PolicyStore|Environment advanced'),
    description: s__('PolicyStore|When a deployment advances to the next environment'),
    icon: 'environment',
    fields: [],
  },
  {
    id: TRIGGER_DEPLOYMENT_PROMOTED,
    category: CATEGORY_DEPLOYMENT,
    label: s__('PolicyStore|Deployment promoted'),
    description: s__('PolicyStore|When an existing deployment is promoted to a new environment'),
    icon: 'upgrade',
    fields: [],
  },
];
