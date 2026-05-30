#!/usr/bin/env node
/**
 * RuntimeRomCatalog 核心函数单元测试
 */

// 模拟核心函数
function getFileExtension(fileName) {
  const dotIndex = fileName.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex === fileName.length - 1) {
    return '';
  }
  return fileName.substring(dotIndex + 1).toLowerCase();
}

function getFileNameFromPath(path) {
  const normalizedPath = path.split('?')[0];
  const slashIndex = normalizedPath.lastIndexOf('/');
  if (slashIndex >= 0 && slashIndex < normalizedPath.length - 1) {
    return normalizedPath.substring(slashIndex + 1);
  }
  return normalizedPath;
}

const DOCUMENTATION_BASENAMES = [
  'readme', 'license', 'licence', 'copying', 'changelog', 'changes', 'notes',
  'authors', 'contributors', 'install', 'todo', 'history', 'news', 'credits'
];

function isLikelyDocumentationFile(fileName) {
  const slashIndex = Math.max(fileName.lastIndexOf('/'), fileName.lastIndexOf('\\'));
  const base = slashIndex >= 0 ? fileName.substring(slashIndex + 1) : fileName;
  const dotIndex = base.lastIndexOf('.');
  const stem = dotIndex > 0 ? base.substring(0, dotIndex) : base;
  return DOCUMENTATION_BASENAMES.includes(stem.toLowerCase());
}

// 测试用例
const tests = [
  // getFileExtension 测试
  { fn: 'getFileExtension', input: 'game.gb', expected: 'gb', desc: '标准扩展名' },
  { fn: 'getFileExtension', input: 'ROM.GBA', expected: 'gba', desc: '大写扩展名' },
  { fn: 'getFileExtension', input: 'noext', expected: '', desc: '无扩展名' },
  { fn: 'getFileExtension', input: 'file.', expected: '', desc: '空扩展名' },
  { fn: 'getFileExtension', input: 'multi.dot.nes', expected: 'nes', desc: '多个点' },

  // getFileNameFromPath 测试
  { fn: 'getFileNameFromPath', input: 'roms/gba/metroid.gba', expected: 'metroid.gba', desc: '标准路径' },
  { fn: 'getFileNameFromPath', input: 'game.gb', expected: 'game.gb', desc: '无路径' },
  { fn: 'getFileNameFromPath', input: 'path/to/rom.nes?query=1', expected: 'rom.nes', desc: '带查询参数' },
  { fn: 'getFileNameFromPath', input: '/absolute/path/file.gba', expected: 'file.gba', desc: '绝对路径' },
  { fn: 'getFileNameFromPath', input: 'trailing/', expected: 'trailing/', desc: '尾部斜杠' },

  // isLikelyDocumentationFile 测试（与 RomImportService 相同逻辑）
  { fn: 'isLikelyDocumentationFile', input: 'readme.txt', expected: true, desc: 'readme 文件' },
  { fn: 'isLikelyDocumentationFile', input: 'LICENSE', expected: true, desc: '大写 LICENSE' },
  { fn: 'isLikelyDocumentationFile', input: 'changelog.md', expected: true, desc: 'changelog 文件' },
  { fn: 'isLikelyDocumentationFile', input: 'game.gb', expected: false, desc: '普通 ROM' },
  { fn: 'isLikelyDocumentationFile', input: 'roms/readme.txt', expected: true, desc: '带路径的文档' },
];

// 运行测试
let passed = 0;
let failed = 0;

console.log('=== RuntimeRomCatalog 核心函数测试 ===\n');

tests.forEach((test, index) => {
  const fn = eval(test.fn);
  const result = fn(test.input);
  const success = result === test.expected;

  if (success) {
    passed++;
    console.log(`✓ Test ${index + 1}: ${test.fn}('${test.input}') - ${test.desc}`);
  } else {
    failed++;
    console.log(`✗ Test ${index + 1}: ${test.fn}('${test.input}') - ${test.desc}`);
    console.log(`  Expected: ${JSON.stringify(test.expected)}`);
    console.log(`  Got: ${JSON.stringify(result)}`);
  }
});

console.log(`\n=== 测试结果 ===`);
console.log(`通过: ${passed}/${tests.length}`);
console.log(`失败: ${failed}/${tests.length}`);

process.exit(failed > 0 ? 1 : 0);
