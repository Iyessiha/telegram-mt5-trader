# 🚀 Deployment Guide - Telegram MT5 Trader

Complete step-by-step guide to deploy the system on Vercel.

## Prerequisites

- GitHub account with the repo cloned
- Telegram bot (from @BotFather)
- Supabase account with a project
- Vercel account (free tier works)
- MetaTrader 5 with your broker

---

## Step 1: Create Telegram Bot

### 1.1 Open Telegram and message @BotFather

```
/newbot
```

**Follow prompts:**
- Choose a name: `MT5 Trader Bot`
- Choose username: `mt5_trader_bot` (must end with `_bot`)

### 1.2 Save your token

BotFather will give you a token like:
```
123456789:ABCdefGHIjklmnoPQRstuvwxyz_1234567890
```

Save this for later (we'll call it `TELEGRAM_BOT_TOKEN`)

### 1.3 Disable Group Privacy

```
/setprivacy
Select: mt5_trader_bot
Disable
```

This allows the bot to read messages in channels/groups.

### 1.4 Generate a Secret Token

For security, create a random secret:
```bash
# On Linux/Mac:
openssl rand -hex 32

# Or use any random string (32+ characters recommended)
your_super_secret_token_here_12345678
```

Save this as `TELEGRAM_SECRET`

---

## Step 2: Setup Supabase

### 2.1 Create Supabase Project

1. Go to [supabase.com](https://supabase.com)
2. Click "New project"
3. Choose organization and project name
4. Set a strong password
5. Select region closest to you
6. Wait for project to initialize

### 2.2 Get Connection Details

In Supabase dashboard:

**Project Settings → API:**
- Copy `Project URL` → `NEXT_PUBLIC_SUPABASE_URL`
- Copy `anon public` key → NOT NEEDED (we use service key)
- Copy `service_role` key → `SUPABASE_SERVICE_ROLE_KEY`

Save both keys.

### 2.3 Create Database Table

**SQL Editor → New query:**

```sql
CREATE TABLE trading_signals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source TEXT NOT NULL CHECK (source IN ('telegram', 'api')),
  user_id TEXT NOT NULL,
  symbol TEXT NOT NULL,
  action TEXT NOT NULL CHECK (action IN ('BUY', 'SELL')),
  entry DECIMAL(20, 8) NOT NULL,
  stop_loss DECIMAL(20, 8) NOT NULL,
  take_profit DECIMAL(20, 8) NOT NULL,
  volume DECIMAL(20, 8) NOT NULL DEFAULT 1.0,
  status TEXT NOT NULL CHECK (status IN ('pending', 'executed', 'failed', 'cancelled')) DEFAULT 'pending',
  mt5_order_id BIGINT,
  error TEXT,
  raw_message TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  executed_at TIMESTAMP WITH TIME ZONE
);

-- Create indexes for performance
CREATE INDEX idx_signals_user ON trading_signals(user_id);
CREATE INDEX idx_signals_status ON trading_signals(status);
CREATE INDEX idx_signals_created ON trading_signals(created_at DESC);
```

Click "Run" to create the table.

---

## Step 3: Deploy to Vercel

### 3.1 Connect GitHub to Vercel

1. Go to [vercel.com](https://vercel.com)
2. Sign up / Sign in with GitHub
3. Click "New Project"
4. Select `telegram-mt5-trader` repository
5. Click "Import"

### 3.2 Configure Environment Variables

On the Vercel "Configure Project" page, add these variables:

**Build & Development Settings:**

Leave as default (Vercel auto-detects Node.js project)

**Environment Variables:**

Add each one:

| Variable | Value |
|----------|-------|
| `TELEGRAM_BOT_TOKEN` | Your bot token from @BotFather |
| `TELEGRAM_SECRET` | Your generated secret token |
| `NEXT_PUBLIC_SUPABASE_URL` | From Supabase Project Settings |
| `SUPABASE_SERVICE_ROLE_KEY` | From Supabase Project Settings |
| `MT5_API_URL` | (Optional) Your MT5 API endpoint |
| `MT5_API_KEY` | (Optional) Your MT5 API key |
| `LOCAL_MT5_SERVER` | (Optional) Your MT5 machine IP |
| `LOCAL_MT5_PORT` | (Optional) Port number (default 9000) |

**Important:** Use "Environment Variables" in Vercel dashboard for sensitive keys.

### 3.3 Deploy

Click "Deploy"

Wait for deployment to complete (usually 1-2 minutes).

**Your deployment URL:** `https://telegram-mt5-trader-xxxx.vercel.app`

---

## Step 4: Configure Telegram Webhook

### 4.1 Set Webhook

Once Vercel deployment is complete:

```bash
VERCEL_URL="https://telegram-mt5-trader-xxxx.vercel.app"
BOT_TOKEN="123456789:ABCdefGHIjklmnoPQRstuvwxyz"
SECRET="your_secret_token"

curl -X POST https://api.telegram.org/bot${BOT_TOKEN}/setWebhook \
  -d url="${VERCEL_URL}/api/telegram-webhook" \
  -d secret_token="${SECRET}"
```

**Success response:**
```json
{
  "ok": true,
  "result": true,
  "description": "Webhook was set"
}
```

### 4.2 Verify Webhook

```bash
curl -X GET https://api.telegram.org/bot${BOT_TOKEN}/getWebhookInfo
```

Should show your webhook URL with status `active`.

---

## Step 5: Setup MetaTrader 5

### 5.1 Install Expert Advisor

1. Download `mt5-ea-signal-receiver.mq5` from the repo
2. Copy to MetaTrader 5:
   ```
   C:\Users\YourUsername\AppData\Roaming\MetaQuotes\Terminal\XXXXX\MQL5\Experts
   ```
3. Restart MetaTrader 5
4. The EA will appear in Navigator → Expert Advisors

### 5.2 Attach EA to Chart

1. Open any chart
2. Drag the EA from Navigator to chart
3. Or: Right-click chart → Expert Advisors → Attach

### 5.3 Configure EA

In the EA settings dialog:

**Inputs tab:**

| Parameter | Value |
|-----------|-------|
| `WebhookURL` | Your Vercel deployment URL |
| `ApiKey` | Your MT5_API_KEY (if using REST) |
| `AllowBuy` | true |
| `AllowSell` | true |
| `DefaultVolume` | 1.0 |
| `MagicNumber` | 20260625 |
| `MaxDailyDrawdown` | 1000.0 |

**Common tab:**

- ✅ "Allow live trading"
- ✅ "Allow DLL imports"
- Set testing: OFF (not needed for webhook)

Click OK to attach.

### 5.4 Check Expert Output

**View → Toolbox → Expert tab**

Should show:
```
Telegram MT5 Trader EA initialized
EA started on EURUSD
```

---

## Step 6: Test the System

### 6.1 Test Signal Format

Send test message to bot:

```
BUY XAUUSD 2650 SL:2640 TP:2660 VOL:1.0
```

### 6.2 Monitor Execution

**Check Vercel logs:**
```bash
vercel logs
```

Should show something like:
```
[16:45:23] Received signal from user 123456789: BUY XAUUSD 2650 SL:2640 TP:2660
[16:45:23] Signal validated successfully
[16:45:23] Signal executed successfully. Order ID: 12345
```

**Check MT5 EA logs:**

View → Toolbox → Expert tab

Should show:
```
✓ Trade executed: BUY XAUUSD @ 2650.00000 (SL: 2640.00000, TP: 2660.00000)
Order ID: 1000001
```

### 6.3 Verify in Supabase

**Supabase Dashboard → trading_signals table:**

Should show the new signal with:
- `status`: "executed"
- `mt5_order_id`: populated
- `action`: "BUY"

---

## Step 7: Monitor & Maintenance

### Health Check Endpoint

```bash
curl https://your-deployment.vercel.app/api/health
```

Response should show:
```json
{
  "status": "OK",
  "services": {
    "supabase": "OK",
    "mt5": "OK"
  }
}
```

### View Recent Signals

```bash
curl "https://your-deployment.vercel.app/api/signals-list?limit=10"
```

### Check Errors

View failed signals:
```bash
curl "https://your-deployment.vercel.app/api/signals-list?status=failed"
```

---

## Troubleshooting

### Issue: Webhook not receiving signals

**Check:**
1. Telegram bot token is correct
2. Webhook URL is accessible:
   ```bash
   curl https://your-url.vercel.app/api/health
   ```
3. Secret token matches in both places
4. Check Vercel logs for errors

### Issue: Signals received but not executing on MT5

**Check:**
1. EA is attached to chart and running
2. MT5 connection details are correct
3. Account has enough balance
4. Symbol is available on broker
5. EA expert logs show no errors

### Issue: "Symbol not allowed"

**Add symbol to allowed list:**

Edit `lib/validation.ts` line ~10:
```typescript
const ALLOWED_SYMBOLS = ['XAUUSD', 'EURUSD', 'GBPUSD', 'YOUR_SYMBOL'];
```

Redeploy to Vercel:
```bash
git push origin main
```

Vercel will auto-redeploy.

### Issue: "Daily loss limit exceeded"

**Adjust limit in EA settings:**

In MetaTrader 5 → EA settings → `MaxDailyDrawdown`

Change to a higher value (e.g., 5000.0)

### Issue: Environment variables not working

1. Check Vercel dashboard → Settings → Environment Variables
2. Make sure you're editing the correct environment (Production vs Preview)
3. After adding/changing variables, redeploy:
   ```bash
   vercel deploy --prod
   ```

---

## Security Checklist

✅ **Telegram Secret:** Random, 32+ characters  
✅ **Supabase Service Key:** Stored in Vercel secrets (not in code)  
✅ **MT5 API Key:** Stored in Vercel secrets (not in code)  
✅ **GitHub:** Private repo or public with secrets not in commits  
✅ **SSL/TLS:** Vercel auto-enables HTTPS  
✅ **Rate Limiting:** Optional - add in Vercel edge middleware  

---

## Next Steps

1. **Monitor trades** via Supabase dashboard
2. **Optimize risk** by adjusting `MaxDailyDrawdown`
3. **Add more symbols** to allowed list
4. **Setup alerts** for failed signals
5. **Automate signal sending** from your analysis tool

---

## Support

📧 Email: support@monweinfinity.com  
🐙 GitHub: https://github.com/Iyessiha/telegram-mt5-trader  
📚 Docs: https://github.com/Iyessiha/telegram-mt5-trader/wiki  

---

**Deployed successfully! 🎉**

Track your signals at: `https://your-deployment.vercel.app/api/signals-list`
