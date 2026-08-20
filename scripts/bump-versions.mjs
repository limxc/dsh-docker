#!/usr/bin/env node
// 更新 versions.json 的 dsh 版本（CI 升级成功后回写，版本单一事实来源）。
// compose 直接拉取 Docker Hub 镜像，不参与版本回写。
// 用法: node scripts/bump-versions.mjs <dsh版本>
import { writeFileSync } from 'node:fs';

const [dsh] = process.argv.slice(2);
if (!dsh) {
  console.error('usage: bump-versions.mjs <dsh-version>');
  process.exit(1);
}

writeFileSync('versions.json', JSON.stringify({ dsh }, null, 2) + '\n');

console.log(`bumped: dsh=${dsh}`);
