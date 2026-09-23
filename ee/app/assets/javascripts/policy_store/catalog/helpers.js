import { FIELD_TYPE_CODE, FIELD_TYPE_FREEZE_WINDOWS } from '../components/editor/constants';

const configEntryLabel = (field, entry) => {
  if (field.type === FIELD_TYPE_FREEZE_WINDOWS) {
    // Not ', ': that separator already divides one window from the next, so a
    // multi-tier window would blur into the window after it.
    const tiers = (entry.tiers || [])
      .map((tier) => field.options?.find((option) => option.id === tier)?.label ?? tier)
      .join(' / ');
    const bounds = [entry.starts_at, entry.ends_at].filter(Boolean).join(' → ');

    return [entry.name, tiers, bounds].filter(Boolean).join(' · ');
  }

  return field.options?.find((option) => option.id === entry)?.label ?? String(entry);
};

const configValueFor = (field, value) => {
  const values = Array.isArray(value) ? value : [value];
  const labelled = values
    .filter((entry) => entry !== undefined && entry !== null && entry !== '')
    .map((entry) => configEntryLabel(field, entry))
    .filter(Boolean);

  return labelled.join(', ');
};

/**
 * Resolves an entry's persisted config into displayable items through the
 * catalog's field definitions, mirroring what the editor's form shows.
 */
export const configItemsFor = (entry, config = {}) =>
  (entry.fields || [])
    .map((field) => ({
      key: field.key,
      label: field.label,
      code: field.type === FIELD_TYPE_CODE,
      value: configValueFor(field, config[field.key]),
    }))
    .filter(({ value }) => value !== '');

// A persisted id the catalog no longer knows still resolves to its raw id
// rather than disappearing from read-only summaries.
export const resolveCatalogEntry = (catalog, id, config = {}) => {
  const entry = catalog.find((candidate) => candidate.id === id) ?? {
    id,
    label: id,
    description: '',
    icon: 'question-o',
  };

  return { ...entry, configItems: configItemsFor(entry, config) };
};
