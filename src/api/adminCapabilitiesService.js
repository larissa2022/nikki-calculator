import { supabase } from './supabase.js'
import { normalizeAdminCapabilities } from '../utils/adminCapabilities.js'

const rpc = async (name, args) => {
  const { data, error } = await supabase.rpc(name, args)
  if (error) throw error
  return data
}

export const fetchAdminCapabilities = async () => (
  normalizeAdminCapabilities(await rpc('get_current_admin_capabilities'))
)

export const fetchLowRiskReviewCandidates = async () => {
  const data = await rpc('list_low_risk_clothes_review_candidates')
  return Array.isArray(data) ? data : []
}

export const reviewLowRiskCandidate = (representativePendingId, action, reason = null) => (
  rpc('review_low_risk_clothes_candidate', {
    p_representative_pending_id: representativePendingId,
    p_action: action,
    p_reason: reason
  })
)

export const fetchMyRejectedClothingSubmissions = async () => {
  const data = await rpc('get_my_rejected_clothing_submissions')
  return Array.isArray(data) ? data : []
}

export const fetchAdminGovernance = async () => {
  const data = await rpc('list_admin_governance')
  return {
    users: Array.isArray(data?.users) ? data.users : [],
    terms: Array.isArray(data?.terms) ? data.terms : [],
    exclusions: Array.isArray(data?.exclusions) ? data.exclusions : [],
    candidates: Array.isArray(data?.candidates) ? data.candidates : [],
    decisions: Array.isArray(data?.decisions) ? data.decisions : [],
    communityActions: Array.isArray(data?.community_actions) ? data.community_actions : []
  }
}

const submitGovernanceAction = (payload) => rpc('submit_admin_governance_action', {
  p_action_type: payload.actionType,
  p_target_user_id: payload.userId || null,
  p_target_record_id: payload.recordId || null,
  p_reason: payload.reason,
  p_starts_at: payload.startsAt || null,
  p_ends_at: payload.endsAt || null
})

export const createManualAdminTerm = (payload) => submitGovernanceAction({
  actionType: 'manual_term_create',
  userId: payload.userId,
  reason: payload.reason,
  endsAt: payload.endsAt
})

export const endAdminTerm = (termId, reason) => submitGovernanceAction({
  actionType: 'term_end',
  recordId: termId,
  reason
})

export const leaveCurrentAdminTerm = () => rpc('leave_current_admin_term')

export const createAdminCandidateExclusion = (payload) => submitGovernanceAction({
  actionType: 'candidate_exclusion_create',
  userId: payload.userId,
  reason: payload.reason,
  startsAt: payload.startsAt,
  endsAt: payload.endsAt
})

export const revokeAdminCandidateExclusion = (exclusionId, reason) => submitGovernanceAction({
  actionType: 'candidate_exclusion_revoke',
  recordId: exclusionId,
  reason
})

export const fetchCommunitySuitReviewQueue = async () => {
  const data = await rpc('list_pending_suits_for_review')
  return Array.isArray(data) ? data : []
}

export const reviewCommunitySuit = (name, decision, reason = null) => rpc('review_pending_suit', {
  p_name: name,
  p_decision: decision,
  p_reason: reason
})

export const fetchRejectedJuryItemsForReopen = async () => {
  const data = await rpc('list_rejected_jury_items_for_reopen')
  return Array.isArray(data) ? data : []
}

export const reopenRejectedJuryCandidate = (candidateId, reason) => rpc('reopen_rejected_jury_candidate', {
  p_candidate_id: candidateId,
  p_reason: reason
})
