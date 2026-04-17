import { createClient } from '@supabase/supabase-js';
import fs from 'fs';

const supabaseUrl = 'https://fopyjewbsvusftpqbtml.supabase.co'; // 记得替换
const supabaseKey = 'sb_secret_H2aR4JgUBKs1SBs5O71FXg_B9caBkaH'; // 记得替换
const supabase = createClient(supabaseUrl, supabaseKey);

async function uploadStages() {
    // 读取本地的 stages.json
    const rawStages = JSON.parse(fs.readFileSync('./src/assets/stages.json', 'utf8'));
    
    // 把原来的 { "名字": {权重} } 格式转换为数据库需要的 [ {name: "名字", weights: {权重}} ] 格式
    const stageArray = Object.keys(rawStages).map(key => ({
        name: key,
        weights: rawStages[key]
    }));

    console.log(`准备上传 ${stageArray.length} 个竞技场主题...`);

    const { error } = await supabase.from('stages').upsert(stageArray, { onConflict: 'name' });

    if (error) {
        console.error('上传失败:', error.message);
    } else {
        console.log('🎉 竞技场权重已同步至云端！');
    }
}

uploadStages();