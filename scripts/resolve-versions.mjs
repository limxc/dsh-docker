#!/usr/bin/env node
// 解析本次构建使用的 dsh 版本：显式参数 > npm latest > versions.json（兜底）。
// 输出 GitHub Actions 格式（>> $GITHUB_OUTPUT）：dsh=... tag=...
// tag = <dsh版本>（可复现构建；latest 为滚动 tag 由 workflow 单独打）
//
// 注：webui / auth-gate / dsh-market 不在此追踪——镜像构建期按 npm latest 预装，
// 日常升级由 dsh-market（Web 设置）管理。
import { readFileSync } from 'node:fs';

const DSH_PKG = 'https://registry.npmjs.org/@deepseek-ai%2Fdsh';

const pinned = JSON.parse(readFileSync('versions.json', 'utf8'));

async function npmLatest(url) {
  try {
    const res = await fetch(url, { headers: { accept: 'application/json' } });
    if (!res.ok) return undefined;
    const data = await res.json();
    return data['dist-tags']?.latest;
  } catch {
    return undefined;
  }
}

const explicitDsh = process.argv[2];

const dsh = explicitDsh || (await npmLatest(DSH_PKG)) || pinned.dsh;

const re = /^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$/;
if (!re.test(dsh)) {
  console.error(`非法版本格式: dsh=${dsh}`);
  process.exit(1);
}

console.log(`dsh=${dsh}`);
console.log(`tag=${dsh}`);
