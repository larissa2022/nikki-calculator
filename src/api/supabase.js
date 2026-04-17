import { createClient } from '@supabase/supabase-js'

const supabaseUrl = 'https://fopyjewbsvusftpqbtml.supabase.co'
// ⚠️ 注意：这里必须填入 anon public 那个秘钥！
const supabaseKey = 'sb_publishable_XxYDVPY0_Ir4kfF-rQCGkA_dtRBH1Yh'

export const supabase = createClient(supabaseUrl, supabaseKey)