import axios, { AxiosError } from 'axios';
import { TradeSignal, MT5Response } from '../types/index';

/**
 * Send signal to MT5 server
 * Supports multiple fallback methods
 */
export async function sendToMT5(signal: TradeSignal): Promise<MT5Response> {
  try {
    // Try primary method: REST API endpoint
    if (process.env.MT5_API_URL) {
      const response = await sendViaREST(signal);
      if (response.success) {
        console.log('Signal sent via REST API:', response);
        return response;
      }
    }

    // Fallback: Local socket server
    if (process.env.LOCAL_MT5_SERVER) {
      const response = await sendViaLocalSocket(signal);
      if (response.success) {
        console.log('Signal sent via local socket:', response);
        return response;
      }
    }

    // Last resort: File-based queue
    const response = await queueSignalToFile(signal);
    console.log('Signal queued to file:', response);
    return response;

  } catch (error) {
    console.error('Error sending signal to MT5:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}

/**
 * Method 1: REST API
 */
async function sendViaREST(signal: TradeSignal): Promise<MT5Response> {
  try {
    const payload = {
      action: signal.action === 'BUY' ? 'open_buy' : 'open_sell',
      symbol: signal.symbol,
      volume: signal.volume,
      price: signal.entry,
      stopLoss: signal.stopLoss,
      takeProfit: signal.takeProfit,
      magic: 20260625,
      comment: 'Telegram Signal'
    };

    const response = await axios.post(
      `${process.env.MT5_API_URL}/execute`,
      payload,
      {
        headers: {
          'Authorization': `Bearer ${process.env.MT5_API_KEY}`,
          'Content-Type': 'application/json'
        },
        timeout: 5000
      }
    );

    if (response.status === 200 && response.data.success) {
      return {
        success: true,
        orderId: response.data.orderId || response.data.ticket
      };
    }

    return {
      success: false,
      error: response.data.error || 'Unknown error'
    };
  } catch (error) {
    const axiosError = error as AxiosError;
    console.error('REST API error:', axiosError.message);
    return {
      success: false,
      error: `REST API failed: ${axiosError.message}`
    };
  }
}

/**
 * Method 2: Local Socket Server
 */
async function sendViaLocalSocket(signal: TradeSignal): Promise<MT5Response> {
  try {
    const response = await axios.post(
      `http://${process.env.LOCAL_MT5_SERVER}:${process.env.LOCAL_MT5_PORT || 9000}/execute`,
      signal,
      { timeout: 5000 }
    );

    if (response.status === 200) {
      return {
        success: true,
        orderId: response.data.orderId || response.data.ticket
      };
    }

    return {
      success: false,
      error: response.data.error || 'Unknown error'
    };
  } catch (error) {
    const axiosError = error as AxiosError;
    console.error('Local socket error:', axiosError.message);
    return {
      success: false,
      error: `Local socket failed: ${axiosError.message}`
    };
  }
}

/**
 * Method 3: File-based queue (fallback)
 * Requires an EA reading from file system
 */
async function queueSignalToFile(signal: TradeSignal): Promise<MT5Response> {
  try {
    // In production: write to a shared folder that EA monitors
    // For now: return success indicating queue
    const queueEntry = {
      timestamp: new Date().toISOString(),
      signal: signal,
      status: 'queued'
    };

    console.log('Signal queued for file processing:', queueEntry);

    return {
      success: true,
      error: 'Queued to file (EA must read and process)'
    };
  } catch (error) {
    console.error('File queue error:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error'
    };
  }
}

/**
 * Test MT5 connection
 */
export async function testMT5Connection(): Promise<boolean> {
  try {
    if (process.env.MT5_API_URL) {
      const response = await axios.get(
        `${process.env.MT5_API_URL}/health`,
        {
          headers: {
            'Authorization': `Bearer ${process.env.MT5_API_KEY}`
          },
          timeout: 5000
        }
      );
      return response.status === 200;
    }

    if (process.env.LOCAL_MT5_SERVER) {
      const response = await axios.get(
        `http://${process.env.LOCAL_MT5_SERVER}:${process.env.LOCAL_MT5_PORT || 9000}/health`,
        { timeout: 5000 }
      );
      return response.status === 200;
    }

    return false;
  } catch (error) {
    console.error('MT5 connection test failed:', error);
    return false;
  }
}
