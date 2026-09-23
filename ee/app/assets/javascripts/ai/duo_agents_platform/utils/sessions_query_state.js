// Survives the sessions index component unmounting when the user opens a session detail page,
// so returning to the list restores state instead of resetting. Keyed by context (project path
// or 'user') so cursors and filters never leak between different lists.
const store = new Map();

export const saveSessionsQueryVariables = (key, variables) => {
  store.set(key, variables);
};

export const getSessionsQueryVariables = (key) => store.get(key) ?? null;
