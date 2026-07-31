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
    terms: Array.isArray(data?.terms) ? data.terms : [],
    exclusions: Array.isArray(data?.exclusions) ? data.exclusions : [],
    candidates: Array.isArray(data?.candidates) ? data.candidates : [],
    decisions: Array.isArray(data?.decisions) ? data.decisions : []
  }
}

export const createManualAdminTerm = (payload) => rpc('create_manual_admin_term', {
  p_user_id: payload.userId,
  p_reason: payload.reason,
  p_ends_at: payload.endsAt
})

export const endAdminTerm = (termId, reason) => rpc('end_admin_term', {
  p_term_id: termId,
  p_reason: reason
})

export const leaveCurrentAdminTerm = () => rpc('leave_current_admin_term')

export const createAdminCandidateExclusion = (payload) => rpc('create_admin_candidate_exclusion', {
  p_user_id: payload.userId,
  p_reason: payload.reason,
  p_starts_at: payload.startsAt,
  p_ends_at: payload.endsAt
})

export const revokeAdminCandidateExclusion = (exclusionId) => (
  rpc('revoke_admin_candidate_exclusion', { p_exclusion_id: exclusionId })
)
