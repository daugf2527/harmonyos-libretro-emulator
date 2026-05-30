#!/usr/bin/env node
/**
 * RomImportService 核心函数单元测试
 * 不依赖 @ohos.test 框架，使用 Node.js 原生断言
 */

// 模拟 RomImportService 的核心函数
const DOCUMENTATION_BASENAMES = [
  'readme', 'license', 'licence', 'copying', 'changelog', 'changes', 'notes',
  'authors', 'contributors', 'install', 'todo', 'history', 'news', 'credits'
];

const GAMBATTE_EXTENSIONS = ['gb', 'gbc', 'dmg'];
const MGBA_EXTENSIONS = ['gba', 'agb'];
const NESTOPIA_EXTENSIONS = ['nes', 'fds', 'unf', 'unif'];

function getRomFileExtension(fileName) {
  const dotIndex = fileName.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex === fileName.length - 1) {
    return '';
  }
  return fileName.substring(dotIndex + 1).toLowerCase();
}

function isLikelyDocumentationFile(fileName) {
  const slashIndex = Math.max(fileName.lastIndexOf('/'), fileName.lastIndexOf('\\'));
  const base = slashIndex >= 0 ? fileName.substring(slashIndex + 1) : fileName;
  const dotIndex = base.lastIndexOf('.');
  const stem = dotIndex > 0 ? base.substring(0, dotIndex) : base;
  return DOCUMENTATION_BASENAMES.includes(stem.toLowerCase());
}

function getPreferredCoreIdForFile(fileName) {
  if (isLikelyDocumentationFile(fileName)) {
    return '';
  }
  const ext = getRomFileExtension(fileName);
  if (GAMBATTE_EXTENSIONS.includes(ext)) {
    return 'gambatte';
  }
  if (MGBA_EXTENSIONS.includes(ext)) {
    return 'mgba';
  }
  if (NESTOPIA_EXTENSIONS.includes(ext)) {
    return 'nestopia';
  }
  return '';
}

// 测试用例
const tests = [
  // getRomFileExtension 测试
  { fn: 'getRomFileExtension', input: 'pokemon.gb', expected: 'gb', desc: '标准扩展名' },
  { fn: 'getRomFileExtension', input: 'game.GBA', expected: 'gba', desc: '大写扩展名' },
  { fn: 'getRomFileExtension', input: 'noext', expected: '', desc: '无扩展名' },
  { fn: 'getRomFileExtension', input: 'file.', expected: '', desc: '空扩展名' },
  { fn: 'getRomFileExtension', input: 'path/to/rom.nes', expected: 'nes', desc: '带路径' },

  // isLikelyDocumentationFile 测试
  { fn: 'isLikelyDocumentationFile', input: 'readme.txt', expected: true, desc: 'readme 文件' },
  { fn: 'isLikelyDocumentationFile', input: 'README.md', expected: true, desc: '大写 README' },
  { fn: 'isLikelyDocumentationFile', input: 'license', expected: true, desc: '无扩展名 license' },
  { fn: 'isLikelyDocumentationFile', input: 'game.gb', expected: false, desc: '普通 ROM 文件' },
  { fn: 'isLikelyDocumentationFile', input: 'path/to/readme.txt', expected: true, desc: '带路径的 readme' },
  { fn: 'isLikelyDocumentationFile', input: 'my-readme.txt', expected: false, desc: '非标准文档名' },

  // getPreferredCoreIdForFile 测试
  { fn: 'getPreferredCoreIdForFile', input: 'pokemon.gb', expected: 'gambatte', desc: 'GB ROM' },
  { fn: 'getPreferredCoreIdForFile', input: 'metroid.gba', expected: 'mgba', desc: 'GBA ROM' },
  { fn: 'getPreferredCoreIdForFile', input: 'mario.nes', expected: 'nestopia', desc: 'NES ROM' },
  { fn: 'getPreferredCoreIdForFile', input: 'readme.txt', expected: '', desc: '文档文件返回空' },
  { fn: 'getPreferredCoreIdForFile', input: 'unknown.xyz', expected: '', desc: '未知扩展名' },
];

// 运行测试
let passed = 0;
let failed = 0;

console.log('=== RomImportService 核心函数测试 ===\n');

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
