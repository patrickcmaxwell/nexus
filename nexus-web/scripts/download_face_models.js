/**
 * Downloads the required face-api.js model files from the official CDN
 * into public/models/ so they are served statically by Next.js.
 *
 * Run once: node scripts/download_face_models.js
 *
 * Models needed:
 *   - tiny_face_detector (fast face detection)
 *   - face_landmark_68_tiny (landmark points)
 *   - face_recognition (128-float descriptor)
 */

import { createWriteStream, mkdirSync, existsSync } from "fs"
import { pipeline } from "stream/promises"

import { join } from "path"
import { fileURLToPath } from "url"

const __dirname = fileURLToPath(new URL(".", import.meta.url))
const MODELS_DIR = join(__dirname, "../public/models")
const BASE_URL = "https://raw.githubusercontent.com/vladmandic/face-api/master/model"

const FILES = [
  "tiny_face_detector_model-weights_manifest.json",
  "tiny_face_detector_model.bin",
  "face_landmark_68_tiny_model-weights_manifest.json",
  "face_landmark_68_tiny_model.bin",
  "face_recognition_model-weights_manifest.json",
  "face_recognition_model.bin",
]

if (!existsSync(MODELS_DIR)) {
  mkdirSync(MODELS_DIR, { recursive: true })
  console.log(`Created directory: ${MODELS_DIR}`)
}

for (const file of FILES) {
  const dest = `${MODELS_DIR}/${file}`
  if (existsSync(dest)) {
    console.log(`[skip] ${file} already exists`)
    continue
  }

  console.log(`[download] ${file}...`)
  const res = await fetch(`${BASE_URL}/${file}`)
  if (!res.ok) throw new Error(`Failed to download ${file}: ${res.status}`)
  await pipeline(res.body, createWriteStream(dest))

  console.log(`[done] ${file}`)
}

console.log("\nAll models downloaded to public/models/")
console.log("Face recognition is ready.")
