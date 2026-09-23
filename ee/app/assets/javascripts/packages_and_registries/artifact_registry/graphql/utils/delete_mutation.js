import { createAlert } from '~/alert';
import { __ } from '~/locale';

const payloadKeyOf = (mutation) => {
  const operation = mutation.definitions.find(({ kind }) => kind === 'OperationDefinition');
  const [field] = operation.selectionSet.selections;

  return (field.alias ?? field.name).value;
};

export const executeDeleteMutation = async (apollo, { mutation, input, ...options }) => {
  try {
    const { data } = await apollo.mutate({
      mutation,
      variables: { input },
      ...options,
    });

    const { errors } = data[payloadKeyOf(mutation)];

    if (errors.length) {
      createAlert({ message: errors.join(' ') });
      return false;
    }

    return true;
  } catch (error) {
    createAlert({
      message: __('Something went wrong. Please try again.'),
      error,
      captureError: true,
    });
    return false;
  }
};
