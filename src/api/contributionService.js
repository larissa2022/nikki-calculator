// src/api/contributionService.js
import { supabase } from './supabase'

export const contributionService = {
  // 1. 提交散件图鉴补充 (ImportZone 使用)
  async submitPendingClothes(payload) {
    const { error } = await supabase.from('pending_clothes').insert([payload]);
    if (error) throw new Error('提交审核失败：' + error.message);
    return true;
  },

  // 2. 批量提报缺失的套装 (SuitGallery 使用)
  async submitMissingSuits(namesArray, userId) {
    const inserts = namesArray.map(name => ({ name: name, submitted_by: userId, status: 'pending' }));
    const { error } = await supabase.from('pending_suits').insert(inserts);
    if (error) throw new Error('提报套装失败：' + error.message);
    return true;
  },

  // 3. 呼叫 AI 图像识别引擎 (通用)
  async recognizeImage(imageBase64, mode = 'clothes') {
    const { data, error } = await supabase.functions.invoke('recognize-clothing', {
      body: { imageBase64, mode } // mode 可以是 'clothes' (散件) 或 'suit' (套装)
    });
    if (error) throw new Error('AI 视觉提取失败：' + error.message);
    return data;
  }
};