export const JURY_VOTE = {
  APPROVE: 'approve',
  REJECT: 'reject'
}

export const JURY_OUTCOME = {
  APPROVED: 'approved',
  RETURNED: 'returned',
  VOTING: 'voting'
}

export const getJuryOutcome = (approveCount, rejectCount) => {
  const approvals = Number(approveCount) || 0
  const rejections = Number(rejectCount) || 0

  if (approvals >= 5 && approvals > rejections) return JURY_OUTCOME.APPROVED
  if (rejections - approvals >= 3) return JURY_OUTCOME.RETURNED
  return JURY_OUTCOME.VOTING
}

export const getJuryStatusText = (status) => ({
  approved: '已通过',
  returned: '已退回重审',
  rejected: '管理员已永久驳回',
  voting: '投票中',
  pending: '等待候选快照',
  failed: '等待重新整理'
}[status] || '等待处理')
