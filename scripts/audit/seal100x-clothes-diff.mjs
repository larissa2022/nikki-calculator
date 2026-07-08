#!/usr/bin/env node
/**
 * Dry-run audit for seal100x live wardrobe data against Supabase public.clothes.
 *
 * Usage:
 *   SUPABASE_DEV_URL=https://tfwejruvdahonacyldrg.supabase.co \
 *   SUPABASE_DEV_ANON_KEY=<anon key> \
 *   node scripts/audit/seal100x-clothes-diff.mjs --target development --limit-samples 20
 *
 * Production SELECT-only audit requires both flags:
 *   SUPABASE_PROD_URL=https://fopyjewbsvusftpqbtml.supabase.co \
 *   SUPABASE_PROD_ANON_KEY=<anon key> \
 *   node scripts/audit/seal100x-clothes-diff.mjs --target production --confirm-production-readonly
 *
 * Optional:
 *   --json tmp/seal100x-clothes-diff.json
 *   --strict-count
 *
 * This script is read-only: it fetches upstream JavaScript, expands the live
 * wardrobe array, and reads Supabase with SELECT requests only.
 */

import { createHash } from 'node:crypto'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import vm from 'node:vm'
import { createClient } from '@supabase/supabase-js'

const UPSTREAM_URL = 'https://seal100x.github.io/nikkiup2u3_data/wardrobe.js'
const EXPECTED_EXPANDED_COUNT = 36811
const DEV_PROJECT_REF = 'tfwejruvdahonacyldrg'
const PROD_PROJECT_REF = 'fopyjewbsvusftpqbtml'
const PAGE_SIZE = 1000
const TARGETS = new Set(['development', 'production'])

const TARGET_COLUMNS = [
  'id',
  'name',
  'category',
  'game_id',
  'stars',
  'tags',
  'scores',
  'suit_id',
  'temp_suit_name',
  'created_at',
  'updated_at',
]

const READ_ONLY_COLUMNS = new Set([
  'id',
  'category',
  'game_id',
  'suit_id',
  'temp_suit_name',
  'created_at',
  'updated_at',
])

const SOURCE_CONTEXT_FIELDS = [
  'source',
  'suit',
  'version',
  'setSource',
  'isNew',
]

const SCORE_KEYS = [
  'gorgeous',
  'simple',
  'elegant',
  'active',
  'mature',
  'cute',
  'sexy',
  'pure',
  'cool',
  'warm',
]

const SCORE_MATRIX = {
  '发型': { '完美++': 1674, '完美+': 1324.5, '完美': 1089, '优秀': 837, '不错': 682.5, '一般': 517.5, '失败': 0 },
  '连衣裙': { '完美++': 6732, '完美+': 5269.5, '完美': 4305, '优秀': 3366, '不错': 2749.5, '一般': 2100, '失败': 0 },
  '外套': { '完美++': 663, '完美+': 525, '完美': 423, '优秀': 331.5, '不错': 270, '一般': 213, '失败': 0 },
  '上装': { '完美++': 3357, '完美+': 2619, '完美': 2140.5, '优秀': 1678.5, '不错': 1369.5, '一般': 1041, '失败': 0 },
  '下装': { '完美++': 3357, '完美+': 2632.5, '完美': 2137.5, '优秀': 1678.5, '不错': 1357.5, '一般': 1041, '失败': 0 },
  '袜子': { '完美++': 1005, '完美+': 789, '完美': 648, '优秀': 502.5, '不错': 403.5, '一般': 305, '失败': 0 },
  '鞋子': { '完美++': 1335, '完美+': 1050, '完美': 855, '优秀': 667.5, '不错': 541.5, '一般': 423, '失败': 0 },
  '饰品': { '完美++': 660, '完美+': 526.5, '完美': 424.5, '优秀': 330, '不错': 271.5, '一般': 213, '失败': 0 },
  '妆容': { '完美++': 336, '完美+': 267, '完美': 213, '优秀': 168, '不错': 125, '一般': 85, '失败': 0 },
  '萤光之灵': { '完美++': 651, '完美+': 517.5, '完美': 421.5, '优秀': 325.5, '不错': 264, '一般': 200, '失败': 0 },
}

