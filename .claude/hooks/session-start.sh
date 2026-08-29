#!/bin/bash
# ai_memory（私用コンテキスト）をセッション開始時に取得する SessionStart フック。
#
# 作業対象のリポジトリの .claude/hooks/session-start.sh として配置し、
# .claude/settings.json の SessionStart に登録して使う。
# 導入手順は ai_memory の README.md を参照。
#
# 失敗してもセッションは止めない。常に exit 0 で終わり、
# 何が起きたかを標準出力でエージェントに伝える。

set -uo pipefail

REPO_URL="https://github.com/yossyossy/ai_memory"
# 取得先はプロジェクトの隣。add_repo がリポジトリを置く場所と同じ規約なので、
# 後から add_repo でアタッチしても clone が二重にならない。
if [ -n "${AI_MEMORY_DIR:-}" ]; then
  DEST="${AI_MEMORY_DIR}"
elif [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  DEST="$(dirname "${CLAUDE_PROJECT_DIR}")/ai_memory"
else
  DEST="${HOME}/ai_memory"
fi
BRANCH="main"

# Claude Code on the web でのみ動かす。手元では各自の clone を使う。
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# 作業対象が ai_memory 自身なら取得不要。
if git -C "${CLAUDE_PROJECT_DIR:-.}" remote get-url origin 2>/dev/null \
   | grep -qiE '/ai_memory(\.git)?/?$'; then
  exit 0
fi

log="$(mktemp)"
trap 'rm -f "${log}"' EXIT

if [ -d "${DEST}/.git" ]; then
  # 既存の clone に手元の変更や作業ブランチがあれば壊さない。更新は諦める。
  dirty="$(git -C "${DEST}" status --porcelain 2>/dev/null)"
  current="$(git -C "${DEST}" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  if [ -n "${dirty}" ] || [ "${current}" != "${BRANCH}" ]; then
    status="local"
  elif git -C "${DEST}" fetch --depth 1 origin "${BRANCH}" >"${log}" 2>&1 \
     && git -C "${DEST}" reset --hard "origin/${BRANCH}" >>"${log}" 2>&1; then
    status="updated"
  else
    status="stale"
  fi
else
  if git clone --depth 1 --branch "${BRANCH}" "${REPO_URL}" "${DEST}" >"${log}" 2>&1; then
    status="cloned"
  else
    status="failed"
    # 半端な clone だけを片付ける。中身のあるディレクトリには触らない。
    case "${DEST}" in
      */ai_memory)
        if [ -d "${DEST}" ] && [ -z "$(ls -A "${DEST}" 2>/dev/null | grep -v '^\.git$')" ]; then
          rm -rf "${DEST}"
        fi
        ;;
    esac
  fi
fi

# resume / clear / compact でも発火するため、重複追記を避ける。
if [ "${status}" != "failed" ] && [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  if ! grep -qF "AI_MEMORY_DIR=\"${DEST}\"" "${CLAUDE_ENV_FILE}" 2>/dev/null; then
    echo "export AI_MEMORY_DIR=\"${DEST}\"" >> "${CLAUDE_ENV_FILE}"
  fi
fi

if [ "${status}" = "failed" ]; then
  cat <<EOF
私用コンテキストリポジトリ ai_memory を取得できませんでした。

ai_memory は private です。クラウドセッションの git プロキシは、セッションに
紐づいたリポジトリしか通しません。add_repo ツールで yossyossy/ai_memory を
このセッションに追加し、${DEST} に clone してから、上のファイルを読んでください。
add_repo はセッション開始時のスコープに縛られないため、そのまま実行できます。
追加できない場合は、私用コンテキストなしで作業していることをユーザーに伝えてください。

git の出力（末尾）: $(tail -n 2 "${log}" | tr '\n' ' ')
EOF
  exit 0
fi

cat <<EOF
私用コンテキストリポジトリ ai_memory を ${DEST} に取得しました（${status}）。
このユーザーの私用環境・制約・失敗記録がここにあります。作業前に読んでください。

常に読む:
- ${DEST}/AGENTS.md — 索引と常時必要な前提
- ${DEST}/notes/constraints.md — 採用しない技術・訂正されがちな前提

必要なときだけ読む:
- ${DEST}/notes/environment.md — ホームラボと私用端末の構成（環境に触れるとき）
- ${DEST}/notes/lessons.md — ハマった記録（作業前に該当箇所を）
- ${DEST}/notes/domains/ — 技術領域ごとの詳細（該当領域のときだけ）

重要: ai_memory は私用のリポジトリです。業務由来の情報を書き込まないでください。
また ai_memory の内容を今作業中のリポジトリにコピーしないでください。逆も同じです。
EOF

case "${status}" in
  stale)
    echo
    echo "注意: 更新の取得に失敗したため、上記は前回取得時点の内容です。"
    ;;
  local)
    echo
    echo "注意: 既存の clone に手元の変更または main 以外のブランチがあるため、"
    echo "更新していません。上記は現在のチェックアウトの内容です。"
    ;;
esac

exit 0
