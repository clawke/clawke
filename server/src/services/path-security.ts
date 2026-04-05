/**
 * 路径安全校验模块
 *
 * 防止路径穿越攻击，确保用户提供的文件名/路径不会逃逸出基础目录。
 */
import path from 'path';

/** 检查文件名是否安全（无路径穿越字符） */
export function isFilenameSafe(filename: string): boolean {
  if (!filename || typeof filename !== 'string') return false;
  if (filename.length === 0) return false;
  if (filename.includes('..')) return false;
  if (filename.includes('/') || filename.includes('\\')) return false;
  return true;
}

/**
 * 安全地解析路径，确保结果不逃逸出基础目录
 * @throws {Error} 如果路径不安全
 */
export function resolveSafePath(baseDir: string, userPath: string): string {
  if (!isFilenameSafe(userPath)) {
    throw new Error(`Unsafe path: ${userPath}`);
  }
  const resolved = path.resolve(baseDir, userPath);
  if (!resolved.startsWith(path.resolve(baseDir))) {
    throw new Error(`Path escapes base directory: ${userPath}`);
  }
  return resolved;
}
