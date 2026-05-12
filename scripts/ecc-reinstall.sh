#!/usr/bin/env bash
# DEPRECATED: 请改用 scripts/ecc-all-sync.sh --full（同时支持 Claude Code + Codex CLI）
# ECC 完全重装脚本 — 从 fork 装（全自动，不用切 Claude Code 手动 /plugin）
#
# 用法（从仓库根目录）:
#   bash scripts/ecc-reinstall.sh
# 或绝对路径:
#   bash ~/Documents/GitHub/everything-claude-code/scripts/ecc-reinstall.sh
#
# 依赖: claude CLI 的 plugin 子命令（已验证）、jq、node
# 修改下面 MARKETPLACE_REPO 变量可切换到别的 fork

set -e

REPO="$HOME/Documents/GitHub/everything-claude-code"
MARKETPLACE_NAME="everything-claude-code"
MARKETPLACE_REPO="kmmao/everything-claude-code"    # ← 你的 fork
MARKETPLACE_DIR="$HOME/.claude/plugins/marketplaces/${MARKETPLACE_NAME}"
# PLUGIN_ID 在 Step 4 之后从 marketplace.json 动态读取（上游可能改过名）
PLUGIN_ID=""
SETTINGS="$HOME/.claude/settings.json"
TS=$(date +%Y%m%d-%H%M%S)

