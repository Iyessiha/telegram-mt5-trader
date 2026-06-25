import { VercelRequest, VercelResponse } from '@vercel/node';
import { supabase } from '@/lib/supabase';
import { testMT5Connection } from '@/lib/mt5';

/**
 * GET /api/health
 * Check system health and connection status
 */
export default async function handler(
  req: VercelRequest,
  res: VercelResponse
) {
  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const health = {
      timestamp: new Date().toISOString(),
      status: 'OK',
      services: {
        supabase: 'unknown',
        mt5: 'unknown'
      }
    };

    // Test Supabase connection
    try {
      const { count, error } = await supabase
        .from('trading_signals')
        .select('*', { count: 'exact' })
        .limit(1);

      health.services.supabase = error ? 'ERROR' : 'OK';
    } catch (error) {
      health.services.supabase = 'ERROR';
    }

    // Test MT5 connection
    try {
      const mt5Ok = await testMT5Connection();
      health.services.mt5 = mt5Ok ? 'OK' : 'UNREACHABLE';
    } catch (error) {
      health.services.mt5 = 'ERROR';
    }

    // Overall status
    const allOk = Object.values(health.services).every(s => s === 'OK');
    health.status = allOk ? 'OK' : 'DEGRADED';

    return res.status(allOk ? 200 : 503).json(health);

  } catch (error) {
    console.error('Health check error:', error);
    return res.status(500).json({ 
      error: 'Health check failed',
      message: error instanceof Error ? error.message : 'Unknown error'
    });
  }
}
