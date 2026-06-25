# 🛠️ Local Development Guide

How to run and test the Telegram MT5 Trader locally.

## Prerequisites

- Node.js 18+ ([download](https://nodejs.org))
- Git
- Vercel CLI (`npm i -g vercel`)
- A text editor (VS Code recommended)

## Setup

### 1. Clone the Repository

```bash
git clone https://github.com/Iyessiha/telegram-mt5-trader.git
cd telegram-mt5-trader
```

### 2. Install Dependencies

```bash
npm install
```

### 3. Create Local Environment File

```bash
cp .env.example .env.local
```

Edit `.env.local` with your values:

```bash
# Telegram
TELEGRAM_BOT_TOKEN=your_bot_token_here
TELEGRAM_SECRET=your_webhook_secret_here

# Supabase
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your_service_key_here

# MT5 (optional for local testing)
MT5_API_URL=http://localhost:9000
MT5_API_KEY=test_key
```

## Development

### Start Local Dev Server

```bash
npm run dev
```

The server runs on: **http://localhost:3000**

API endpoints available:
- `POST http://localhost:3000/api/telegram-webhook`
- `GET http://localhost:3000/api/signals-list`
- `GET http://localhost:3000/api/health`

### Test with curl

**Send test signal:**

```bash
curl -X POST http://localhost:3000/api/telegram-webhook \
  -H "x-telegram-secret: your_webhook_secret" \
  -H "Content-Type: application/json" \
  -d '{
    "message": "BUY XAUUSD 2650 SL:2640 TP:2660 VOL:1.0",
    "user_id": "123456789"
  }'
```

**Get signals list:**

```bash
curl http://localhost:3000/api/signals-list
```

**Health check:**

```bash
curl http://localhost:3000/api/health
```

## Testing

### Test Signal Examples

Valid signals to test:

```
BUY XAUUSD 2650 SL:2640 TP:2660
SELL EURUSD 1.0850 SL:1.0870 TP:1.0800 VOL:2.0
BUY GBPUSD 1.2500 SL:1.2480 TP:1.2550 VOL:0.5
```

Invalid signals (will be rejected):

```
BUY XAUUSD 2650 SL:2650 TP:2660    # SL same as entry
SELL EURUSD 1.0850 SL:1.0800 TP:1.0950  # Bad risk/reward
BUY INVALID_SYMBOL 100 SL:90 TP:110  # Invalid symbol
```

### Test with Postman

1. Create a new POST request
2. URL: `http://localhost:3000/api/telegram-webhook`
3. Headers:
   ```
   x-telegram-secret: your_webhook_secret
   Content-Type: application/json
   ```
4. Body (JSON):
   ```json
   {
     "message": "BUY XAUUSD 2650 SL:2640 TP:2660 VOL:1.0",
     "user_id": "123456789"
   }
   ```
5. Send request

## Debug Mode

### Enable Debug Logging

Edit `api/telegram-webhook.ts` and add:

```typescript
console.log('Full request:', JSON.stringify(req.body, null, 2));
```

### Check Supabase Directly

```bash
# Connect to Supabase SQL editor and run:
SELECT * FROM trading_signals ORDER BY created_at DESC LIMIT 10;
```

### Browser DevTools

Open `http://localhost:3000` to inspect API calls in Network tab.

## Make Changes

### Add New Endpoint

Create `api/new-endpoint.ts`:

```typescript
import { VercelRequest, VercelResponse } from '@vercel/node';

export default function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }
  
  return res.status(200).json({ message: 'Hello!' });
}
```

Accessible at: `http://localhost:3000/api/new-endpoint`

### Modify Validation Rules

Edit `lib/validation.ts`:

```typescript
// Add new symbol
const ALLOWED_SYMBOLS = ['XAUUSD', 'EURUSD', 'NEW_SYMBOL'];

// Adjust volume limits
const MAX_VOLUME = 20;  // was 10
```

### Change Signal Parser

Edit `lib/telegram.ts` to support different message formats.

## Type Checking

Verify TypeScript types:

```bash
npm run type-check
```

Fix type errors:

```bash
npx tsc --noEmit
```

## Database

### View Data

```bash
# In Supabase SQL Editor:
SELECT * FROM trading_signals;
SELECT COUNT(*) FROM trading_signals WHERE status = 'executed';
```

### Reset Table

```sql
-- Delete all records
DELETE FROM trading_signals;

-- Or drop and recreate
DROP TABLE trading_signals;
-- Then run creation SQL from DEPLOYMENT.md
```

## Deployment

### Deploy to Vercel

After making changes locally:

```bash
# Commit changes
git add .
git commit -m "Add new feature"

# Push to GitHub
git push origin main

# Vercel auto-deploys (or manually):
vercel deploy --prod
```

### Preview Deployment

Test changes before prod:

```bash
vercel deploy --prebuilt
```

This creates a preview URL for testing.

## Environment Variables

### Local Development

Use `.env.local` (ignored by git):

```bash
TELEGRAM_BOT_TOKEN=test_token
SUPABASE_SERVICE_ROLE_KEY=test_key
```

### Production (Vercel)

Set in Vercel dashboard:
- **Settings → Environment Variables**
- Select "Production"
- Add your keys

### Preview (Pull Requests)

Optional: Set different keys for preview deployments.

## Troubleshooting

### "Cannot find module"

```bash
# Reinstall dependencies
rm -rf node_modules package-lock.json
npm install
```

### Port 3000 already in use

```bash
# Kill process on port 3000
npx kill-port 3000

# Or use different port
PORT=3001 npm run dev
```

### Supabase connection error

Check:
1. `.env.local` has correct `NEXT_PUBLIC_SUPABASE_URL`
2. Service role key is not the anon key
3. VPN/firewall not blocking Supabase

### TypeScript errors

```bash
# Check all files
npx tsc --noEmit

# Fix linting
npx eslint . --fix
```

## Best Practices

✅ **Always use `.env.local`** - Never commit real secrets  
✅ **Test before deploying** - Run locally first  
✅ **Check logs** - Use `vercel logs` for production issues  
✅ **Use branches** - Create feature branches before changes  
✅ **Write comments** - Document complex logic  
✅ **Handle errors** - Wrap API calls in try/catch  

## Project Structure

```
telegram-mt5-trader/
├── api/                 # Serverless API endpoints
│   ├── telegram-webhook.ts
│   ├── signals-list.ts
│   └── health.ts
├── lib/                 # Utility functions
│   ├── telegram.ts      # Signal parsing
│   ├── validation.ts    # Validation rules
│   ├── mt5.ts           # MT5 execution
│   └── supabase.ts      # Database client
├── types/               # TypeScript definitions
├── .env.example         # Environment template
├── .env.local          # (Local only, not in git)
├── package.json
├── tsconfig.json
└── README.md
```

## Next Steps

1. ✅ Clone and install locally
2. ✅ Configure `.env.local` with test credentials
3. ✅ Start dev server: `npm run dev`
4. ✅ Send test signals via curl
5. ✅ Monitor Supabase for signals
6. ✅ Make changes and test
7. ✅ Commit and push to GitHub
8. ✅ Vercel auto-deploys to production

## Questions?

- Check `README.md` for API documentation
- See `DEPLOYMENT.md` for production setup
- Review code comments in source files

---

**Happy developing! 🚀**
