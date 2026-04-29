import fs from "fs"
import { createClient } from "@supabase/supabase-js"

// Manually parse .env.local
const envFile = fs.readFileSync(".env.local", "utf8")
const getEnv = (key) => envFile.match(new RegExp(`^${key}=(.*)`, "m"))?.[1]

const SUPABASE_URL = getEnv("NEXT_PUBLIC_SUPABASE_URL")
const SUPABASE_KEY = getEnv("SUPABASE_SERVICE_ROLE_KEY") || getEnv("SUPABASE_SECRET_KEY")
const USER_ID = "e9d9a15b-0e5a-4631-9b50-6225ee03a44f" // The one used in Nexus Web
const JSON_PATH = "../memory/eve-private/prod-grok-backend.json"

if (!SUPABASE_URL || !SUPABASE_KEY) {
  console.error("❌ Missing Supabase credentials")
  process.exit(1)
}

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY)

async function run() {
  console.log("🚀 Loading 71MB JSON... (this might take a second)")
  const rawData = JSON.parse(fs.readFileSync(JSON_PATH, "utf8"))
  const conversations = rawData.conversations

  console.log(`✨ Found ${conversations.length} conversations.`)

  // We wipe the old ones to avoid messy duplication since the JSON is the absolute source
  console.log("🧹 Clearing old history...")
  await supabase.from("eve_history").delete().eq("user_id", USER_ID)
  await supabase.from("eve_conversations").delete().eq("user_id", USER_ID)

  for (const item of conversations) {
    const meta = item.conversation
    const responses = item.responses

    // Format metadata
    const created_at = meta.create_time
    const updated_at = meta.modify_time || created_at
    const title = meta.title || "Untitled Session"

    console.log(`📦 Importing: ${title} (${responses.length} messages)`)

    const { data: conv, error: convErr } = await supabase
      .from("eve_conversations")
      .insert({
        user_id: USER_ID,
        title,
        created_at,
        updated_at,
        source: "grok"
      })
      .select("id")
      .single()

    if (convErr) {
      console.error(`  ❌ Error: ${convErr.message}`)
      continue
    }

    const conversation_id = conv.id
    const messages = responses.map(r => {
      const resp = r.response
      let ts = resp.create_time
      // Handle the Mongodb-style date object
      if (typeof ts === "object" && ts.$date) {
        ts = new Date(parseInt(ts.$date.$numberLong)).toISOString()
      }

      return {
        user_id: USER_ID,
        conversation_id,
        role: resp.sender === "human" ? "user" : "assistant",
        content: resp.message || "",
        created_at: ts
      }
    })

    // Insert in batches of 500 to stay under payload limits
    const BATCH_SIZE = 500
    for (let i = 0; i < messages.length; i += BATCH_SIZE) {
      const batch = messages.slice(i, i + BATCH_SIZE)
      const { error: msgErr } = await supabase.from("eve_history").insert(batch)
      if (msgErr) console.error(`  ❌ Batch Error: ${msgErr.message}`)
    }
    
    console.log(`  ✅ Success: ${messages.length} messages inserted.`)
  }

  console.log("🎉 DEEP IMPORT COMPLETE!")
}

run().catch(console.error)
