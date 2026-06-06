#!/usr/bin/perl
# gc Pattern 7 — ArkTS async-@State 守卫启发式检测(D018 根治工具)
#
# 检测"async 方法体内 await 之后写 @State 字段,但该写之前无生命周期守卫"的竞态
# (页面销毁后 setState on destroyed,use-after-free 类,见 D016/D017/D018)。
#
# 启发式 + human-review:必有误报(方法只在 active 时调 / 守卫用未识别形式 /
# private 字段被收为 @State 等),输出为候选清单,需人工复核确认真遗漏。
#
# 逐行状态机:遇 await → seen_await=1,guarded=0;遇守卫 → guarded=1;
#   遇 this.<@State字段>= 且 seen_await && !guarded → flag(await 后未经守卫就写 @State)。
#   每个 await 重置 guarded(每个 await 后都需各自守卫)。已修方法(await→守卫→赋值)不报。
#
# 用法: perl check_async_state_guard.pl <file.ets> [file2.ets ...]
use strict;
use warnings;

my ($total_methods, $flagged) = (0, 0);

for my $f (@ARGV) {
  open(my $fh, '<', $f) or next;
  local $/;
  my $s = <$fh>;
  close($fh);

  # 1. 收集本文件 @State 字段名(@State [private] name[: Type])
  my %state_fields;
  while ($s =~ /\@State\s+(?:private\s+)?(\w+)/g) {
    $state_fields{$1} = 1;
  }
  next unless %state_fields;
  my $state_re = join('|', map { quotemeta } keys %state_fields);

  # 2. 遍历 async 方法,平衡括号(跳字符串)取方法体
  while ($s =~ /\basync\s+(\w+)\s*\(/g) {
    my $mname = $1;
    my $brace = index($s, '{', pos($s));
    next if $brace < 0;
    my ($depth, $i, $len, $q) = (0, $brace, length($s), '');
    for (; $i < $len; $i++) {
      my $c = substr($s, $i, 1);
      if ($q ne '') { $q = '' if $c eq $q; next; }
      if    ($c eq "'" or $c eq '"' or $c eq '`') { $q = $c; }
      elsif ($c eq '{') { $depth++; }
      elsif ($c eq '}') { $depth--; last if $depth == 0; }
    }
    my $body = substr($s, $brace, $i - $brace + 1);
    next unless $body =~ /\bawait\b/;   # 只关心含 await 的 async 方法
    $total_methods++;

    my $method_line = (substr($s, 0, $brace) =~ tr/\n//) + 1;

    # 3. 逐行状态机
    my ($seen_await, $guarded) = (0, 0);
    for my $ln (split /\n/, $body) {
      if ($ln =~ /\bawait\b/) { $seen_await = 1; $guarded = 0; }
      # 守卫: if(!this.pageActive) / isCurrent*Task / isCurrent*Refresh / !this.isActive
      #   / token 比较式(xToken === this.yToken 或回调 () => token === this.xToken)。
      # 注: token 守卫多防"并发"(后到请求覆盖先到), pageActive 守卫防"页面销毁"。
      #   二者语义不同——有 token 守卫不等于防销毁竞态, human-review 需分辨。
      if ($ln =~ /!\s*this\.pageActive|isCurrent\w*\s*\(|!\s*this\.isActive\b|\w*[Tt]oken\s*[!=]==\s*this\.|this\.\w*[Tt]oken\s*[!=]==/) {
        $guarded = 1;
      }
      # await 后未经守卫就写 @State 字段
      if ($seen_await && !$guarded && $ln =~ /\bthis\.($state_re)\s*=(?![=>])/) {
        $flagged++;
        print "NO_GUARD $f method=$mname (~L$method_line) field=$1\n";
        last;   # 一个方法只报一次
      }
    }
  }
}

print "=== async-with-await methods=$total_methods  NO_GUARD(candidates)=$flagged ===\n";
print "# NO_GUARD 是启发式候选,需 human-review:确认 await 后写 \@State 是否真有页面销毁竞态窗口\n";