const GRADE_TO_LABEL = {
  C: '一般',
  B: '不错',
  A: '优秀',
  S: '完美',
  SS: '完美+',
  SSS: '完美++',
}

const parseArgs = (argv) => {
  const args = {
    target: 'development',
    confirmProductionReadonly: false,
    jsonPath: null,
    limitSamples: 20,
    strictCount: false,
  }

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--json') {
      args.jsonPath = argv[i + 1]
      i += 1
    } else if (arg === '--target') {
      args.target = argv[i + 1]
      i += 1
    } else if (arg === '--confirm-production-readonly') {
      args.confirmProductionReadonly = true
    } else if (arg === '--limit-samples') {
      args.limitSamples = Number(argv[i + 1] || 20)
      i += 1
    } else if (arg === '--strict-count') {
      args.strictCount = true
    } else if (arg === '--help' || arg === '-h') {
      printUsage()
      process.exit(0)
    } else {
      throw new Error(`Unknown argument: ${arg}`)
    }
  }

  if (!TARGETS.has(args.target)) {
    throw new Error('--target must be development or production')
  }

  if (!Number.isInteger(args.limitSamples) || args.limitSamples < 0) {
    throw new Error('--limit-samples must be a non-negative integer')
  }

  return args
}

const printUsage = () => {
  console.log(`Usage:
  node scripts/audit/seal100x-clothes-diff.mjs [--target development] [--limit-samples 20] [--json tmp/seal100x-clothes-diff.json] [--strict-count]
  node scripts/audit/seal100x-clothes-diff.mjs --target production --confirm-production-readonly [--limit-samples 20]

Required environment:
  SUPABASE_DEV_URL=https://${DEV_PROJECT_REF}.supabase.co
  SUPABASE_DEV_ANON_KEY=<development anon key>

Production environment:
  SUPABASE_PROD_URL=https://${PROD_PROJECT_REF}.supabase.co
  SUPABASE_PROD_ANON_KEY=<production anon key>

Fallback environment accepted only when the URL contains the development ref:
  VITE_SUPABASE_URL
  VITE_SUPABASE_ANON_KEY`)
}

const loadEnvFileIfNeeded = () => {
  const envFiles = ['.env.local', '.env']
  for (const envFile of envFiles) {
    if (!existsSync(envFile)) continue
    const lines = readFileSync(envFile, 'utf8').split(/\r?\n/)
    for (const line of lines) {
      const trimmed = line.trim()
      if (!trimmed || trimmed.startsWith('#')) continue
      const eq = trimmed.indexOf('=')
      if (eq <= 0) continue
      const key = trimmed.slice(0, eq).trim()
      let value = trimmed.slice(eq + 1).trim()
      if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
        value = value.slice(1, -1)
      }
      if (!process.env[key]) process.env[key] = value
    }
  }
}

const getSupabaseEnv = (args) => {
  loadEnvFileIfNeeded()

  if (args.target === 'production') {
    if (!args.confirmProductionReadonly) {
      throw new Error('Production audit requires --confirm-production-readonly')
    }

    const url = process.env.SUPABASE_PROD_URL || ''
    const anonKey = process.env.SUPABASE_PROD_ANON_KEY || ''

    if (!url || !anonKey) {
      throw new Error('Missing production Supabase env: SUPABASE_PROD_URL and SUPABASE_PROD_ANON_KEY')
    }

    if (!url.includes(PROD_PROJECT_REF)) {
      throw new Error(`Production Supabase URL must contain project ref ${PROD_PROJECT_REF}`)
    }

    assertAnonKeyOnly(anonKey)

    return {
      url,
      anonKey,
      target: 'production',
      projectRef: PROD_PROJECT_REF,
      productionReadOnlyConfirmed: true,
    }
  }

  const url = process.env.SUPABASE_DEV_URL || process.env.VITE_SUPABASE_URL || ''
  const anonKey = process.env.SUPABASE_DEV_ANON_KEY || process.env.VITE_SUPABASE_ANON_KEY || ''

  if (!url || !anonKey) {
    throw new Error('Missing development Supabase env: SUPABASE_DEV_URL and SUPABASE_DEV_ANON_KEY')
  }

  if (url.includes(PROD_PROJECT_REF)) {
    throw new Error(`Refusing to run development audit against production project ref ${PROD_PROJECT_REF}`)
  }

  if (!url.includes(DEV_PROJECT_REF)) {
    throw new Error(`Development Supabase URL must contain project ref ${DEV_PROJECT_REF}`)
  }

  assertAnonKeyOnly(anonKey)

  return {
    url,
    anonKey,
    target: 'development',
    projectRef: DEV_PROJECT_REF,
    productionReadOnlyConfirmed: false,
  }
}

