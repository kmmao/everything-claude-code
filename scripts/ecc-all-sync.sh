#!/usr/bin/env bash
# ecc-all-sync.sh — 统一同步脚本：Claude Code + Codex CLI
#
# 用法:
#   bash scripts/ecc-all-sync.sh              # 日常同步（两者都更新）
#   bash scripts/ecc-all-sync.sh --full       # 完全重装 Claude Code plugin + 重新同步 Codex
#   bash scripts/ecc-all-sync.sh --claude     # 只同步 Claude Code
#   bash scripts/ecc-all-sync.sh --codex      # 只同步 Codex CLI
#   bash scripts/ecc-all-sync.sh --dry-run    # 预览模式（不实际执行）
#
# 取代: ecc-sync.sh 和 ecc-reinstall.sh

set -euo pipefail

# ─── 参数解析 ─────────────────────────────────
MODE_CLAUDE=true
MODE_CODEX=true
FULL=false
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --claude)   MODE_CODEX=false ;;
    --codex)    MODE_CLAUDE=false ;;
    --full)     FULL=true ;;
    --dry-run)  DRY_RUN=true ;;
    -h|--help)
      sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
  esac
done

# ─── 辅助函数 ─────────────────────────────────
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TS=$(date +%Y%m%d-%H%M%S)

