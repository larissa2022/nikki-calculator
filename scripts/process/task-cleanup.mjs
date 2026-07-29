import { spawnSync } from 'node:child_process'
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

export const PROTECTED_BRANCHES = new Set(['main', 'develop'])
export const TASK_BRANCH_PATTERN = /^(?:codex|feature|fix|docs)\//
export const REMOTE_REFRESH_ARGS = Object.freeze(['fetch', 'origin', '--prune'])

export const classifyBranchForCleanup = ({
  name,
  isCurrent = false,
  isWorktree = false,
  isMerged = false,
  hasOpenPr = false,
  openPrStateKnown = true
}) => {
  if (PROTECTED_BRANCHES.has(name)) return { category: 'keep', reason: '受保护分支' }
  if (isCurrent) return { category: 'keep', reason: '当前分支' }
  if (isWorktree) return { category: 'keep', reason: '仍被 worktree 使用' }
  if (!openPrStateKnown) return { category: 'review', reason: '无法确认开放 PR' }
  if (hasOpenPr) return { category: 'keep', reason: '仍有开放 PR' }
  if (!isMerged) return { category: 'review', reason: '存在未进入 develop 的提交' }
  if (!TASK_BRANCH_PATTERN.test(name)) return { category: 'review', reason: '不是项目任务分支命名' }
  return { category: 'safe', reason: '已合并任务分支' }
}

const run = (command, args, { cwd = process.cwd(), allowFailure = false } = {}) => {
  const result = spawnSync(command, args, {
    cwd,
    encoding: 'utf8',
    windowsHide: true
  })
  if (!allowFailure && result.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} 失败：${String(result.stderr || result.stdout).trim()}`)
  }
  return result
}

const git = (args, options) => run('git', args, options)
const gh = (args, options) => run('gh', args, options)

const listRefs = (prefix, cwd) => {
  const output = git([
    'for-each-ref',
    '--format=%(refname:short)\t%(objectname)',
    prefix
  ], { cwd }).stdout.trim()
  if (!output) return []
  return output.split(/\r?\n/).map(line => {
    const [name, sha] = line.split('\t')
    return { name, sha }
  })
}

const getCurrentBranch = cwd => git(['branch', '--show-current'], { cwd }).stdout.trim()

const getWorktreeBranches = cwd => {
  const output = git(['worktree', 'list', '--porcelain'], { cwd }).stdout
  return new Set(
    output.split(/\r?\n/)
      .filter(line => line.startsWith('branch refs/heads/'))
      .map(line => line.slice('branch refs/heads/'.length))
  )
}

const getOpenPrHeads = cwd => {
  const result = gh([
    'pr', 'list', '--state', 'open', '--limit', '200', '--json', 'headRefName'
  ], { cwd, allowFailure: true })
  if (result.status !== 0) return null
  return new Set(JSON.parse(result.stdout).map(pr => pr.headRefName))
}

const isAncestor = (ancestor, target, cwd) => (
  git(['merge-base', '--is-ancestor', ancestor, target], { cwd, allowFailure: true }).status === 0
)

const refExists = (ref, cwd) => (
  git(['show-ref', '--verify', '--quiet', ref], { cwd, allowFailure: true }).status === 0
)

export const auditBranches = (cwd = process.cwd()) => {
  const current = getCurrentBranch(cwd)
  const worktrees = getWorktreeBranches(cwd)
  const openPrHeads = getOpenPrHeads(cwd)
  const local = listRefs('refs/heads', cwd)
  const remote = listRefs('refs/remotes/origin', cwd)
    .filter(branch => !['origin', 'origin/HEAD', 'origin/main', 'origin/develop'].includes(branch.name))
    .map(branch => ({ ...branch, name: branch.name.replace(/^origin\//, '') }))

  const classify = (branch, location) => ({
    ...branch,
    location,
    ...classifyBranchForCleanup({
      name: branch.name,
      isCurrent: location === 'local' && branch.name === current,
      isWorktree: location === 'local' && worktrees.has(branch.name),
      isMerged: isAncestor(branch.sha, 'origin/develop', cwd),
      hasOpenPr: Boolean(openPrHeads?.has(branch.name)),
      openPrStateKnown: openPrHeads !== null
    })
  })

  return [...local.map(branch => classify(branch, 'local')), ...remote.map(branch => classify(branch, 'remote'))]
}

const printAudit = audit => {
  const labels = [
    ['safe', '可安全清理'],
    ['review', '需要负责人决定'],
    ['keep', '必须保留']
  ]
  labels.forEach(([category, label]) => {
    const rows = audit.filter(item => item.category === category)
    console.log(`${label}：${rows.length}`)
    rows.forEach(row => console.log(`- [${row.location}] ${row.name}：${row.reason}`))
  })
}

const cleanupMergedPrBranch = (prNumber, cwd) => {
  if (!/^\d+$/.test(String(prNumber || ''))) throw new Error('应用清理时必须提供精确 PR 编号')

  const pr = JSON.parse(gh([
    'pr', 'view', String(prNumber),
    '--json', 'state,mergedAt,baseRefName,headRefName,mergeCommit,commits'
  ], { cwd }).stdout)
  if (pr.state !== 'MERGED' || !pr.mergedAt || pr.baseRefName !== 'develop') {
    throw new Error('只允许清理已经合并到 develop 的 PR 分支')
  }
  if (!TASK_BRANCH_PATTERN.test(pr.headRefName) || PROTECTED_BRANCHES.has(pr.headRefName)) {
    throw new Error('PR head 不是允许自动清理的任务分支')
  }

  git(REMOTE_REFRESH_ARGS, { cwd })
  const current = getCurrentBranch(cwd)
  const worktrees = getWorktreeBranches(cwd)
  if (current === pr.headRefName || worktrees.has(pr.headRefName)) {
    throw new Error('目标分支仍为当前分支或被 worktree 使用')
  }

  const remoteRef = `refs/remotes/origin/${pr.headRefName}`
  const localRef = `refs/heads/${pr.headRefName}`
  const headSha = refExists(remoteRef, cwd)
    ? git(['rev-parse', remoteRef], { cwd }).stdout.trim()
    : refExists(localRef, cwd)
      ? git(['rev-parse', localRef], { cwd }).stdout.trim()
      : pr.commits?.at(-1)?.oid
  if (!headSha || !isAncestor(headSha, 'origin/develop', cwd)) {
    throw new Error('无法证明任务分支提交已经进入 origin/develop')
  }

  const openPrHeads = getOpenPrHeads(cwd)
  if (openPrHeads === null || openPrHeads.has(pr.headRefName)) {
    throw new Error('无法确认目标分支没有开放 PR')
  }

  if (refExists(remoteRef, cwd)) git(['push', 'origin', '--delete', pr.headRefName], { cwd })
  if (refExists(localRef, cwd)) git(['branch', '-d', pr.headRefName], { cwd })
  console.log(`已清理 PR #${prNumber} 的任务分支：${pr.headRefName}`)
}

