import { ref } from 'vue'
import { supabase } from '../api/supabase'

export function useAi() {
  const isRecognizing = ref(false)

  const recognizeImage = async (file) => {
    if (!file) return null
    isRecognizing.value = true
    
    return new Promise((resolve, reject) => {
      const reader = new FileReader()
      reader.readAsDataURL(file)
      reader.onload = async () => {
        try {
          const base64 = reader.result.split(',')[1]
          const { data, error } = await supabase.functions.invoke('recognize-clothing', {
            body: { imageBase64: base64 }
          })
          if (error) throw error
          resolve(data.names)
        } catch (err) {
          reject(err)
        } finally {
          isRecognizing.value = false
        }
      }
    })
  }

  return { isRecognizing, recognizeImage }
}