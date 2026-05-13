---
name: ecc-project-config
description: Auto-detect the current project's tech stack and generate a precise .claude/ecc-install.json config file for selective ECC installation. Reads project files, maps to ECC modules/components, confirms with user, writes config, and optionally runs install.
origin: ECC
---

# ECC Project Config

Automatically analyzes the current project, generates a project-scoped `ecc-install.json`, and optionally installs only what this project needs.

## When to Activate

- User says "configure ECC for this project", "init ECC config", "ecc-project-config", or similar
- User opens a new project and wants a tailored ECC install
- User invokes `/ecc-project-config`

## Constants

```
ECC_REPO="$HOME/Documents/GitHub/everything-claude-code"
STACK_MAP="$ECC_REPO/config/project-stack-mappings.json"
CONFIG_OUT=".claude/ecc-install.json"
GLOBAL_CONFIG="$HOME/ecc-install.json"
```

---

## Step 0: Verify ECC Repo

Check that the local ECC fork exists:

```bash
ls "$HOME/Documents/GitHub/everything-claude-code/config/project-stack-mappings.json"
```

If missing, tell the user: "ECC repo not found at ~/Documents/GitHub/everything-claude-code. Run `git clone https://github.com/kmmao/everything-claude-code` first."

---

## Step 1: Detect Project Tech Stack

Scan the project root for indicator files. Match against these detection rules (in priority order):

### Framework Detection (check first — more specific)

| Stack | Indicator Files |
|-------|----------------|
| Next.js | `next.config.js`, `next.config.ts`, `next.config.mjs` |
| React | `package.json` contains `"react":` |
| Django | `manage.py` + `settings.py` OR `django` in `requirements.txt`/`pyproject.toml` |
| Spring Boot | `pom.xml` contains `spring-boot` OR `build.gradle` contains `spring-boot` |
| Quarkus | `pom.xml` contains `quarkus` OR `build.gradle` contains `quarkus` |
| Laravel | `artisan` file exists OR `composer.json` contains `laravel/framework` |
| Android | `AndroidManifest.xml` exists |
| Dart/Flutter | `pubspec.yaml` exists |

### Language Detection (fallback)

| Stack | Indicator Files |
|-------|----------------|
| TypeScript | `tsconfig.json` OR `package.json` contains `"typescript"` |
| JavaScript | `package.json` exists |
| Go | `go.mod` exists |
| Python | `pyproject.toml` OR `requirements.txt` OR `setup.py` OR `*.py` files |
| Rust | `Cargo.toml` exists |
| Java/Kotlin | `pom.xml` OR `build.gradle` OR `build.gradle.kts` |
| Swift | `Package.swift` OR `*.xcodeproj` directory |
| PHP | `composer.json` exists |
| C/C++ | `CMakeLists.txt` OR `Makefile` + `*.cpp`/`*.c` files |
| C# | `*.csproj` OR `*.sln` exists |
| Perl | `*.pl` OR `Makefile.PL` |

### Infrastructure Detection

| Stack | Indicator Files |
|-------|----------------|
| Docker | `Dockerfile` OR `docker-compose.yml` |

Run these checks with Bash, collecting matched stacks into a list.

---

## Step 2: Map Tech Stack to ECC Config

Based on detected stacks, build the recommended config:

### Profile Selection

| Detected stacks | Recommended profile |
|----------------|---------------------|
| 1-2 stacks, simple | `developer` |
| 3+ stacks OR Docker OR complex frameworks | `full` |
| Only Docker/infra | `core` |

### Include Components (add to profile)

| Detected | Include |
|----------|---------|
| Swift/iOS | `lang:swift` |
| Docker / DevOps | `capability:devops` |
| Security-sensitive project (auth files, payments) | `capability:security` |
| ML files (`*.ipynb`, `train.py`, torch/tensorflow in deps) | `capability:machine-learning` |
| Database files (schema, migrations) | `capability:database` |

### Exclude Components (remove from full profile)

Default exclusions for all projects (never useful):
- `capability:supply-chain`

Additional exclusions based on what was NOT detected:

| Not detected | Exclude |
|--------------|---------|
| No ML files | `capability:machine-learning` |
| No social/publishing intent | `capability:social` |
| No media generation need | `capability:media` |
| No document processing | `capability:documents` |
| No business/content writing | `capability:content` (only if purely technical project) |

