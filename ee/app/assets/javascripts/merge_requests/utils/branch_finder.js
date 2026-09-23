import { projectTargetBranchRulesPath } from 'ee/lib/utils/path_helpers/project';
import axios from '~/lib/utils/axios_utils';

export const findTargetBranch = async (projectPath, branch, cancelToken) => {
  try {
    const { data } = await axios.get(projectTargetBranchRulesPath(projectPath), {
      params: { branch_name: branch },
      cancelToken,
    });

    return data.target_branch;
  } catch {
    return null;
  }
};
