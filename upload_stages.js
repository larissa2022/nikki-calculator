import fs from 'fs';
import { createMaintenanceClient } from './scripts/lib/maintenance-client.mjs';

const supabase = createMaintenanceClient();

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
