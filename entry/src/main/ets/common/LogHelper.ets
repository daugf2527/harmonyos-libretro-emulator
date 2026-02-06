import hilog from '@ohos.hilog';

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
}
