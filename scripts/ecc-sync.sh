#!/usr/bin/env bash
# DEPRECATED: 请改用 scripts/ecc-all-sync.sh（同时支持 Claude Code + Codex CLI）
# ECC 日常同步脚本 — 拉上游 → install.sh → 清 zh/ 重复
#
# 用法（从仓库根目录）:
#   bash scripts/ecc-sync.sh
# 或绝对路径:
#   bash ~/Documents/GitHub/everything-claude-code/scripts/ecc-sync.sh
#
# 和 ecc-reinstall.sh 的区别:
#   - sync: 日常轻量更新，不动 plugin
#   - reinstall: 彻底卸了重装（从 fork 克隆新副本）

set -e

REPO="$HOME/Documents/GitHub/everything-claude-code"
PLUGIN_COPY="$HOME/.claude/plugins/marketplaces/everything-claude-code/.claude-plugin/plugin.json"
CONFIG="$HOME/ecc-install.json"

cd "$REPO"

# 锁文件经常有本地改动，merge 前先清理避免阻塞
if git diff --name-only | grep -qE '(package-lock\.json|yarn\.lock)$'; then
  echo "==> 清理锁文件本地改动（不影响合并结果）"
  git checkout -- package-lock.json yarn.lock 2>/dev/null || true
fi

echo "==> git fetch upstream"
git fetch upstream

echo "==> git merge upstream/main"
git merge upstream/main || {
  if git status --porcelain | grep -q "^UU .claude-plugin/plugin.json"; then
    echo "   plugin.json 冲突 —— 以本地为准（若有裁剪）"
    git checkout --ours .claude-plugin/plugin.json
    git add .claude-plugin/plugin.json
    git commit --no-edit
  else
    echo "   有其他冲突，手动解决后重跑"; exit 1
  fi
}

echo "==> npm install"
npm install --silent

echo "==> install.sh"
if [ -f "$CONFIG" ]; then
  echo "   用 $CONFIG"
  ./install.sh --config "$CONFIG"
else
  echo "   没找到 $CONFIG，用 --profile full"
  ./install.sh --profile full
fi

echo "==> 清理 ~/.claude/rules/zh（中文规则重复注入）"
rm -rf ~/.claude/rules/zh

# 如果本地 plugin.json 被裁剪过，同步到所有激活副本（marketplace + cache）
for target in "$PLUGIN_COPY" $(find "$HOME/.claude/plugins/cache/everything-claude-code" -name "plugin.json" -path "*/.claude-plugin/*" 2>/dev/null); do
  if [ -f "$target" ] && ! diff -q .claude-plugin/plugin.json "$target" >/dev/null 2>&1; then
    echo "==> 同步 plugin.json → $target"
    cp .claude-plugin/plugin.json "$target"
  fi
done

echo
echo "==> 完成"
if [ -f "$PLUGIN_COPY" ]; then
  echo "   激活 plugin: $(jq -r '.skills|length' "$PLUGIN_COPY") skills, $(jq -r '.agents|length' "$PLUGIN_COPY") agents, $(jq -r '.commands|length' "$PLUGIN_COPY") commands"
fi
echo "   💡 重启 Claude Code 让 plugin 清单 refresh"
