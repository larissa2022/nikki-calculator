export const CANDIDATE_EXCLUSION_STATUS = Object.freeze({
  ACTIVE: 'active',
  SCHEDULED: 'scheduled',
  EXPIRED: 'expired',
  REVOKED: 'revoked',
  INVALID: 'invalid'
})

const parseTimestamp = (value) => {
  const timestamp = Date.parse(value)
  return Number.isFinite(timestamp) ? timestamp : null
}

export const getCandidateExclusionStatus = (exclusion, now = Date.now()) => {
  if (exclusion?.revoked_at) return CANDIDATE_EXCLUSION_STATUS.REVOKED

  const startsAt = parseTimestamp(exclusion?.starts_at)
  const endsAt = parseTimestamp(exclusion?.ends_at)
  if (startsAt === null || endsAt === null || endsAt <= startsAt) {
    return CANDIDATE_EXCLUSION_STATUS.INVALID
  }
  if (endsAt <= now) return CANDIDATE_EXCLUSION_STATUS.EXPIRED
  if (startsAt > now) return CANDIDATE_EXCLUSION_STATUS.SCHEDULED
  return CANDIDATE_EXCLUSION_STATUS.ACTIVE
}

export const canRevokeCandidateExclusion = (exclusion, now = Date.now()) => {
  const status = getCandidateExclusionStatus(exclusion, now)
  return status === CANDIDATE_EXCLUSION_STATUS.ACTIVE
    || status === CANDIDATE_EXCLUSION_STATUS.SCHEDULED
}

export const groupCandidateExclusions = (exclusions, now = Date.now()) => {
  const current = []
  const history = []

  for (const exclusion of Array.isArray(exclusions) ? exclusions : []) {
    const item = {
      ...exclusion,
      view_status: getCandidateExclusionStatus(exclusion, now)
    }
    if (canRevokeCandidateExclusion(exclusion, now)) current.push(item)
    else history.push(item)
  }

  return { current, history }
}
