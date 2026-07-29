export const CORRECTION_EVIDENCE_BUCKET = 'correction-evidence'
export const CORRECTION_EVIDENCE_MAX_BYTES = 8 * 1024 * 1024

const ALLOWED_TYPES = new Map([
  ['image/jpeg', 'jpg'],
  ['image/png', 'png'],
  ['image/webp', 'webp']
])

export const validateCorrectionEvidenceFile = file => {
  if (!file) return '请上传游戏内图鉴图片。'
  if (!ALLOWED_TYPES.has(String(file.type || '').toLowerCase())) {
    return '图片仅支持 JPG、PNG 或 WebP 格式。'
  }
  if (!Number.isFinite(Number(file.size)) || Number(file.size) <= 0) {
    return '图片文件为空，请重新选择。'
  }
  if (Number(file.size) > CORRECTION_EVIDENCE_MAX_BYTES) {
    return '图片不能超过 8 MB。'
  }
  return ''
}

export const createCorrectionEvidencePath = (
  userId,
  file,
  randomUUID = () => globalThis.crypto.randomUUID()
) => {
  const normalizedUserId = String(userId || '').trim().toLowerCase()
  const extension = ALLOWED_TYPES.get(String(file?.type || '').toLowerCase())
  if (!normalizedUserId || !extension) throw new Error('无法生成图片保存地址')
  return `${normalizedUserId}/${randomUUID()}.${extension}`
}

export const uploadCorrectionEvidence = async (client, path, file) => {
  const validationError = validateCorrectionEvidenceFile(file)
  if (validationError) throw new Error(validationError)
  const { error } = await client.storage
    .from(CORRECTION_EVIDENCE_BUCKET)
    .upload(path, file, {
      cacheControl: '3600',
      contentType: file.type,
      upsert: false
    })
  if (error) throw error
  return path
}

export const removeCorrectionEvidence = async (client, path) => {
  if (!path) return
  const { error } = await client.storage
    .from(CORRECTION_EVIDENCE_BUCKET)
    .remove([path])
  if (error) throw error
}

export const createCorrectionEvidenceSignedUrl = async (
  client,
  path,
  expiresIn = 3600
) => {
  if (!path) return ''
  const { data, error } = await client.storage
    .from(CORRECTION_EVIDENCE_BUCKET)
    .createSignedUrl(path, expiresIn)
  if (error) throw error
  return String(data?.signedUrl || '')
}