const assertAnonKeyOnly = (key) => {
  if (String(key).includes('service_role')) {
    throw new Error('Refusing to run with a service role key')
  }

  const parts = String(key).split('.')
  if (parts.length < 2) return

  try {
    const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'))
    if (payload?.role === 'service_role') {
      throw new Error('Refusing to run with a service role key')
    }
  } catch (error) {
    if (error.message.includes('service role')) throw error
  }
}

const assertSafeJsonPath = (jsonPath) => {
  if (!jsonPath) return null
  const normalized = jsonPath.replaceAll('\\', '/')
  if (!normalized.startsWith('tmp/') && !normalized.startsWith('.cache/')) {
    throw new Error('--json path must be under tmp/ or .cache/')
  }
  return resolve(jsonPath)
}

const fetchText = async (url) => {
  const response = await fetch(url)
  if (!response.ok) {
    throw new Error(`Failed to fetch ${url}: HTTP ${response.status}`)
  }
  return response.text()
}

const parseUpstream = async () => {
  const fetchTime = new Date().toISOString()
  const raw = await fetchText(UPSTREAM_URL)
  const hash = createHash('sha256').update(raw).digest('hex')
  const context = {}

  vm.createContext(context)
  vm.runInContext(
    `${raw}
this.__seal100x = { category, code2tag, code2suit, codewardrobe, wardrobe, wardrobe_lastupd };`,
    context,
    { timeout: 30000 }
  )

  const parsed = context.__seal100x
  if (!parsed || !Array.isArray(parsed.wardrobe) || !Array.isArray(parsed.codewardrobe)) {
    throw new Error('Unable to parse seal100x wardrobe globals')
  }

  const rows = parsed.wardrobe.map(normalizeUpstreamRow)
  return {
    url: UPSTREAM_URL,
    fetchTime,
    sha256: hash,
    wardrobeLastUpdated: parsed.wardrobe_lastupd || null,
    rawCount: parsed.codewardrobe.length,
    expandedCount: parsed.wardrobe.length,
    categories: parsed.category || [],
    rows,
  }
}

const normalizeUpstreamRow = (row) => {
  const grades = {}
  for (let i = 0; i < SCORE_KEYS.length; i += 1) {
    grades[SCORE_KEYS[i]] = normalizeText(row[4 + i])
  }

  return {
    name: normalizeText(row[0]),
    category: normalizeText(row[1]),
    game_id: normalizeText(row[2]),
    stars: normalizeText(row[3]),
    scores: gradesToScores(normalizeText(row[1]), grades),
    grades,
    tags: normalizeTags(row[14]),
    source: normalizeText(row[15]),
    suit: normalizeText(row[16]),
    version: normalizeText(row[17]),
    setSource: normalizeText(row[18]),
    isNew: normalizeText(row[19]),
  }
}

const gradesToScores = (category, grades) => {
  const broadCategory = getBroadCategory(category)
  const matrix = SCORE_MATRIX[broadCategory] || SCORE_MATRIX['饰品']
  const scores = {}

  for (const key of SCORE_KEYS) {
    const grade = grades[key]
    const label = GRADE_TO_LABEL[grade]
    scores[key] = label ? matrix[label] || 0 : 0
  }

  return scores
}

const normalizeText = (value) => String(value ?? '').trim()

