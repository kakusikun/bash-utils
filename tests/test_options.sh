#!/usr/bin/env bash
# bash-utils 1.4.0 參數摘要（u_print_options）與中文訊息的測試
# 用法: bash tests/test_options.sh

UTILS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/utils.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

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
contains() {
	if [[ "$2" == *"$3"* ]]; then
		PASS=$((PASS + 1))
		echo "  [PASS] $1"
	else
		FAIL=$((FAIL + 1))
		echo "  [FAIL] $1（找不到 '$3'）"
		echo "$2"
	fi
}

echo "=== u_get_option 取值不變 ==="
u_parse_arguments cmd -n ../maps/Y06 --vis
v=""
u_get_option -n --node "" "地圖節點目錄" v
check "短選項取值" "$v" "../maps/Y06"
u_get_option -c --config "configs/a.yml" "設定檔" v 2>/dev/null
check "預設值" "$v" "configs/a.yml"
u_get_option -o --output "x" "輸出目錄" v
check "選填未給時為空" "$v" ""
f=0
u_has_flag --vis f "顯示視窗"
check "flag 有給" "$f" "1"
u_has_flag --bg f "背景模式"
check "flag 沒給" "$f" "0"
u_has_flag --help f
check "不傳說明的 flag 照常運作" "$f" "0"
a=""
u_get_argument 0 "" "命令" a
check "位置引數" "$a" "cmd"

echo "=== u_print_options ==="
out=$(u_print_options)
contains "標題" "$out" "參數:"
contains "指定的選項" "$out" "-n, --node"
contains "指定的值與來源" "$out" "../maps/Y06"
contains "說明" "$out" "地圖節點目錄"
contains "預設來源" "$out" "[預設]"
contains "選填未給" "$out" "[未指定]"
contains "空值顯示" "$out" "（空）"
contains "flag 是" "$out" "是"
contains "引數標籤" "$out" "第 1 個引數"
check "未傳說明的 flag 不列入" "$(grep -c -- '--help' <<<"$out")" "0"
check "列數（6 項 + 標題 + 空行）" "$(u_print_options | wc -l)" "8"

u_get_option -n --node "" "地圖節點目錄（重複）" v
check "重複記錄不新增列" "$(u_print_options | wc -l)" "8"

u_parse_arguments other
check "重新解析時清空紀錄" "$(u_print_options | wc -l)" "0"

u_parse_arguments cmd -n Y06
u_get_argument 0 "" "命令" a
u_reset_options
u_get_option -n --node "" "地圖節點目錄" v
check "u_reset_options 後只剩之後的紀錄" "$(u_print_options | grep -c '第 1 個引數')" "0"
check "u_reset_options 後的新紀錄" "$(u_print_options | grep -c -- '-n, --node')" "1"

echo "=== 中文錯誤訊息 ==="
err=$( (u_parse_arguments -x 1 && u_get_option -n --node "" "地圖節點目錄" v) 2>&1)
check "缺必填選項時結束碼 1" "$?" "1"
contains "缺必填選項訊息" "$err" "缺少必填選項 -n, --node：地圖節點目錄"
err=$( (u_parse_arguments && u_get_argument 0 "" "命令" v) 2>&1)
contains "缺引數訊息" "$err" "缺少第 1 個引數：命令"
err=$(u_parse_arguments -n 1 pos 2>&1)
contains "引數順序錯誤訊息" "$err" "必須放在所有選項與旗標之前"
u_parse_arguments
err=$(u_get_option -c --config "a.yml" "設定檔" v 2>&1 >/dev/null)
contains "預設值訊息" "$err" "選項 -c, --config 未指定，使用預設值：a.yml"

echo "=== u_check_cmd ==="
u_parse_arguments -n Y06
u_get_option -n --node "" "地圖節點目錄" v
out=$(u_check_cmd "*.node.root=Y06" </dev/null)
contains "先印參數摘要" "$out" "-n, --node"
contains "再印將執行的參數" "$out" "將執行的參數:"
contains "命令內容" "$out" "*.node.root=Y06"

echo ""
echo "結果: $PASS 通過, $FAIL 失敗"
[ "$FAIL" -eq 0 ]
