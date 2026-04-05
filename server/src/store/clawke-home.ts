/**
 * Clawke 运行时数据目录管理
 *
 * 所有运行时数据统一存放在 ~/.clawke/ 下。
 * 可通过环境变量 CLAWKE_DATA_DIR 覆盖（CI、Docker 等场景）。
 */
import * as os from 'os';
import * as path from 'path';
import * as fs from 'fs';

export const CLAWKE_HOME = process.env.CLAWKE_DATA_DIR
  || path.join(os.homedir(), '.clawke');

export const DATA_DIR = path.join(CLAWKE_HOME, 'data');
export const UPLOAD_DIR = path.join(CLAWKE_HOME, 'uploads');
export const THUMB_DIR = path.join(CLAWKE_HOME, 'uploads', 'thumbs');
export const BIN_DIR = path.join(CLAWKE_HOME, 'bin');

/**
 * 确保所有运行时目录存在（首次启动时调用）
 */
export function ensureDirectories(): void {
  for (const dir of [DATA_DIR, UPLOAD_DIR, THUMB_DIR, BIN_DIR]) {
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
  }
}
