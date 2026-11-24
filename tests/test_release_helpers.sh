#!/usr/bin/env bash
# bash-utils 1.3.0 新增的 release helpers 測試（不連網）
# 用法: bash tests/test_release_helpers.sh

UTILS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/utils.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 讓 utils.sh 以暫存目錄為 CWD，避免啟用任何真實的 .venv
export CWD="$WORK"
# shellcheck source=/dev/null
source "$UTILS"
set +e

PASS=0
FAIL=0
check() {
	if [ "$2" = "$3" ]; then
		PASS=$((PASS + 1))
		echo "  [PASS] $1"
	else
		FAIL=$((FAIL + 1))
		echo "  [FAIL] $1（預期 '$3'，實際 '$2'）"
	fi
}

echo "=== u_get_project_version ==="
printf '[project]\nname = "x"\nversion = "1.2.3"\n[tool.x]\nversion = "9.9.9"\n' >"$WORK/pyproject.toml"
ver=""
u_get_project_version "$WORK/pyproject.toml" ver
check "讀取第一個 version" "$ver" "1.2.3"
printf '[project]\nname = "x"\n' >"$WORK/noversion.toml"
u_get_project_version "$WORK/noversion.toml" ver 2>/dev/null
check "沒有 version 時回傳 1" "$?" "1"

echo "=== u_confirm_overwrite ==="
u_confirm_overwrite 0 "$WORK/nope1" "$WORK/nope2"
check "都不存在時直接通過" "$?" "0"
touch "$WORK/exists"
u_confirm_overwrite 1 "$WORK/exists"
check "is_yes=1 不詢問直接通過" "$?" "0"
echo n | u_confirm_overwrite 0 "$WORK/exists" >/dev/null 2>&1
check "回答 n 時拒絕" "$?" "1"
echo y | u_confirm_overwrite 0 "$WORK/exists" >/dev/null 2>&1
check "回答 y 時通過" "$?" "0"
check "不會刪除檔案" "$([ -e "$WORK/exists" ] && echo yes)" "yes"

echo "=== u_offline_run ==="
mode=""
out=$(u_offline_run mode bash -c 'echo "UV_OFFLINE=$UV_OFFLINE"')
check "命令內 UV_OFFLINE=1" "$out" "UV_OFFLINE=1"
u_offline_run mode true
check "mode 有值" "$([ -n "$mode" ] && echo set)" "set"
echo "  （本機驗證方式：$mode）"
u_offline_run mode bash -c 'exit 7'
check "回傳命令的結束碼" "$?" "7"
if [ "$mode" = "offline-namespace" ]; then
	out=$(u_offline_run mode bash -c 'ip -o link 2>/dev/null | grep -vc " lo:" || true')
	check "namespace 內只有 loopback" "$out" "0"
fi

echo "=== u_fix_python_links ==="
py="$WORK/py"
mkdir -p "$py/cpython-3.13.12-linux-x86_64-gnu/bin" "$py/.temp"
touch "$py/.lock" "$py/cpython-3.13.12-linux-x86_64-gnu/bin/python3.13"
ln -s python3.13 "$py/cpython-3.13.12-linux-x86_64-gnu/bin/python3"
ln -s "$py/cpython-3.13.12-linux-x86_64-gnu" "$py/cpython-3.13-linux-x86_64-gnu"
ln -s "$py/cpython-3.13.12-linux-x86_64-gnu/bin/python3.13" "$py/python3.13"
u_fix_python_links "$py"
check "頂層絕對連結被移除" "$(find "$py" -maxdepth 1 -type l | wc -l)" "0"
check ".temp/.lock 被移除" "$(ls -A "$py" | tr '\n' ' ')" "cpython-3.13.12-linux-x86_64-gnu "
check "安裝目錄內的相對連結保留" "$(readlink "$py/cpython-3.13.12-linux-x86_64-gnu/bin/python3")" "python3.13"
u_fix_python_links "$WORK/does-not-exist"
check "目錄不存在時不報錯" "$?" "0"

echo ""
echo "結果: $PASS 通過, $FAIL 失敗"
[ "$FAIL" -eq 0 ]
