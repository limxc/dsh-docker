#!/usr/bin/env node
// 检查 @deepseek-ai/dsh 的 npm latest 版本，与 versions.json 对比。
// 输出 GitHub Actions 格式（>> $GITHUB_OUTPUT）：
//   changed=true|false
//   dsh=<当前> new_dsh=<最新>
import { readFileSync } from 'node:fs';

const DSH_PKG = 'https://registry.npmjs.org/@deepseek-ai%2Fdsh';

async function npmLatest(url) {
  const res = await fetch(url, { headers: { accept: 'application/json' } });
  if (!res.ok) throw new Error(`npm registry ${url} -> HTTP ${res.status}`);
  const data = await res.json();
  return data['dist-tags'].latest;
}

const pinned = JSON.parse(readFileSync('versions.json', 'utf8'));
const newDsh = await npmLatest(DSH_PKG);

const changed = newDsh !== pinned.dsh;
console.log(`changed=${changed}`);
console.log(`dsh=${pinned.dsh}`);
console.log(`new_dsh=${newDsh}`);
console.error(`[check-updates] dsh ${pinned.dsh} -> ${newDsh} | changed=${changed}`);