const normalizeTags = (value) => {
  const values = Array.isArray(value) ? value : [value]
  return [...new Set(
    values
      .flatMap((item) => String(item ?? '').split(/[,，、;；/]+/))
      .map((tag) => tag.trim())
      .filter(Boolean)
  )].join(', ')
}

const getBroadCategory = (category) => {
  const value = normalizeText(category).replace(/[·*]/g, '-')
  if (!value) return '饰品'
  if (value.includes('袜子')) return '袜子'
  if (value.includes('饰品')) return '饰品'
  if (value.includes('上装')) return '上装'
  if (value.includes('下装')) return '下装'
  return value
}

const stripLeadingZeros = (gameId) => {
  const value = normalizeText(gameId)
  return value.replace(/^0+(?=\d)/, '') || value
}

const createExactKey = (row) => [
  normalizeText(row.category),
  normalizeText(row.game_id),
  normalizeText(row.name),
].join('\u0001')

const createNormalizedKey = (row) => [
  getBroadCategory(row.category),
  stripLeadingZeros(row.game_id),
  normalizeText(row.name),
].join('\u0001')

const displayKey = (key) => key.split('\u0001').join(' | ')

const createClientReadOnly = ({ url, anonKey }) => createClient(url, anonKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  },
})

const probeExistingColumns = async (supabase) => {
  const warnings = []
  const existingColumns = []

  for (const column of TARGET_COLUMNS) {
    const { error } = await supabase
      .from('clothes')
      .select(column)
      .limit(1)

    if (error) {
      if (column === 'updated_at') {
        warnings.push('clothes.updated_at does not exist; continuing without it')
        continue
      }
      throw new Error(`Required clothes column probe failed for ${column}: ${error.message}`)
    }

    existingColumns.push(column)
  }

  return { existingColumns, warnings }
}

const fetchClothesRows = async (supabase, columns) => {
  const rows = []
  let from = 0
  const selectColumns = columns.join(',')

  while (true) {
    const to = from + PAGE_SIZE - 1
    const { data, error } = await supabase
      .from('clothes')
      .select(selectColumns)
      .range(from, to)

    if (error) {
      throw new Error(`Failed to read public.clothes at range ${from}-${to}: ${error.message}`)
    }

    const page = data || []
    rows.push(...page)
    if (page.length < PAGE_SIZE) break
    from += PAGE_SIZE
  }

  return rows.map(normalizeDbRow)
}

const normalizeDbRow = (row) => ({
  id: normalizeText(row.id),
  name: normalizeText(row.name),
  category: normalizeText(row.category),
  game_id: normalizeText(row.game_id),
  stars: normalizeText(row.stars),
  tags: normalizeTags(row.tags),
  scores: normalizeScores(row.scores),
  suit_id: normalizeText(row.suit_id),
  temp_suit_name: normalizeText(row.temp_suit_name),
  created_at: normalizeText(row.created_at),
  updated_at: normalizeText(row.updated_at),
})

const normalizeScores = (scores) => {
  const source = scores && typeof scores === 'object' && !Array.isArray(scores) ? scores : {}
  const normalized = {}
  for (const key of SCORE_KEYS) {
    const value = Number(source[key] ?? 0)
    normalized[key] = Number.isFinite(value) ? value : 0
  }
  return normalized
}