const cleanupAllSafeBranches = cwd => {
  git(REMOTE_REFRESH_ARGS, { cwd })
  const audit = auditBranches(cwd)
  const grouped = new Map()
  audit.forEach(item => grouped.set(item.name, [...(grouped.get(item.name) || []), item]))
  const names = [...grouped.entries()]
    .filter(([, entries]) => entries.length > 0 && entries.every(item => item.category === 'safe'))
    .map(([name]) => name)
    .sort()
  const current = getCurrentBranch(cwd)
  const worktrees = getWorktreeBranches(cwd)
  const openPrHeads = getOpenPrHeads(cwd)
  if (openPrHeads === null) throw new Error('无法确认开放 PR，已停止批量清理')

  names.forEach(name => {
    if (PROTECTED_BRANCHES.has(name) || !TASK_BRANCH_PATTERN.test(name)) {
      throw new Error(`目标不是标准任务分支，已停止：${name}`)
    }
    if (current === name || worktrees.has(name) || openPrHeads.has(name)) {
      throw new Error(`目标仍在使用或出现开放 PR，已停止：${name}`)
    }
    const remoteRef = `refs/remotes/origin/${name}`
    const localRef = `refs/heads/${name}`
    const shas = [remoteRef, localRef]
      .filter(ref => refExists(ref, cwd))
      .map(ref => git(['rev-parse', ref], { cwd }).stdout.trim())
    if (!shas.length || shas.some(sha => !isAncestor(sha, 'origin/develop', cwd))) {
      throw new Error(`无法证明分支提交已经进入 origin/develop，已停止：${name}`)
    }
    if (refExists(remoteRef, cwd)) git(['push', 'origin', '--delete', name], { cwd })
    if (refExists(localRef, cwd)) git(['branch', '-d', name], { cwd })
    console.log(`已清理：${name}`)
  })

  console.log(`安全任务分支清理完成：${names.length} 个`)
}

const isDirectRun = process.argv[1]
  && resolve(process.argv[1]) === fileURLToPath(import.meta.url)

if (isDirectRun) {
  try {
    const apply = process.argv.includes('--apply')
    const applySafe = process.argv.includes('--apply-safe')
    const prIndex = process.argv.indexOf('--pr')
    const prNumber = prIndex >= 0 ? process.argv[prIndex + 1] : ''
    if (applySafe) cleanupAllSafeBranches(process.cwd())
    else if (apply) cleanupMergedPrBranch(prNumber, process.cwd())
    else printAudit(auditBranches(process.cwd()))
  } catch (error) {
    console.error(error.message)
    process.exit(1)
  }
}
