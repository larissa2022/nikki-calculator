export const EMPTY_ADMIN_CAPABILITIES = Object.freeze({
  is_super_admin: false,
  can_review_low_risk: false,
  can_review_suits: false,
  can_permanently_reject: false,
  can_manage_admin_terms: false,
  can_review_high_risk: false,
  term_id: null,
  term_source: null,
  term_ends_at: null,
  show_grant_notice: false
})

export const normalizeAdminCapabilities = (value) => ({
  ...EMPTY_ADMIN_CAPABILITIES,
  ...(value && typeof value === 'object' && !Array.isArray(value) ? value : {}),
  is_super_admin: value?.is_super_admin === true,
  can_review_low_risk: value?.can_review_low_risk === true,
  can_review_suits: value?.can_review_suits === true,
  can_permanently_reject: value?.can_permanently_reject === true,
  can_manage_admin_terms: value?.can_manage_admin_terms === true,
  can_review_high_risk: value?.can_review_high_risk === true,
  show_grant_notice: value?.show_grant_notice === true
})
