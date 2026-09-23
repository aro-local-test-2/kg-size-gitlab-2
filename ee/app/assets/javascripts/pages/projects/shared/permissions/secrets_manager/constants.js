import { s__ } from '~/locale';

export const PERMISSION_CATEGORY_ROLE = 'ROLE';
export const PERMISSION_CATEGORY_USER = 'USER';

export const SCOPE_ORDER = ['READ', 'READ_VALUE', 'WRITE', 'DELETE'];
export const SCOPE_LABELS = {
  READ: s__('SecretsManagerPermissions|Read metadata'),
  READ_VALUE: s__('SecretsManagerPermissions|Read value'),
  WRITE: s__('SecretsManagerPermissions|Write'),
  DELETE: s__('SecretsManagerPermissions|Delete'),
};

export const ALERT_CONTAINER_CLASSNAME = 'js-secrets-manager-permissions-alert-container';
export const ALERT_CONTAINER_SELECTOR = `.${ALERT_CONTAINER_CLASSNAME}`;