cyan()   { printf "\033[36m%s\033[0m\n" "$*"; }
green()  { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
red()    { printf "\033[31m%s\033[0m\n" "$*"; }

step() {
  echo
  cyan "━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

run() {
  if $DRY_RUN; then
    yellow "[dry-run] $*"
  else
    "$@"
  fi
}

MARKETPLACE_NAME="everything-claude-code"
MARKETPLACE_REPO="kmmao/everything-claude-code"
MARKETPLACE_DIR="$HOME/.claude/plugins/marketplaces/${MARKETPLACE_NAME}"
PLUGIN_COPY="$MARKETPLACE_DIR/.claude-plugin/plugin.json"
CONFIG="$HOME/ecc-install.json"

# ─── Phase 0: 前置检查 ──────────────────────────
step "Phase 0: 前置检查"

command -v node >/dev/null 2>&1 || { red "✗ 缺 node"; exit 1; }
command -v jq   >/dev/null 2>&1 || { red "✗ 缺 jq";   exit 1; }
[ -d "$REPO" ] || { red "✗ 仓库不存在: $REPO"; exit 1; }
green "✓ 基础依赖齐全"

HAS_CLAUDE=false
HAS_CODEX=false
command -v claude >/dev/null 2>&1 && HAS_CLAUDE=true || yellow "⚠️  claude CLI 未找到，将跳过 Claude Code 同步"
command -v codex  >/dev/null 2>&1 && HAS_CODEX=true  || yellow "⚠️  codex CLI 未找到，将跳过 Codex 同步"

$MODE_CLAUDE && ! $HAS_CLAUDE && { red "✗ 指定了 --claude 但 claude CLI 不可用"; exit 1; }
$MODE_CODEX  && ! $HAS_CODEX  && MODE_CODEX=false && yellow "⚠️  codex 不可用，已自动禁用 Codex 同步"

$DRY_RUN && yellow "🔍 dry-run 模式：只预览，不执行"

# ─── Phase 1: Git 同步 ──────────────────────────
step "Phase 1: Git 同步"

cd "$REPO"

# 锁文件经常有本地改动，merge 前先清理
if git diff --name-only | grep -qE '(package-lock\.json|yarn\.lock)$'; then
  yellow "==> 清理锁文件本地改动"
  run git checkout -- package-lock.json yarn.lock 2>/dev/null || true
fi

run git fetch upstream
run git merge upstream/main || {
  if git status --porcelain | grep -q "^UU .claude-plugin/plugin.json"; then
    yellow "   plugin.json 冲突 —— 以本地为准"
    run git checkout --ours .claude-plugin/plugin.json
    run git add .claude-plugin/plugin.json
    run git commit --no-edit
  else
    red "   有其他冲突，手动解决后重跑"; exit 1
  fi
}

run npm install --silent
green "✓ Git 同步完成"

# ─── Phase 2: Claude Code 同步 ───────────────────
if $MODE_CLAUDE && $HAS_CLAUDE; then
  step "Phase 2: Claude Code 同步$(${FULL} && echo ' (完全重装)' || echo '')"

  if $FULL; then
    yellow "==> 卸载旧 plugin"
    installed=$(claude plugin list 2>/dev/null | grep "@${MARKETPLACE_NAME}$" | awk '{print $2}')
    if [ -n "$installed" ]; then
      for pid in $installed; do
        run claude plugin uninstall "$pid" || red "⚠️  卸 $pid 失败但继续"
      done
    fi
    [ -d "$MARKETPLACE_DIR" ] && run rm -rf "$MARKETPLACE_DIR"

    yellow "==> 刷新 marketplace"
    current_repo=$(claude plugin marketplace list --json 2>/dev/null \
      | jq -r --arg n "$MARKETPLACE_NAME" '.[] | select(.name==$n) | .repo // ""')
    if [ -z "$current_repo" ]; then
      run claude plugin marketplace add "$MARKETPLACE_REPO"
    elif [ "$current_repo" != "$MARKETPLACE_REPO" ]; then
      run claude plugin marketplace remove "$MARKETPLACE_NAME"
      run claude plugin marketplace add "$MARKETPLACE_REPO"
    else
      run claude plugin marketplace update "$MARKETPLACE_NAME"
    fi

    yellow "==> 安装 plugin"
    plugin_name=$(jq -r '.plugins[0].name' "$MARKETPLACE_DIR/.claude-plugin/marketplace.json" 2>/dev/null || echo "ecc")
    run claude plugin install "${plugin_name}@${MARKETPLACE_NAME}"
    sleep 2
  fi

  yellow "==> install.sh"
  if [ -f "$CONFIG" ]; then
    run ./install.sh --config "$CONFIG"
  else
    run ./install.sh --profile full
  fi

  yellow "==> 清理 ~/.claude/rules/zh"
  run rm -rf ~/.claude/rules/zh

  # 同步 plugin.json 到所有 marketplace 副本
  for target in "$PLUGIN_COPY" $(find "$HOME/.claude/plugins/cache/everything-claude-code" -name "plugin.json" -path "*/.claude-plugin/*" 2>/dev/null); do
    if [ -f "$target" ] && ! diff -q .claude-plugin/plugin.json "$target" >/dev/null 2>&1; then
      yellow "==> 同步 plugin.json → $target"
      run cp .claude-plugin/plugin.json "$target"
    fi
  done

  green "✓ Claude Code 同步完成"
fi

# ─── Phase 3: Codex CLI 同步 ──────────────────────
if $MODE_CODEX && $HAS_CODEX; then
  step "Phase 3: Codex CLI 同步"

  yellow "==> install.sh --target codex --profile full"
  run ./install.sh --target codex --profile full

  yellow "==> sync-ecc-to-codex.sh"
  if $DRY_RUN; then
    run bash scripts/sync-ecc-to-codex.sh --dry-run
  else
    bash scripts/sync-ecc-to-codex.sh
  fi

  yellow "==> 设置 PATH 命令别名"
  BIN_DIR="${HOME}/.local/bin"
  run mkdir -p "$BIN_DIR"
  run ln -sf "$REPO/scripts/sync-ecc-to-codex.sh" "$BIN_DIR/ecc-sync-codex"
  run ln -sf "$REPO/scripts/codex/install-global-git-hooks.sh" "$BIN_DIR/ecc-install-git-hooks"
  run ln -sf "$REPO/scripts/codex/check-codex-global-state.sh" "$BIN_DIR/ecc-check-codex"

  yellow "==> 健康检查"
  run bash scripts/codex/check-codex-global-state.sh 2>/dev/null || yellow "⚠️  健康检查有警告（见上方输出）"

  green "✓ Codex CLI 同步完成"
fi

# ─── Phase 4: 最终验证 ──────────────────────────
step "Phase 4: 最终验证"

echo
if $HAS_CLAUDE && $MODE_CLAUDE; then
  echo "  Claude Code:"
  for d in rules agents hooks skills; do
    c=$(find "$HOME/.claude/$d" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
    printf "    ~/.claude/%-10s %s items\n" "$d/" "$c"
  done
  [ -f "$PLUGIN_COPY" ] && printf "    plugin: v%s, %s skills\n" \
    "$(jq -r '.version // "?"' "$PLUGIN_COPY")" \
    "$(jq -r '(.skills // []) | length' "$PLUGIN_COPY")"
fi

if $HAS_CODEX && $MODE_CODEX; then
  echo "  Codex CLI:"
  CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
  [ -f "$CODEX_HOME/AGENTS.md" ] && green "    ~/.codex/AGENTS.md ✓" || yellow "    ~/.codex/AGENTS.md 未找到"
  c=$(find "$CODEX_HOME/agents" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
  printf "    ~/.codex/agents/   %s items\n" "$c"
fi

echo
green "════════════════════════════════════════"
green " ✓ 同步完成"
green "════════════════════════════════════════"
$MODE_CLAUDE && $HAS_CLAUDE && {
  echo
  red "⚠️  需要重启 Claude Code（plugin 清单只在启动时加载）"
  yellow "   ⌘Q 退出 Claude Code → 重开"
}