cyan()   { printf "\033[36m%s\033[0m\n" "$*"; }
green()  { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
red()    { printf "\033[31m%s\033[0m\n" "$*"; }

step() {
  echo
  cyan "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  cyan ">>> $*"
  cyan "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ─────────────────────────────────────────────
# Step 0 — 前置检查
# ─────────────────────────────────────────────
step "Step 0: 前置检查"

command -v claude >/dev/null 2>&1 || { red "✗ 缺 claude CLI"; exit 1; }
command -v jq >/dev/null 2>&1 || { red "✗ 缺 jq"; exit 1; }
command -v node >/dev/null 2>&1 || { red "✗ 缺 node"; exit 1; }
[ -d "$REPO" ] || { red "✗ 仓库不存在：$REPO"; exit 1; }
green "✓ 依赖齐全"

current=$(claude plugin list 2>/dev/null | grep "@${MARKETPLACE_NAME}$" | head -1 | awk '{print $2}')
yellow "当前已装：${current:-无}"

# ─────────────────────────────────────────────
# Step 1 — 备份
# ─────────────────────────────────────────────
step "Step 1: 备份关键配置"

[ -f "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.before-reinstall-$TS" && green "✓ settings.json → $SETTINGS.before-reinstall-$TS"
[ -f "$HOME/ecc-install.json" ] && cp "$HOME/ecc-install.json" "$HOME/ecc-install.json.before-reinstall-$TS" && green "✓ ecc-install.json 备份"

# ─────────────────────────────────────────────
# Step 2 — 清 install.sh 层
# ─────────────────────────────────────────────
step "Step 2: 清 install.sh 管理的文件"

cd "$REPO"
if [ -f "$HOME/.claude/ecc/install-state.json" ]; then
  node scripts/uninstall.js || red "⚠️  uninstall.js 报错但继续"
  rm -f "$HOME/.claude/ecc/install-state.json"
  rmdir "$HOME/.claude/ecc" 2>/dev/null || true
  green "✓ install.sh 层清干净"
else
  yellow "没 install-state.json，跳过"
fi

# ─────────────────────────────────────────────
# Step 3 — 卸 plugin（卸所有挂在此 marketplace 下的 plugin）
# ─────────────────────────────────────────────
step "Step 3: claude plugin uninstall"

installed=$(claude plugin list 2>/dev/null | grep "@${MARKETPLACE_NAME}$" | awk '{print $2}')
if [ -n "$installed" ]; then
  for pid in $installed; do
    yellow "卸 $pid"
    claude plugin uninstall "$pid" || red "⚠️  卸 $pid 失败但继续"
  done
  green "✓ plugin 已卸"
else
  yellow "没装此 marketplace 的 plugin，跳过"
fi

# 额外保险：手动删 marketplace 副本目录，确保下次 install 从零拉
if [ -d "$MARKETPLACE_DIR" ]; then
  rm -rf "$MARKETPLACE_DIR"
  green "✓ 清 marketplace 副本 ($MARKETPLACE_DIR)"
fi

# ─────────────────────────────────────────────
# Step 4 — 确保 marketplace 指向你的 fork，必要时重建
# ─────────────────────────────────────────────
step "Step 4: 校验并刷新 marketplace"

current_repo=$(claude plugin marketplace list --json 2>/dev/null \
  | jq -r --arg n "$MARKETPLACE_NAME" '.[] | select(.name==$n) | .repo // ""')

if [ -z "$current_repo" ]; then
  yellow "marketplace 不存在，新增 → $MARKETPLACE_REPO"
  claude plugin marketplace add "$MARKETPLACE_REPO"
  green "✓ marketplace 已添加"
elif [ "$current_repo" != "$MARKETPLACE_REPO" ]; then
  yellow "marketplace 当前指向 $current_repo，不是 $MARKETPLACE_REPO，重建"
  claude plugin marketplace remove "$MARKETPLACE_NAME"
  claude plugin marketplace add "$MARKETPLACE_REPO"
  green "✓ marketplace 已切换到 $MARKETPLACE_REPO"
else
  yellow "marketplace 已指向 $MARKETPLACE_REPO，只刷新"
  claude plugin marketplace update "$MARKETPLACE_NAME"
  green "✓ marketplace 已刷新"
fi

# ─────────────────────────────────────────────
# Step 5 — 从 marketplace.json 读出真实 plugin 名并安装
# ─────────────────────────────────────────────
step "Step 5: claude plugin install"

if [ ! -f "$MARKETPLACE_DIR/.claude-plugin/marketplace.json" ]; then
  red "✗ marketplace.json 不存在，Step 4 刷新失败？"
  exit 1
fi

# 读 marketplace.json 里声明的第一个 plugin 的 name
plugin_name=$(jq -r '.plugins[0].name' "$MARKETPLACE_DIR/.claude-plugin/marketplace.json")
if [ -z "$plugin_name" ] || [ "$plugin_name" = "null" ]; then
  red "✗ 从 marketplace.json 读不到 plugin 名"
  exit 1
fi

PLUGIN_ID="${plugin_name}@${MARKETPLACE_NAME}"
yellow "marketplace 声明 plugin name = $plugin_name"
yellow "安装 ID: $PLUGIN_ID"

claude plugin install "$PLUGIN_ID"
sleep 2

if [ ! -d "$MARKETPLACE_DIR" ]; then
  red "✗ plugin 副本没出来，安装失败"
  exit 1
fi

plugin_version=$(jq -r '.version // "unknown"' "$MARKETPLACE_DIR/.claude-plugin/plugin.json")
plugin_skills=$(jq -r '(.skills // []) | length' "$MARKETPLACE_DIR/.claude-plugin/plugin.json")
green "✓ plugin 装好 (v$plugin_version, skill 条目 $plugin_skills)"

# ─────────────────────────────────────────────
# Step 6 — 跑 install.sh --profile full
# ─────────────────────────────────────────────
step "Step 6: ./install.sh --profile full"

cd "$REPO"
npm install --silent
yellow "npm install 完成"

ops=$(./install.sh --profile full --dry-run --json 2>/dev/null | jq '.plan.operations | length')
yellow "将要执行 $ops 个文件操作"

./install.sh --profile full
green "✓ install.sh --profile full 完成"

# ─────────────────────────────────────────────
# Step 7 — 清 zh/ 重复
# ─────────────────────────────────────────────
if [ -d "$HOME/.claude/rules/zh" ]; then
  rm -rf "$HOME/.claude/rules/zh"
  green "✓ 清 ~/.claude/rules/zh（中文规则重复注入）"
fi

# ─────────────────────────────────────────────
# 最终验证
# ─────────────────────────────────────────────
step "最终验证"

node scripts/list-installed.js 2>/dev/null | head -8 || true
echo
for d in rules agents hooks scripts skills; do
  c=$(find "$HOME/.claude/$d" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
  printf "  ~/.claude/%-10s %s items\n" "$d/" "$c"
done

echo
claude plugin list 2>&1 | grep -A 3 "ecc@"

echo
green "════════════════════════════════════════"
green " ✓ 重装完成"
green "════════════════════════════════════════"
echo
red "⚠️  必须重启 Claude Code"
echo
echo "原因：Claude Code 没有 plugin reload CLI（我翻了 'claude plugin --help' 确认过），"
echo "     plugin 清单只在 CC 启动时加载。当前会话里的 skills/agents/commands 缓存"
echo "     还是旧的，要完全关掉 CC 窗口再重开才会真正 refresh。"
echo
yellow "执行方式：⌘Q 退出 Claude Code → 重开"
yellow "（打开后跑 \`claude plugin list\` 验证 ecc 版本对上）"
