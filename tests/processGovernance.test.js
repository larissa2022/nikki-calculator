import assert from 'node:assert/strict'
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import test from 'node:test'

import {
  validateAcceptancePackFile,
  validateAcceptancePackText
} from '../scripts/process/validate-acceptance-pack.mjs'
import {
  classifyBranchForCleanup,
  isTransientRemoteError,
  REMOTE_REFRESH_ARGS,
  REMOTE_RETRY_LIMIT,
  remoteDeleteIsComplete
} from '../scripts/process/task-cleanup.mjs'

const agentsText = readFileSync(new URL('../AGENTS.md', import.meta.url), 'utf8')
const rulesText = readFileSync(new URL('../docs/ai/RULES.md', import.meta.url), 'utf8')
const workflowsText = readFileSync(new URL('../docs/ai/WORKFLOWS.md', import.meta.url), 'utf8')
const acceptanceTemplateText = readFileSync(new URL('../docs/ai/templates/验收清单模板.md', import.meta.url), 'utf8')

const validPack = `# DB13 验收清单

验收批次：DB13-20260729
目标 PR：#123
目标提交：abcdef1234567890
测试入口：https://example.invalid

## 验收范围

验证普通用户提交流程。

## 已准备数据

短编号 9910001 已准备。

## 最短验收流程

### A：一次登录完成全部提交

账号：tester@example.invalid
密码：Nikki1234

1. 提交资料。
   - 预期结果：显示提交成功。

总通过标准：本轮全部步骤成功。

## 异常反馈

反馈步骤号和截图。

## 数据保留与清理

数据保留在 development，清理需要精确授权。

## Rollback

验收失败时继续在原 PR 修复。
`

test('本地验收包必须在每个测试模块内包含简单账号密码、预置数据、最短流程和预期结果', () => {
  assert.deepEqual(validateAcceptancePackText(validPack), [])
  assert.ok(validateAcceptancePackText(validPack.replace('密码：Nikki1234', '密码：待填写')).length > 0)
  assert.ok(validateAcceptancePackText(validPack.replace('密码：Nikki1234', '密码：Nikki-1234!')).length > 0)
  assert.ok(validateAcceptancePackText(validPack.replace('一次登录', '分步登录')).length > 0)
  assert.ok(validateAcceptancePackText(validPack.replace('目标 PR：#123', '目标 PR：待创建')).length > 0)
  assert.ok(validateAcceptancePackText(validPack.replace('目标提交：abcdef1234567890', '目标提交：develop')).length > 0)
})

test('验收包拒绝账号密码总表、统一密码和模块外凭据', () => {
  const globalTable = validPack.replace(
    '## 已准备数据',
    '## 账号与密码放置规则\n\n账号：outside@example.invalid\n统一密码：Nikki1234\n\n## 已准备数据'
  )
  assert.ok(validateAcceptancePackText(globalTable).length > 0)

  const passwordOutsideModule = validPack.replace(
    '## 最短验收流程',
    '密码：Nikki1234\n\n## 最短验收流程'
  )
  assert.ok(validateAcceptancePackText(passwordOutsideModule).length > 0)
})

test('验收包要求每个账号测试模块各自填写账号和简单密码', () => {
  const twoModules = validPack.replace(
    '总通过标准：本轮全部步骤成功。',
    '### B：一次登录检查只读页面\n\n账号：reader@example.invalid\n密码：Reader123\n\n1. 打开页面。\n   - 预期结果：页面只读。\n\n总通过标准：本轮全部步骤成功。'
  )
  assert.deepEqual(validateAcceptancePackText(twoModules), [])

  const missingSecondPassword = twoModules.replace('密码：Reader123\n\n1. 打开页面。', '1. 打开页面。')
  assert.ok(validateAcceptancePackText(missingSecondPassword).length > 0)
})