---

## Step 3: Confirm with User

Show the detection results:

```
## 检测结果

**项目技术栈**
- ✅ TypeScript (tsconfig.json)
- ✅ React (package.json contains "react")
- ✅ Docker (Dockerfile)

**推荐配置**
- Profile: `full`
- Include: `capability:devops`
- Exclude: `capability:supply-chain`, `capability:machine-learning`,
           `capability:social`, `capability:media`, `capability:documents`

**预计文件操作数**: [run dry-run to get this number]
```

Get the operation count by running:
```bash
cd "$HOME/Documents/GitHub/everything-claude-code" && \
  ./install.sh --profile <profile> --dry-run --json 2>/dev/null | jq '.plan.operations | length'
```

Then use `AskUserQuestion`:

```
Question: "是否需要调整配置？"
Options:
  - "确认并生成配置文件" — "写入 .claude/ecc-install.json，不立即安装"
  - "立即确认并安装" — "写入配置并执行 install.sh"
  - "需要调整" — "手动修改 profile 或 include/exclude"
```

If user chooses "需要调整", ask two follow-up questions:

```
Question: "选择 Profile"
Options:
  - "developer (推荐)" — "规则、agents、命令、hooks、语言框架、数据库、编排（9 模块）"
  - "full" — "全部 21 个模块"
  - "core" — "最小基础，仅核心命令和 hooks（6 模块）"
  - "minimal" — "最轻量，无 hooks（5 模块）"
```

```
Question: "需要额外添加哪些能力？" (multiSelect: true)
Options:
  - "capability:security — 安全审查"
  - "capability:machine-learning — ML 工程"
  - "capability:devops — Docker/部署"
  - "capability:research — 深度调研"
  - "lang:swift — Swift/iOS"
  - "不需要额外添加"
```

---

## Step 4: Write Config File

Create `.claude/` directory if needed:

```bash
mkdir -p .claude
```

Write `.claude/ecc-install.json`:

```json
{
  "version": 1,
  "target": "claude",
  "profile": "<selected-profile>",
  "include": [<confirmed-includes>],
  "exclude": [<confirmed-excludes>]
}
```

Only include `"include"` key if the list is non-empty.
Always include `"exclude"` with at least `"capability:supply-chain"`.

**If a `.claude/ecc-install.json` already exists**, read it first and show the diff:
```
现有配置: profile=full, exclude=[supply-chain]
新建配置: profile=developer, exclude=[supply-chain, machine-learning, social, media]
```
Ask: "覆盖现有配置？" Options: "覆盖" / "取消"

---

## Step 5: (If Requested) Execute Install

If the user chose "立即确认并安装":

```bash
cd "$HOME/Documents/GitHub/everything-claude-code"
./install.sh --config "$(pwd)/.claude/ecc-install.json"
```

Then run the dedup cleanup (same as ecc-all-sync.sh):
```bash
# Remove duplicate rules at top level
for d in common typescript web python golang swift kotlin java rust perl php cpp csharp dart angular arkts fsharp; do
  [ -d "$HOME/.claude/rules/$d" ] && [ -d "$HOME/.claude/rules/ecc/$d" ] && rm -rf "$HOME/.claude/rules/$d"
done
rm -rf "$HOME/.claude/rules/zh" "$HOME/.claude/rules/ecc/zh"
# Remove duplicate agents
[ -d "$HOME/.claude/plugins/marketplaces/everything-claude-code/agents" ] && rm -rf "$HOME/.claude/agents"
```

---

## Step 6: Summary

Print a summary:

```
## ✅ ECC 项目配置完成

**配置文件**: .claude/ecc-install.json
**Profile**: developer
**Include**: capability:devops
**Exclude**: capability:supply-chain, capability:machine-learning,
             capability:social, capability:media

**下次同步**:
运行 `bash ~/Documents/GitHub/everything-claude-code/scripts/ecc-all-sync.sh`
脚本会自动读取 .claude/ecc-install.json（项目级配置优先于全局配置）
```

If install was also executed, show the installed counts:
```
**已安装**: XX rules, XX agents, XX hooks, XX skills
```
