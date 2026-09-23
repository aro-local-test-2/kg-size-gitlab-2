import { NAMESPACE_TYPE_ORGANIZATION } from 'ee/policy_store/components/editor/constants';
import initPolicyStoreEditor from 'ee/policy_store/editor';

initPolicyStoreEditor(document.getElementById('js-policy-store'), NAMESPACE_TYPE_ORGANIZATION);
