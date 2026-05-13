#!/usr/bin/env bash
# ecc-all-sync.sh — 统一同步脚本：Claude Code + Codex CLI
#
# 全部由 install.sh 管理（不依赖 plugin），包括 rules、skills、agents、hooks、commands。
#
# 用法:
#   bash scripts/ecc-all-sync.sh              # 日常同步（两者都更新）
#   bash scripts/ecc-all-sync.sh --full       # 完全重装（清除旧目录后重装）
#   bash scripts/ecc-all-sync.sh --claude     # 只同步 Claude Code
#   bash scripts/ecc-all-sync.sh --codex      # 只同步 Codex CLI
#   bash scripts/ecc-all-sync.sh --dry-run    # 预览模式（不实际执行）
#
# 配置: ~/ecc-install.json（控制安装哪些模块）

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
      sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
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

# 配置文件优先级：仓库内 > 用户目录
if [ -f "$REPO/ecc-install.json" ]; then
  CONFIG="$REPO/ecc-install.json"
elif [ -f "$HOME/ecc-install.json" ]; then
  CONFIG="$HOME/ecc-install.json"
else
  CONFIG=""
fi

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

# ─── Phase 2: Claude Code 同步（全由 install.sh 管理）───
if $MODE_CLAUDE && $HAS_CLAUDE; then
  step "Phase 2: Claude Code 同步$(${FULL} && echo ' (完全重装)' || echo '')"

  if $FULL; then
    yellow "==> 清理旧安装目录（确保无残留）"
    for d in "$HOME/.claude/rules/ecc" "$HOME/.claude/skills/ecc" "$HOME/.claude/agents" "$HOME/.claude/hooks"; do
      [ -d "$d" ] && run rm -rf "$d" && yellow "   清除 $d"
    done
    [ -f "$HOME/.claude/ecc/install-state.json" ] && run rm -f "$HOME/.claude/ecc/install-state.json"
  fi

  # 主安装：install.sh 装 rules + skills + agents + hooks + commands
  yellow "==> install.sh"
  if [ -f "$CONFIG" ]; then
    yellow "    配置: $CONFIG"
    run ./install.sh --config "$CONFIG"
  else
    yellow "    无配置文件，使用 --profile full"
    run ./install.sh --profile full
  fi

  # 补装 manifest 遗漏的 skills（仓库 skills/ 有但 module 未收录的）
  yellow "==> 补装 manifest 未收录的 skills"
  INSTALLED_SKILLS_DIR="$HOME/.claude/skills/ecc"
  REPO_SKILLS_DIR="$REPO/skills"
  extra_count=0
  if [ -d "$REPO_SKILLS_DIR" ] && [ -d "$INSTALLED_SKILLS_DIR" ]; then
    for skill_dir in "$REPO_SKILLS_DIR"/*/; do
      skill_name=$(basename "$skill_dir")
      if [ ! -d "$INSTALLED_SKILLS_DIR/$skill_name" ] && [ -f "$skill_dir/SKILL.md" ]; then
        run cp -r "$skill_dir" "$INSTALLED_SKILLS_DIR/$skill_name"
        extra_count=$((extra_count + 1))
      fi
    done
    [ $extra_count -gt 0 ] && yellow "   补装了 $extra_count 个遗漏 skill" || yellow "   无遗漏（全部已安装）"
  fi

  # 清理旧遗留 + 精简 rules
  yellow "==> 清理旧遗留"
  # rules: 顶层语言目录与 ecc/ 重复
  for d in common typescript web python golang swift kotlin java rust perl php cpp csharp dart angular arkts fsharp; do
    [ -d "$HOME/.claude/rules/$d" ] && [ -d "$HOME/.claude/rules/ecc/$d" ] && run rm -rf "$HOME/.claude/rules/$d" && yellow "   清除重复 rules/$d"
  done
  run rm -rf "$HOME/.claude/rules/zh" "$HOME/.claude/rules/ecc/zh"

  # rules: prune language dirs not in keep_rules (saves always-on tokens)
  if [ -n "${CONFIG:-}" ] && [ -f "$CONFIG" ]; then
    KEEP_RULES=$(jq -r '.options.keep_rules // [] | .[]' "$CONFIG" 2>/dev/null || true)
    if [ -n "$KEEP_RULES" ]; then
      yellow "==> prune rules (keep: $(echo $KEEP_RULES | tr '\n' ' '))"
      for d in "$HOME/.claude/rules/ecc"/*/; do
        rname=$(basename "$d")
        if ! echo "$KEEP_RULES" | grep -qx "$rname"; then
          run rm -rf "$d" && yellow "   rm rules/ecc/$rname"
        fi
      done
    fi
    # delete specific rule files
    EXCLUDE_RULES_FILES=$(jq -r '.options.exclude_rules_files // [] | .[]' "$CONFIG" 2>/dev/null || true)
    if [ -n "$EXCLUDE_RULES_FILES" ]; then
      echo "$EXCLUDE_RULES_FILES" | while read -r rf; do
        target="$HOME/.claude/rules/ecc/$rf"
        [ -f "$target" ] && run rm -f "$target" && yellow "   rm rules/ecc/$rf"
      done
    fi
  fi
  # skills: 顶层 skill 与 ecc/ 重复
  for d in "$HOME/.claude/skills"/*/; do
    name=$(basename "$d")
    [ "$name" = "ecc" ] || [ "$name" = "learned" ] && continue
    if [ -d "$HOME/.claude/skills/ecc/$name" ]; then
      run rm -rf "$d" && yellow "   清除重复 skills/$name"
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

  yellow "==> 清理 Codex 冗余"
  CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
  # ~/.codex/skills/ 与 ~/.agents/skills/ 重复
  if [ -d "$CODEX_HOME/skills" ] && [ -d "${AGENTS_HOME:-$HOME/.agents}/skills" ]; then
    run rm -rf "$CODEX_HOME/skills"
    yellow "   清除 ~/.codex/skills/（Codex 用 ~/.agents/skills/）"
  fi
  # 清理备份残留
  for f in "$CODEX_HOME"/config.toml.bak-* "$CODEX_HOME"/config_副本.toml "$CODEX_HOME"/auth_副本.json "$CODEX_HOME"/.codex-global-state.json.bak; do
    [ -f "$f" ] && run rm -f "$f" && yellow "   清除 $(basename "$f")"
  done

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
  echo "  Claude Code（install.sh 管理）:"
  for d in rules skills agents hooks; do
    c=$(find "$HOME/.claude/$d" -maxdepth 2 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    printf "    ~/.claude/%-10s %s items\n" "$d/" "$c"
  done
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
green " ✓ 同步完成（全部由 install.sh 管理，无 plugin 依赖）"
green "════════════════════════════════════════"
$MODE_CLAUDE && $HAS_CLAUDE && {
  echo
  red "⚠️  需要重启 Claude Code（⌘Q → 重开）"
}