test('统一验收清单模板保留业务模块且不包含账号密码规则模块', () => {
  const headings = [...acceptanceTemplateText.matchAll(/^##\s+(.+)\s*$/gmu)].map(match => match[1].trim())
  assert.deepEqual(headings, [
    '验收范围',
    '已准备数据',
    '最短验收流程',
    '总通过标准',
    '异常反馈格式',
    '数据保留与清理',
    'Rollback'
  ])
  assert.doesNotMatch(acceptanceTemplateText, /^##\s+账号与密码/mu)
  assert.match(acceptanceTemplateText, /^### .+（一次登录）$/mu)
  assert.ok(acceptanceTemplateText.indexOf('账号：') > acceptanceTemplateText.indexOf('### '))
  assert.ok(acceptanceTemplateText.indexOf('密码：') > acceptanceTemplateText.indexOf('### '))
  assert.match(agentsText, /账号和简单密码直接写在该模块内，不设置账号密码总表/u)
  assert.match(workflowsText, /templates\/验收清单模板\.md/u)
})

test('验收包必须位于 Git 忽略路径且不能被跟踪', () => {
  const directory = 'tmp/process-governance-test'
  const filePath = `${directory}/验收清单.md`
  mkdirSync(directory, { recursive: true })
  writeFileSync(filePath, validPack, 'utf8')
  try {
    assert.deepEqual(validateAcceptancePackFile(filePath), [])
  } finally {
    rmSync(directory, { recursive: true, force: true })
  }
})

test('只有已进入 develop 且无开放 PR 的任务分支可自动清理', () => {
  assert.deepEqual(classifyBranchForCleanup({
    name: 'codex/finished-task',
    isMerged: true
  }), { category: 'safe', reason: '已合并任务分支' })

  assert.equal(classifyBranchForCleanup({ name: 'main', isMerged: true }).category, 'keep')
  assert.equal(classifyBranchForCleanup({ name: 'codex/current', isCurrent: true, isMerged: true }).category, 'keep')
  assert.equal(classifyBranchForCleanup({ name: 'codex/open', isMerged: true, hasOpenPr: true }).category, 'keep')
  assert.equal(classifyBranchForCleanup({ name: 'codex/unmerged' }).category, 'review')
  assert.equal(classifyBranchForCleanup({ name: 'user/manual', isMerged: true }).category, 'review')
  assert.equal(classifyBranchForCleanup({ name: 'codex/unknown', isMerged: true, openPrStateKnown: false }).category, 'review')
})

test('清理前刷新完整远端分支并移除过期引用', () => {
  assert.deepEqual(REMOTE_REFRESH_ARGS, ['fetch', 'origin', '--prune'])
  assert.equal(REMOTE_REFRESH_ARGS.includes('develop'), false)
})

test('远端分支并发消失时按幂等成功处理', () => {
  assert.equal(remoteDeleteIsComplete({ deleteStatus: 0, remoteExistsAfter: false }), true)
  assert.equal(remoteDeleteIsComplete({ deleteStatus: 1, remoteExistsAfter: false }), true)
  assert.equal(remoteDeleteIsComplete({ deleteStatus: 1, remoteExistsAfter: true }), false)
})

test('仅对明确的临时网络错误进行有限重试', () => {
  assert.equal(REMOTE_RETRY_LIMIT, 2)
  assert.equal(isTransientRemoteError('TLS connect error: unexpected eof while reading'), true)
  assert.equal(isTransientRemoteError('Could not resolve host: github.com'), true)
  assert.equal(isTransientRemoteError('permission denied'), false)
  assert.equal(isTransientRemoteError('branch is not fully merged'), false)
})

test('用户可见功能必须绑定最新版本验收后再合并', () => {
  assert.match(agentsText, /用户可见功能还必须已经通过对应版本的业务验收，才可合并/)
  assert.match(rulesText, /目标 PR 最新 head commit 对应的 Preview \/ development 版本完成业务验收后，才可合并到 `develop`/)
  assert.match(workflowsText, /验收反馈直接提交到原分支并更新原 PR/)
  assert.doesNotMatch(agentsText, /PR 检查通过后，普通 `develop` PR 可直接合并/)
  assert.doesNotMatch(workflowsText, /普通 `develop` PR 检查通过后直接合并/)
})
