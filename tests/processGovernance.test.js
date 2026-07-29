import assert from 'node:assert/strict'
import { mkdirSync, rmSync, writeFileSync } from 'node:fs'
import test from 'node:test'

import {
  validateAcceptancePackFile,
  validateAcceptancePackText
} from '../scripts/process/validate-acceptance-pack.mjs'
import {
  classifyBranchForCleanup,
  REMOTE_REFRESH_ARGS,
  remoteDeleteIsComplete
} from '../scripts/process/task-cleanup.mjs'

const validPack = `# DB13 验收清单

验收批次：DB13-20260729
目标版本：develop abc123
测试入口：https://example.invalid

## 账号与密码

账号：tester@example.invalid
统一密码：local-test-password

## 已准备数据

短编号 9910001 已准备。

## 最短验收流程

### A：一次登录完成全部提交

1. 提交资料。
   - 预期结果：显示提交成功。

总通过标准：本轮全部步骤成功。

## 异常反馈

反馈步骤号和截图。

## 数据保留与清理

数据保留在 development，清理需要精确授权。
`

test('本地验收包必须包含账号密码、预置数据、最短流程和预期结果', () => {
  assert.deepEqual(validateAcceptancePackText(validPack), [])
  assert.ok(validateAcceptancePackText(validPack.replace('统一密码：local-test-password', '统一密码：待填写')).length > 0)
  assert.ok(validateAcceptancePackText(validPack.replace('一次登录', '分步登录')).length > 0)
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
