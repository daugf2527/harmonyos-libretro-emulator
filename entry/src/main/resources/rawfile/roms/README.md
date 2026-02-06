# Game Boy ROM 测试文件

这个目录用于存放 Game Boy ROM 文件进行测试。

## 推荐的测试 ROM

### 1. Snake (贪吃蛇) - 开源
- **项目**: https://github.com/raph080/gbSnake
- **下载**: https://github.com/raph080/gbSnake/releases/download/v0.1/snake.gb
- **许可**: Apache-2.0
- **文件名**: `snake.gb`

### 2. Adjustris (俄罗斯方块克隆) - 开源
- **项目**: https://github.com/tbsp/simple-gb-asm-demo
- **许可**: MIT
- **文件名**: `tetris.gb`

### 3. Tobu Tobu Girl - 开源
- **项目**: https://github.com/SimonLarsen/tobutobugirl
- **下载**: https://tangramgames.itch.io/tobu-tobu-girl
- **许可**: MIT
- **文件名**: `tobutobugirl.gb`

## 使用方法

1. 下载上述任一 ROM 文件
2. 将 ROM 文件放到这个目录
3. 运行 Gambatte 测试程序
4. 测试代码会自动加载 ROM 并运行

## 注意事项

- ✅ 只使用合法的开源 ROM 或你自己拥有的 ROM
- ❌ 不要使用盗版商业 ROM
- ✅ 支持的格式: `.gb` (Game Boy) 和 `.gbc` (Game Boy Color)

## 当前测试 ROM

请将你的测试 ROM 文件放在这里：
- `snake.gb` - 贪吃蛇游戏
- `tetris.gb` - 俄罗斯方块（如果有）

## 下载命令

```bash
# 下载 Snake ROM
curl -L -o snake.gb https://github.com/raph080/gbSnake/releases/download/v0.1/snake.gb

# 或者使用 wget
wget -O snake.gb https://github.com/raph080/gbSnake/releases/download/v0.1/snake.gb
```
