import { hilog } from '@kit.PerformanceAnalysisKit';

export default class LogHelper {
  static info(tag: string, flow: string, message: string, domain: number = 0xD003): void {
    hilog.info(domain, tag, `【${tag}】【${flow}】 ${message}`);
  }

  static warn(tag: string, flow: string, message: string, domain: number = 0xD003): void {
    hilog.warn(domain, tag, `【${tag}】【${flow}】 ${message}`);
  }

  static error(tag: string, flow: string, message: string, domain: number = 0xD003): void {
    hilog.error(domain, tag, `【${tag}】【${flow}】 ${message}`);
  }

  static describePathForLog(path: string): string {
    if (!path || path.length === 0) {
      return '<empty>';
    }
    const normalized = path.replace(/\\/g, '/').trim();
    const slash = normalized.lastIndexOf('/');
    const name = slash >= 0 ? normalized.substring(slash + 1) : normalized;
    let ext = 'no_ext';
    const dot = name.lastIndexOf('.');
    if (dot > 0 && dot < name.length - 1 && name.length - dot <= 16) {
      let safe = true;
      for (let index = dot + 1; index < name.length; index += 1) {
        const code = name.charCodeAt(index);
        const char = name.charAt(index);
        if (!((code >= 48 && code <= 57) ||
          (code >= 65 && code <= 90) ||
          (code >= 97 && code <= 122) ||
          char === '_' ||
          char === '-')) {
          safe = false;
          break;
        }
      }
      if (safe) {
        ext = `ext=${name.substring(dot)}`;
      }
    }
    if (normalized.startsWith('roms/') || normalized.startsWith('./roms/')) {
      return `rawfile:${ext}`;
    }
    if (normalized.startsWith('/')) {
      return `absolute:${ext}`;
    }
    return `relative:${ext}`;
  }
}
