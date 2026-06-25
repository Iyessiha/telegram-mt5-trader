import { VercelRequest, VercelResponse } from '@vercel/node';
import { supabase } from '@/lib/supabase';

/**
 * GET /api/signals-list
 * Get list of recent trading signals
 */
export default async function handler(
  req: VercelRequest,
  res: VercelResponse
) {
  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const { limit = 50, status, symbol } = req.query;

    let query = supabase
      .from('trading_signals')
      .select('*')
      .order('created_at', { ascending: false });

    // Filter by status if provided
    if (status && typeof status === 'string') {
      query = query.eq('status', status);
    }

    // Filter by symbol if provided
    if (symbol && typeof symbol === 'string') {
      query = query.eq('symbol', symbol);
    }

    // Apply limit
    const limitNum = Math.min(parseInt(String(limit)), 200);
    query = query.limit(limitNum);

    const { data, error } = await query;

    if (error) {
      console.error('Database error:', error);
      return res.status(500).json({ 
        error: 'Failed to fetch signals',
        details: error.message 
      });
    }

    return res.status(200).json({
      success: true,
      count: data?.length || 0,
      signals: data || []
    });

  } catch (error) {
    console.error('API error:', error);
    return res.status(500).json({ 
      error: 'Internal server error',
      message: error instanceof Error ? error.message : 'Unknown error'
    });
  }
}
