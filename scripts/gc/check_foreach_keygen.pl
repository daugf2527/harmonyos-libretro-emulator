#!/usr/bin/perl
# Pattern 3 精确版:对每个 ForEach( 做平衡括号解析,跳过字符串字面量,
# 统计顶层逗号数。ArkUI ForEach(arr, itemBuilder, keyGen) 应有 2 个顶层逗号;
# < 2 = 缺 keyGenerator。\bForEach 自动排除 LazyForEach。
# 用法: perl check_foreach_keygen.pl <file.ets> [file2.ets ...]
use strict; use warnings;
my ($total, $nokey) = (0, 0);
for my $f (@ARGV) {
  open(my $fh, '<', $f) or next;
  local $/; my $s = <$fh>; close($fh);
  my $len = length($s);
  while ($s =~ /\bForEach\s*\(/g) {
    my $mstart = $-[0];
    my $p = index($s, '(', $mstart);
    my ($depth, $commas, $i) = (0, 0, $p);
    my $q = '';                       # 当前所在字符串引号,'' = 不在字符串
    for (; $i < $len; $i++) {
      my $c = substr($s, $i, 1);
      if ($q ne '') { $q = '' if $c eq $q; next; }
      if    ($c eq "'" or $c eq '"' or $c eq '`') { $q = $c; }
      elsif ($c eq '(') { $depth++; }
      elsif ($c eq ')') { $depth--; last if $depth == 0; }
      elsif ($c eq ',' && $depth == 1) { $commas++; }
    }
    my $line = (substr($s, 0, $mstart) =~ tr/\n//) + 1;
    $total++;
    if ($commas < 2) { $nokey++; print "NO_KEY $f:$line (topcommas=$commas)\n"; }
  }
}
print "=== total ForEach=$total  NO_KEY=$nokey ===\n";
