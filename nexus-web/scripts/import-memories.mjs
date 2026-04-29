import fs from "fs"
import path from "path"
import { createClient } from "@supabase/supabase-js"
// Manually parse .env.local to avoid dependency issues
const envFile = fs.readFileSync(".env.local", "utf8")
const getEnv = (key) => envFile.match(new RegExp(`^${key}=(.*)`, "m"))?.[1]

const SUPABASE_URL = getEnv("NEXT_PUBLIC_SUPABASE_URL")
const SUPABASE_KEY = getEnv("SUPABASE_SERVICE_ROLE_KEY") || getEnv("SUPABASE_SECRET_KEY")
const USER_ID = "e9d9a15b-0e5a-4631-9b50-6225ee03a44f"
const MEMORY_DIR = "../memory/eve-private/eve/history"

if (!SUPABASE_URL || !SUPABASE_KEY || SUPABASE_URL.includes("your_supabase_url")) {
  console.error("❌ SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY missing in .env.local")
  process.exit(1)
}

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY)

async function importFile(filePath) {
  const content = fs.readFileSync(filePath, "utf8")
  
  // 1. Parse Frontmatter
  const frontmatterMatch = content.match(/^---\n([\s\S]*?)\n---/)
  if (!frontmatterMatch) return
  
  const yaml = frontmatterMatch[1]
  const title = yaml.match(/title: "(.*?)"/)?.[1] || yaml.match(/title: (.*)/)?.[1]
  const dateStr = yaml.match(/date: "(.*?)"/)?.[1] || yaml.match(/date: (.*)/)?.[1]
  const created_at = dateStr ? new Date(dateStr).toISOString() : new Date().toISOString()

  console.log(`Processing: ${title} (${created_at})`)

  // 2. Create Conversation
  const { data: conv, error: convErr } = await supabase
    .from("eve_conversations")
    .insert({
      user_id: USER_ID,
      title: title || "Imported Chat",
      created_at,
      updated_at: created_at,
      source: "grok"
    })
    .select("id")
    .single()

  if (convErr) {
    console.error(`  ❌ Error creating conversation: ${convErr.message}`)
    return
  }

  const conversation_id = conv.id

  // 3. Parse Messages
  // Users: > [!INFO] **User** (TIMESTAMP)
  // Eve: > [!ABSTRACT] **Grok** (TIMESTAMP)
  const messageRegex = /> \[!(INFO|ABSTRACT)\] \*\*(User|Grok)\*\* \((.*?)\)\n([\s\S]*?)(?=\n> \[!|$)/g
  let match
  const messages = []

  while ((match = messageRegex.exec(content)) !== null) {
    const role = match[2] === "User" ? "user" : "assistant"
    const timestamp = match[3]
    const body = match[4].trim().replace(/^> /gm, "")
    
    messages.push({
      user_id: USER_ID,
      conversation_id,
      role,
      content: body,
      created_at: new Date(timestamp).toISOString()
    })
  }

  if (messages.length > 0) {
    const { error: msgErr } = await supabase.from("eve_history").insert(messages)
    if (msgErr) {
      console.error(`  ❌ Error inserting messages: ${msgErr.message}`)
    } else {
      console.log(`  ✅ Inserted ${messages.length} messages`)
    }
  }
}

async function walk(dir) {
  const files = fs.readdirSync(dir)
  for (const file of files) {
    const fullPath = path.join(dir, file)
    if (fs.statSync(fullPath).isDirectory()) {
      await walk(fullPath)
    } else if (file.endsWith(".md") && file !== "Master Index.md") {
      await importFile(fullPath)
    }
  }
}

console.log("🚀 Starting import...")
walk(MEMORY_DIR)
  .then(() => console.log("✨ Done!"))
  .catch(err => console.error("💥 Fatal error:", err))