const stableStringify = (value) => {
  if (value === null || typeof value !== 'object') return JSON.stringify(value)
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(',')}]`
  return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`).join(',')}}`
}

const valuesEqual = (left, right) => {
  if (left && typeof left === 'object') return stableStringify(left) === stableStringify(right)
  return normalizeText(left) === normalizeText(right)
}

const countBy = (rows, keyFn) => {
  const counts = {}
  for (const row of rows) {
    const key = keyFn(row)
    counts[key] = (counts[key] || 0) + 1
  }
  return counts
}

const groupBy = (rows, keyFn) => {
  const groups = new Map()
  for (const row of rows) {
    const key = keyFn(row)
    if (!groups.has(key)) groups.set(key, [])
    groups.get(key).push(row)
  }
  return groups
}

const findDuplicateKeys = (rows, keyFn) => [...groupBy(rows, keyFn).entries()]
  .filter(([, values]) => values.length > 1)
  .map(([key, values]) => ({
    key: displayKey(key),
    count: values.length,
    rows: values.map(sampleRow),
  }))

const sampleRow = (row) => ({
  id: row.id || undefined,
  name: row.name,
  category: row.category,
  game_id: row.game_id,
  stars: row.stars,
  tags: row.tags,
  source: row.source || undefined,
  suit: row.suit || undefined,
  version: row.version || undefined,
  setSource: row.setSource || undefined,
  isNew: row.isNew || undefined,
})

const analyzeDiff = ({ sourceRows, dbRows, keyFn, limitSamples }) => {
  const sourceGroups = groupBy(sourceRows, keyFn)
  const dbGroups = groupBy(dbRows, keyFn)
  const sourceDuplicateKeys = findDuplicateKeys(sourceRows, keyFn)
  const dbDuplicateKeys = findDuplicateKeys(dbRows, keyFn)
  const conflictKeySet = new Set([
    ...sourceDuplicateKeys.map((item) => item.key),
    ...dbDuplicateKeys.map((item) => item.key),
  ])

  const sourceOnly = []
  const dbOnly = []
  const changed = []

  for (const [key, sourceGroup] of sourceGroups.entries()) {
    const printableKey = displayKey(key)
    if (conflictKeySet.has(printableKey)) continue
    const dbGroup = dbGroups.get(key)
    if (!dbGroup) {
      sourceOnly.push({ key: printableKey, source: sampleRow(sourceGroup[0]) })
      continue
    }

    const diffs = compareWhitelistFields(sourceGroup[0], dbGroup[0])
    if (diffs.length > 0) {
      changed.push({
        key: printableKey,
        source: sampleRow(sourceGroup[0]),
        db: sampleRow(dbGroup[0]),
        fields: diffs,
      })
    }
  }

  for (const [key, dbGroup] of dbGroups.entries()) {
    const printableKey = displayKey(key)
    if (conflictKeySet.has(printableKey)) continue
    if (!sourceGroups.has(key)) {
      dbOnly.push({ key: printableKey, db: sampleRow(dbGroup[0]) })
    }
  }

  return {
    counts: {
      sourceOnly: sourceOnly.length,
      changed: changed.length,
      dbOnly: dbOnly.length,
      sourceDuplicateKeys: sourceDuplicateKeys.length,
      dbDuplicateKeys: dbDuplicateKeys.length,
      totalConflictKeys: sourceDuplicateKeys.length + dbDuplicateKeys.length,
    },
    samples: {
      sourceOnly: sourceOnly.slice(0, limitSamples),
      changed: changed.slice(0, limitSamples),
      dbOnly: dbOnly.slice(0, limitSamples),
    },
    conflicts: {
      sourceDuplicateKeys,
      dbDuplicateKeys,
    },
  }
}

const compareWhitelistFields = (source, db) => {
  const fields = []
  for (const field of ['name', 'stars', 'scores', 'tags']) {
    const sourceValue = source[field]
    const dbValue = db[field]
    if (!valuesEqual(sourceValue, dbValue)) {
      fields.push({ field, source: sourceValue, db: dbValue })
    }
  }
  return fields
}

const buildDbStats = (dbRows, columns) => {
  const exactDuplicates = findDuplicateKeys(dbRows, createExactKey)
  const normalizedDuplicates = findDuplicateKeys(dbRows, createNormalizedKey)

  return {
    rowCount: dbRows.length,
    categoryCounts: countBy(dbRows, (row) => row.category || '(blank)'),
    blankGameIdCount: dbRows.filter((row) => !row.game_id).length,
    exactDuplicateKeyCount: exactDuplicates.length,
    normalizedDuplicateKeyCount: normalizedDuplicates.length,
    exactDuplicateKeys: exactDuplicates,
    normalizedDuplicateKeys: normalizedDuplicates,
    actualColumns: columns,
  }
}

const buildReport = ({ upstream, dbRows, columns, warnings, env, limitSamples }) => {
  const exact = analyzeDiff({
    sourceRows: upstream.rows,
    dbRows,
    keyFn: createExactKey,
    limitSamples,
  })
  const normalized = analyzeDiff({
    sourceRows: upstream.rows,
    dbRows,
    keyFn: createNormalizedKey,
    limitSamples,
  })

  if (upstream.expandedCount !== EXPECTED_EXPANDED_COUNT) {
    warnings.push(`Upstream expanded count is ${upstream.expandedCount}, expected ${EXPECTED_EXPANDED_COUNT}`)
  }

  return {
    generatedAt: new Date().toISOString(),
    mode: 'dry-run read-only',
    environment: {
      target: env.target,
      projectRef: env.projectRef,
      productionReadOnlyConfirmed: env.productionReadOnlyConfirmed,
      productionRefBlocked: PROD_PROJECT_REF,
    },
    upstream: {
      url: upstream.url,
      fetchTime: upstream.fetchTime,
      sha256: upstream.sha256,
      wardrobeLastUpdated: upstream.wardrobeLastUpdated,
      rawCount: upstream.rawCount,
      expandedCount: upstream.expandedCount,
      expectedExpandedCount: EXPECTED_EXPANDED_COUNT,
      categoryCount: upstream.categories.length,
      categories: upstream.categories,
    },
    db: buildDbStats(dbRows, columns),
    warnings,
    policy: {
      sourceOfTruth: 'seal100x upstream is the clothing item sync source, not the database schema source.',
      dbSchemaSource: 'Nikki Calculator current public.clothes schema and confirmed product requirements.',
      comparedFieldsOnly: ['name', 'stars', 'scores', 'tags'],
      readOnlyFields: [...READ_ONLY_COLUMNS],
      sourceContextOnlyFields: SOURCE_CONTEXT_FIELDS,
    },
    exactKey: exact,
    normalizedKey: normalized,
  }
}

const printSummary = (report, limitSamples) => {
  console.log('seal100x clothes diff dry-run audit')
  console.log('====================================')
  console.log(`Mode: ${report.mode}`)
  console.log(`Target: ${report.environment.target}`)
  console.log(`Project ref: ${report.environment.projectRef}`)
  console.log(`Production readonly confirmed: ${report.environment.productionReadOnlyConfirmed}`)
  console.log(`Upstream URL: ${report.upstream.url}`)
  console.log(`Upstream wardrobe_lastupd: ${report.upstream.wardrobeLastUpdated || '(unknown)'}`)
  console.log(`Upstream raw count: ${report.upstream.rawCount}`)
  console.log(`Upstream expanded count: ${report.upstream.expandedCount}`)
  console.log(`Upstream sha256: ${report.upstream.sha256}`)
  console.log(`${report.environment.target} clothes rows: ${report.db.rowCount}`)
  console.log(`clothes columns: ${report.db.actualColumns.join(', ')}`)
  console.log(`blank game_id rows: ${report.db.blankGameIdCount}`)
  console.log('')

  if (report.warnings.length > 0) {
    console.log('Warnings:')
    for (const warning of report.warnings) console.log(`- ${warning}`)
    console.log('')
  }

  console.log('DB category counts:')
  for (const [category, count] of Object.entries(report.db.categoryCounts).sort((a, b) => a[0].localeCompare(b[0], 'zh-Hans-CN'))) {
    console.log(`- ${category}: ${count}`)
  }
  console.log('')

  printDiffSummary('Exact key: category + game_id + name', report.exactKey)
  printDiffSummary('Normalized key: getBroadCategory(category) + stripLeadingZeros(game_id) + name', report.normalizedKey)

  printSamples(`Exact source-only samples (limit ${limitSamples})`, report.exactKey.samples.sourceOnly)
  printSamples(`Exact changed samples (limit ${limitSamples})`, report.exactKey.samples.changed)
  printSamples(`Exact DB-only samples (limit ${limitSamples})`, report.exactKey.samples.dbOnly)
  printConflictSummary('Exact key conflicts', report.exactKey.conflicts)

  printSamples(`Normalized source-only samples (limit ${limitSamples})`, report.normalizedKey.samples.sourceOnly)
  printSamples(`Normalized changed samples (limit ${limitSamples})`, report.normalizedKey.samples.changed)
  printSamples(`Normalized DB-only samples (limit ${limitSamples})`, report.normalizedKey.samples.dbOnly)
  printConflictSummary('Normalized key conflicts', report.normalizedKey.conflicts)

  console.log('Schema note:')
  console.log('- Upstream source/version/setSource/isNew are source context only, not DB field requirements.')
  console.log('- Upstream suit is source context only; DB suit boundary remains suit_id / temp_suit_name.')
}

const printDiffSummary = (title, diff) => {
  console.log(title)
  console.log(`- source has, DB missing: ${diff.counts.sourceOnly}`)
  console.log(`- source has, DB has, compared fields differ: ${diff.counts.changed}`)
  console.log(`- DB has, source missing: ${diff.counts.dbOnly}`)
  console.log(`- source duplicate keys: ${diff.counts.sourceDuplicateKeys}`)
  console.log(`- DB duplicate keys: ${diff.counts.dbDuplicateKeys}`)
  console.log(`- total conflict keys: ${diff.counts.totalConflictKeys}`)
  console.log('')
}

const printSamples = (title, samples) => {
  console.log(title)
  if (samples.length === 0) {
    console.log('- none')
    console.log('')
    return
  }

  for (const [index, item] of samples.entries()) {
    console.log(`${index + 1}. ${item.key}`)
    if (item.source) console.log(`   source: ${formatSample(item.source)}`)
    if (item.db) console.log(`   db: ${formatSample(item.db)}`)
    if (item.fields) {
      console.log(`   differing fields: ${item.fields.map((field) => field.field).join(', ')}`)
    }
  }
  console.log('')
}

const printConflictSummary = (title, conflicts) => {
  console.log(title)
  if (conflicts.sourceDuplicateKeys.length === 0 && conflicts.dbDuplicateKeys.length === 0) {
    console.log('- none')
    console.log('')
    return
  }

  for (const item of conflicts.sourceDuplicateKeys) {
    console.log(`- source duplicate ${item.key}: ${item.count}`)
  }
  for (const item of conflicts.dbDuplicateKeys) {
    console.log(`- DB duplicate ${item.key}: ${item.count}`)
  }
  console.log('')
}

const formatSample = (item) => [
  item.id ? `id=${item.id}` : null,
  `name=${item.name}`,
  `category=${item.category}`,
  `game_id=${item.game_id}`,
  `stars=${item.stars}`,
  item.tags ? `tags=${item.tags}` : null,
  item.source ? `source=${item.source}` : null,
  item.version ? `version=${item.version}` : null,
].filter(Boolean).join('; ')

const writeJsonReport = (jsonPath, report) => {
  const absolutePath = assertSafeJsonPath(jsonPath)
  if (!absolutePath) return null
  mkdirSync(dirname(absolutePath), { recursive: true })
  writeFileSync(absolutePath, `${JSON.stringify(report, null, 2)}\n`, 'utf8')
  return absolutePath
}

const main = async () => {
  const args = parseArgs(process.argv.slice(2))
  const env = getSupabaseEnv(args)
  const supabase = createClientReadOnly(env)
  const warnings = []

  const upstream = await parseUpstream()
  if (args.strictCount && upstream.expandedCount !== EXPECTED_EXPANDED_COUNT) {
    throw new Error(`Upstream expanded count ${upstream.expandedCount} does not match expected ${EXPECTED_EXPANDED_COUNT}`)
  }

  const { existingColumns, warnings: columnWarnings } = await probeExistingColumns(supabase)
  warnings.push(...columnWarnings)
  const dbRows = await fetchClothesRows(supabase, existingColumns)
  const report = buildReport({
    upstream,
    dbRows,
    columns: existingColumns,
    warnings,
    env,
    limitSamples: args.limitSamples,
  })

  printSummary(report, args.limitSamples)

  const jsonReportPath = writeJsonReport(args.jsonPath, report)
  if (jsonReportPath) {
    console.log(`JSON report written to: ${jsonReportPath}`)
  }
}

main().catch((error) => {
  console.error(`seal100x clothes diff dry-run failed: ${error.message}`)
  process.exit(1)
})
