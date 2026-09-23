import { commitPath } from 'ee/packages_and_registries/artifact_registry/utils';
import { truncateSha } from '~/lib/utils/text_utility';
import { s__ } from '~/locale';

const PUBLISHED = s__('ArtifactRegistry|Published');

const PROJECT_BY_AUTHOR = s__('ArtifactRegistry|Published to %{project} by %{author}');

const PROJECT_ONLY = s__('ArtifactRegistry|Published to %{project}');

const AUTHOR_ONLY = s__('ArtifactRegistry|Published by %{author}');

const attributionMessage = ({ project, author, fromCommit }) => {
  const namesAuthor = Boolean(author) && fromCommit;

  if (project) return namesAuthor ? PROJECT_BY_AUTHOR : PROJECT_ONLY;

  return namesAuthor ? AUTHOR_ONLY : null;
};

export const sourceOf = ({ gitCommitSha, project, createdBy }) => {
  const author = createdBy?.name ?? null;

  return {
    sha: gitCommitSha ? truncateSha(gitCommitSha) : null,
    commitPath: commitPath({ project, gitCommitSha }),
    project,
    author,
    originMessage: author ? AUTHOR_ONLY : PUBLISHED,
    attributionMessage: attributionMessage({
      project,
      author,
      fromCommit: Boolean(gitCommitSha),
    }),
  };
};

export const hasSource = ({ gitCommitSha, project, createdBy }) =>
  Boolean(gitCommitSha || project || createdBy);
