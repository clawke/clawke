import type BetterSqlite3 from 'better-sqlite3';
import type { Database } from './database.js';

export class GatewayModelCacheStore {
  private readonly selectStmt: BetterSqlite3.Statement;
  private readonly replaceTransaction: BetterSqlite3.Transaction;

  constructor(database: Database) {
    const db = database.raw;
    db.exec(`
      CREATE TABLE IF NOT EXISTS gateway_model_cache (
        gateway_id TEXT NOT NULL,
        model_id TEXT NOT NULL,
        display_name TEXT,
        provider TEXT,
        raw_json TEXT,
        updated_at INTEGER NOT NULL,
        last_seen_at INTEGER NOT NULL,
        PRIMARY KEY (gateway_id, model_id)
      );
      CREATE INDEX IF NOT EXISTS idx_gateway_model_cache_gateway
        ON gateway_model_cache(gateway_id, model_id);
    `);

    this.selectStmt = db.prepare(`
      SELECT model_id
      FROM gateway_model_cache
      WHERE gateway_id = ?
      ORDER BY model_id ASC
    `);
    const deleteStmt = db.prepare('DELETE FROM gateway_model_cache WHERE gateway_id = ?');
    const insertStmt = db.prepare(`
      INSERT INTO gateway_model_cache (
        gateway_id,
        model_id,
        display_name,
        provider,
        raw_json,
        updated_at,
        last_seen_at
      ) VALUES (
        @gateway_id,
        @model_id,
        @display_name,
        @provider,
        @raw_json,
        @updated_at,
        @last_seen_at
      )
    `);
    this.replaceTransaction = db.transaction((gatewayId: string, models: string[], now: number) => {
      deleteStmt.run(gatewayId);
      for (const modelId of models) {
        insertStmt.run({
          gateway_id: gatewayId,
          model_id: modelId,
          display_name: modelId,
          provider: providerFromModelId(modelId),
          raw_json: JSON.stringify({ id: modelId }),
          updated_at: now,
          last_seen_at: now,
        });
      }
    });
  }

  getGatewayModels(gatewayId: string): string[] {
    return (this.selectStmt.all(gatewayId) as Array<{ model_id: string }>)
      .map((row) => row.model_id)
      .filter(Boolean);
  }

  replaceGatewayModels(gatewayId: string, models: string[]): void {
    const uniqueModels = [...new Set(models.map((model) => model.trim()).filter(Boolean))].sort();
    this.replaceTransaction(gatewayId, uniqueModels, Date.now());
  }
}

function providerFromModelId(modelId: string): string | null {
  const index = modelId.indexOf('/');
  if (index <= 0) return null;
  return modelId.slice(0, index);
}
