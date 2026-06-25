# Telegram MT5 Trader 🚀

Automated trading system that receives trading signals from Telegram and executes them on MetaTrader 5.

## Features

✅ **Telegram Integration** - Receive trade signals directly from Telegram  
✅ **MT5 Execution** - Automatically execute orders on MetaTrader 5  
✅ **Signal Validation** - Comprehensive validation with risk/reward checks  
✅ **Database Tracking** - All signals stored in Supabase for auditing  
✅ **Multiple Fallbacks** - REST API, Local Socket, File-based queue  
✅ **Vercel Deployment** - Serverless and scalable  

## Signal Format

```
BUY XAUUSD 2650 SL:2640 TP:2660 VOL:1.0
```

**Parameters:**
- `ACTION`: BUY or SELL
- `SYMBOL`: Trading pair (XAUUSD, EURUSD, etc.)
- `ENTRY`: Entry price
- `SL:value`: Stop Loss price
- `TP:value`: Take Profit price
- `VOL:value`: Volume (optional, default 1.0)

**Example valid signals:**
```
BUY XAUUSD 2650 SL:2640 TP:2660
SELL EURUSD 1.0850 SL:1.0870 TP:1.0800 VOL:2.0
BUY GBPUSD 1.2500 SL:1.2480 TP:1.2550 VOL:0.5
```

## Installation

### 1. Clone Repository
```bash
git clone https://github.com/Iyessiha/telegram-mt5-trader.git
cd telegram-mt5-trader
```

### 2. Install Dependencies
```bash
npm install
```

### 3. Configure Environment
```bash
cp .env.example .env
# Edit .env with your credentials
```

### 4. Deploy to Vercel
```bash
npm i -g vercel
vercel login
vercel link
vercel env add TELEGRAM_SECRET
vercel env add TELEGRAM_BOT_TOKEN
vercel env add NEXT_PUBLIC_SUPABASE_URL
vercel env add SUPABASE_SERVICE_ROLE_KEY
vercel env add MT5_API_KEY
vercel deploy --prod
```

## Setup

### Create Telegram Bot
1. Message [@BotFather](https://t.me/botfather) on Telegram
2. `/newbot` → choose a name and username
3. Copy the token (save for .env)
4. Disable Group Privacy: `/setprivacy` → select bot → Disable
5. Set Webhook on your domain

### Create Supabase Project
1. Go to [supabase.com](https://supabase.com)
2. Create a new project
3. Copy the URL and Service Role Key
4. Create `trading_signals` table with the schema in `/lib/supabase.ts`

### Configure MT5
Choose one connection method:

**Option A: REST API** (Recommended)
- Requires MT5 Server with REST endpoint
- Set `MT5_API_URL` and `MT5_API_KEY`

**Option B: Local Socket**
- Run a Node.js server on your MT5 machine
- Set `LOCAL_MT5_SERVER` and `LOCAL_MT5_PORT`

**Option C: File Queue**
- EA reads signals from shared folder
- Works when API unavailable

## API Endpoints

### Send Signal (via Webhook)
```bash
curl -X POST https://your-app.vercel.app/api/telegram-webhook \
  -H "x-telegram-secret: YOUR_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "message": "BUY XAUUSD 2650 SL:2640 TP:2660 VOL:1.0",
    "user_id": "123456789"
  }'
```

### Get Signals List
```bash
curl https://your-app.vercel.app/api/signals-list?limit=50&status=executed
```

### Health Check
```bash
curl https://your-app.vercel.app/api/health
```

## Telegram Webhook Setup

After deploying to Vercel:

```bash
curl -X POST https://api.telegram.org/bot<YOUR_BOT_TOKEN>/setWebhook \
  -d url="https://your-app.vercel.app/api/telegram-webhook" \
  -d secret_token="YOUR_TELEGRAM_SECRET"
```

## Allowed Symbols

- XAUUSD (Gold)
- EURUSD
- GBPUSD
- USDJPY
- AUDUSD
- NZDUSD
- USDCAD
- USDCHF

Add more symbols in `lib/validation.ts`

## Validation Rules

✓ Risk/Reward ratio minimum 1:1  
✓ Stop Loss must be different from Entry  
✓ Take Profit must be different from Entry  
✓ For BUY: TP > Entry, SL < Entry  
✓ For SELL: TP < Entry, SL > Entry  
✓ Volume between 0.01 and 10  
✓ Symbol must be in allowed list  

## MQL5 Expert Advisor

Download the EA to receive signals: [See `mt5-ea/` folder]

```mql5
// Copy to MT5 Experts folder
// Attach to chart
// Configure:
// - WebhookURL
// - ApiKey
// - SymbolFilter
```

## Monitoring

Check recent signals:
```bash
curl https://your-app.vercel.app/api/signals-list?limit=10&status=executed
```

View failed signals:
```bash
curl https://your-app.vercel.app/api/signals-list?status=failed
```

## Error Handling

All errors are logged to Vercel function logs:
```bash
vercel logs
```

Common issues:
- `Unauthorized`: Invalid TELEGRAM_SECRET
- `Invalid signal format`: Wrong message format
- `MT5 connection failed`: MT5 server unreachable
- `Database error`: Supabase connection issue

## Security

🔒 All endpoints require TELEGRAM_SECRET  
🔒 Supabase uses Service Role Key (server-only)  
🔒 API keys not exposed in client  
🔒 Signal validation prevents injection  
🔒 Rate limiting recommended (add in Vercel)  

## Development

```bash
# Local development
npm run dev

# Type checking
npm run type-check

# Lint
npm run lint
```

## Project Structure

```
telegram-mt5-trader/
├── api/                    # API endpoints
│   ├── telegram-webhook.ts # Main webhook
│   ├── signals-list.ts     # List signals
│   └── health.ts           # Health check
├── lib/                    # Utilities
│   ├── telegram.ts         # Signal parser
│   ├── validation.ts       # Validation logic
│   ├── mt5.ts              # MT5 execution
│   └── supabase.ts         # Database client
├── types/                  # TypeScript types
│   └── index.ts
├── package.json
├── tsconfig.json
├── vercel.json
└── README.md
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| TELEGRAM_BOT_TOKEN | Yes | Telegram bot token from @BotFather |
| TELEGRAM_SECRET | Yes | Webhook secret for verification |
| NEXT_PUBLIC_SUPABASE_URL | Yes | Supabase project URL |
| SUPABASE_SERVICE_ROLE_KEY | Yes | Supabase service role key |
| MT5_API_URL | No | MT5 REST API endpoint |
| MT5_API_KEY | No | MT5 API key |
| LOCAL_MT5_SERVER | No | Local MT5 server IP |
| LOCAL_MT5_PORT | No | Local MT5 server port |

## License

MIT

## Support

📧 Email: support@monweinfinity.com  
🔗 Website: https://monweinfinity.com  

---

**Built with** ❤️ by [MonWe Infinity LLC](https://monweinfinity.com)
