/**
 * Arena — The Executor
 * Nexus middleware layer that takes action in the real world.
 * Eve thinks and plans. Arena does.
 *
 * Run: npm run dev
 */

import express, { Request, Response } from 'express';

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3001;

// ── Logging ───────────────────────────────────────────────────────────────────
function log(action: string, payload: object, result: object) {
  console.log(`[Arena] ${new Date().toISOString()} | ${action}`, { payload, result });
  // TODO: write to Supabase action_log table
}

// ── Health check ──────────────────────────────────────────────────────────────
app.get('/health', (_req: Request, res: Response) => {
  res.json({ status: 'ok', service: 'Arena' });
});

// ── ClickUp Integration ───────────────────────────────────────────────────────
app.post('/task/create', async (req: Request, res: Response) => {
  const { title, description, assignee, due } = req.body;

  try {
    // TODO: replace with real ClickUp API call
    // const clickup = new ClickUpClient(process.env.CLICKUP_API_KEY);
    // const task = await clickup.tasks.create({ title, description, assignee, due });

    const result = {
      success: true,
      task_id: `MOCK-${Date.now()}`,
      title,
      message: `Task "${title}" created in ClickUp`
    };

    log('task/create', req.body, result);
    res.json(result);
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

app.post('/task/update', async (req: Request, res: Response) => {
  const { task_id, status, notes } = req.body;

  try {
    // TODO: real ClickUp update
    const result = { success: true, task_id, status, message: `Task ${task_id} updated` };
    log('task/update', req.body, result);
    res.json(result);
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

// ── Payment Routing ───────────────────────────────────────────────────────────
app.post('/payment/route', async (req: Request, res: Response) => {
  const { amount, currency = 'USD', splits, reference } = req.body;
  // splits = [{ destination: 'operations', amount: 400 }, { destination: 'growth', amount: 600 }]

  try {
    const total = splits?.reduce((sum: number, s: { amount: number }) => sum + s.amount, 0);
    if (total !== amount) {
      return res.status(400).json({
        success: false,
        error: `Split amounts (${total}) don't match total (${amount})`
      });
    }

    // TODO: real payment routing (Stripe, crypto, bank transfer)
    const result = {
      success: true,
      reference,
      amount,
      currency,
      splits,
      message: `$${amount} routed: ${splits?.map((s: any) => `$${s.amount} → ${s.destination}`).join(', ')}`
    };

    log('payment/route', req.body, result);
    res.json(result);
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

// ── Sync trigger (from iPhone "Hey Sync") ─────────────────────────────────────
app.post('/sync/push', async (req: Request, res: Response) => {
  const { user_id } = req.body;

  try {
    // TODO: package latest memory files and push to Supabase memory_updates table
    const result = {
      success: true,
      user_id,
      message: 'Memory package pushed to Supabase — iPhone can now pull'
    };
    log('sync/push', req.body, result);
    res.json(result);
  } catch (error) {
    res.status(500).json({ success: false, error: String(error) });
  }
});

// ── Start ─────────────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`✅ Arena running on port ${PORT}`);
});
