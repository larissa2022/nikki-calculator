import { supabase } from './supabase.js'
import { FEATURE_REQUEST_FILTER, normalizeFeatureRequest } from '../utils/featureRequests.js'

export { FEATURE_REQUEST_FILTER, normalizeFeatureRequest } from '../utils/featureRequests.js'

const rpc = async (name, args = {}) => {
  const { data, error } = await supabase.rpc(name, args)
  if (error) throw error
  return data
}

const normalizeList = data => (Array.isArray(data) ? data : [])
  .map(normalizeFeatureRequest)
  .filter(item => item.requestId && item.title && item.description)

export const fetchFeatureRequests = async (filter = FEATURE_REQUEST_FILTER.PENDING) => (
  normalizeList(await rpc('list_feature_requests', {
    p_filter: filter,
    p_limit: 100,
    p_offset: 0
  }))
)

export const fetchMyFeatureRequests = async () => (
  normalizeList(await rpc('get_my_feature_requests'))
)

export const submitFeatureRequest = (title, description) => rpc('submit_feature_request', {
  p_title: title,
  p_description: description
})

export const setFeatureRequestLike = (requestId, liked) => rpc('set_feature_request_like', {
  p_request_id: requestId,
  p_liked: liked
})

export const withdrawFeatureRequest = requestId => rpc('withdraw_feature_request', {
  p_request_id: requestId
})

export const fetchFeatureRequestsForAdmin = async () => (
  normalizeList(await rpc('list_feature_requests_for_admin'))
)

export const moderateFeatureRequest = ({ requestId, action, reason, publicResponse = null, duplicateOf = null }) => (
  rpc('moderate_feature_request', {
    p_request_id: requestId,
    p_action: action,
    p_reason: reason,
    p_public_response: publicResponse,
    p_duplicate_of: duplicateOf
  })
)
