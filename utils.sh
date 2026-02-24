#!/usr/bin/env bash

set -e

[ -n "$DEBUG" ] && set -x

u_print_commands() {
    echo
    sed -ne '/^#/!q;s/.\{1,2\}//;1,2d;p' <"$0"
    [ -z "$1" ] || exit "$1"
}

u_is_end_with() {
    [[ $1 =~ $2$ ]]
}

u_is_start_with() {
    [[ $1 =~ ^$2 ]]
}

u_is_file_exist() {
    [ -n "$(find "$2" -maxdepth 1 -type f -name "$1")" ]
}

u_is_dir_exist() {
    [ -n "$(find "$2" -maxdepth 1 -type d -name "$1")" ]
}

u_glob_dir() {
    local _glob_dir__name="$1"
    local _glob_dir__dir="$2"
    local -n _glob_dir__out_arr="$3"

    mapfile -d '' _glob_dir__out_arr < <(find "$_glob_dir__dir" -maxdepth 1 -name "$_glob_dir__name" -print0)
}

u_get_base_name() {
    local _get_base_name__input="$1"
    local -n _get_base_name__out_var="$2"

    # 1. 移除結尾的 slash (如果有)
    # ${變數%/} 代表：若變數結尾是 / 則移除它，否則保持原樣
    local _get_base_name__temp="${_get_base_name__input%/}"

    # 2. 執行原有的邏輯：取出最後一段
    _get_base_name__out_var="${_get_base_name__temp##*/}"
}

u_get_name() {
    local _get_name__input="$1"
    local -n _get_name__out_var="$2"

    # 1. 移除結尾的 slash (如果有)
    # ${變數%/} 代表：若變數結尾是 / 則移除它，否則保持原樣
    local _get_name__temp="${_get_name__input%/}"

    # 2. 執行原有的邏輯：取出最後一段
    _get_name__out_var="${_get_name__temp%%.*}"
}

u_git_clone() {
    local _git_clone__url="$1"
    local _git_clone__tag="$2"
    local _git_clone__dst="$3"

    git clone "$_git_clone__url" "$_git_clone__dst"

    (
        cd "$_git_clone__dst" &&
            git fetch &&
            git checkout "$_git_clone__tag"
    )
}

u_get_latest_file() {
    local _get_latest_file__path="$1"
    local -n _get_latest_file__out_var="$2"

    local _get_latest_file__target_files
    local _get_latest_file__pattern
    local _get_latest_file__dir
    _get_latest_file__dir=$(dirname "$_get_latest_file__path")
    u_get_base_name "$_get_latest_file__path" _get_latest_file__pattern
    u_glob_dir "$_get_latest_file__pattern" "$_get_latest_file__dir" _get_latest_file__target_files

    _get_latest_file__latest=""
    for _get_latest_file__file in $_get_latest_file__target_files; do
        # 如果還沒有 latest，或者當前 file 比 latest 新 (-nt = newer than)
        if [[ -z "$_get_latest_file__latest" || "$_get_latest_file__file" -nt "$_get_latest_file__latest" ]]; then
            _get_latest_file__latest="$_get_latest_file__file"
        fi
    done

    _get_latest_file__out_var=$_get_latest_file__latest
}

u_parse_arguments() {
    # 建議加上 -g (global) 確保變數在函數外可用，視你的需求而定
    declare -Ag _parse_arguments__OPTS
    _parse_arguments__ARGS=()
    _parse_arguments__FLAGS=()

    # 使用 while 迴圈配合 $# (剩餘參數個數) 是處理 shift 的標準做法
    while [ $# -gt 0 ]; do
        local _parse_arguments__key="$1"

        # 檢查是否為 Option (以 - 開頭)
        if [ "${_parse_arguments__key:0:1}" = "-" ]; then
            # 檢查是否有 Value (下一個參數存在且不是以 - 開頭)
            # 注意：這裡使用了 "${2-}" 來避免 unbound variable 錯誤
            local _parse_arguments__val="${2-}"
            
            # 判斷下一個參數是否為有效的值
            # 邏輯：如果沒有下一個參數，或者下一個參數是以 - 開頭 (視為下一個 Flag)
            if [ -z "$_parse_arguments__val" ] || [ "${_parse_arguments__val:0:1}" = "-" ]; then
                # 視為 Flag (開關)
                _parse_arguments__FLAGS+=("$_parse_arguments__key")  # <--- 重要：加上雙引號，防止 * 被展開
                shift 1
            else
                # 視為 Key-Value
                _parse_arguments__OPTS["$_parse_arguments__key"]="${_parse_arguments__val%/}" # <--- 這裡也要確保賦值安全
                shift 2
            fi
        else
            # 一般參數 (Positional Arguments)
            
            # 你的原始邏輯：嚴格禁止參數出現在 Option 之後
            if [ ${#_parse_arguments__FLAGS[@]} -ne 0 ] || [ ${#_parse_arguments__OPTS[@]} -ne 0 ]; then
                echo "Error: Positional argument '$_parse_arguments__key' found after options/flags." >&2
                # print_commands 1  # 假設你有這個函數
                return 1
            fi

            _parse_arguments__ARGS+=("$_parse_arguments__key") # <--- 重要：加上雙引號，防止 * 被展開
            shift 1
        fi
    done
}

u_get_argument() {
    local _get_argument__index="$1"
    local _get_argument__default_val="$2"
    local __get_argument__doc="$3"
    local -n _get_argument__out_var="$4"

    # 1. 檢查 key1 是否存在且有值
    if [ -n "${_parse_arguments__ARGS[$_get_argument__index]}" ]; then
        _get_argument__out_var="${_parse_arguments__ARGS[$_get_argument__index]}"
        return 0
    fi

    # 3. 若都找不到，檢查參數數量是否大於等於 3 (代表有傳入 default_val)
    if [ -n "$_get_argument__default_val" ]; then
        echo "use default value for argument '$_get_argument__index': $_get_argument__default_val" >&2
        _get_argument__out_var="$_get_argument__default_val"
        return 0
    fi

    # 4. 若沒有預設值，報錯並終止 script
    echo "missing argument. '$_get_argument__index', $__get_argument__doc" >&2
    exit 1

}

u_has_flag() {
    local -n _has_flag__out_var="$2"
    
    if [ ${#_parse_arguments__FLAGS[@]} -eq 0 ]; then
        _has_flag__out_var=0
        return 0
    fi

    if echo "${_parse_arguments__FLAGS[@]}" | grep -q "\<${1:2}\>"; then
        _has_flag__out_var=1
        return 0
    fi

    _has_flag__out_var=0
}

u_get_option() {
    local _get_option__key1="$1"
    local _get_option__key2="$2"
    local _get_option__default_val="$3"
    local _get_option__doc="$4"
    local -n _get_option__out_var="$5"

    # 1. 檢查 key1 是否存在且有值
    if [ -n "$_get_option__key1" ] && [ -n "${_parse_arguments__OPTS["$_get_option__key1"]}" ]; then
        _get_option__out_var="${_parse_arguments__OPTS["$_get_option__key1"]}"
        return 0
    fi

    # 2. 檢查 key2 是否存在且有值
    if [ -n "${_parse_arguments__OPTS["$_get_option__key2"]}" ]; then
        _get_option__out_var="${_parse_arguments__OPTS["$_get_option__key2"]}"
        return 0
    fi

    # 3. 若都找不到，檢查參數數量是否大於等於 3 (代表有傳入 default_val)
    if [ -n "$_get_option__default_val" ]; then
        if [ "$_get_option__default_val" != "x" ]; then
            echo "use default value for option '$_get_option__key1', '$_get_option__key2': $_get_option__default_val" >&2
            _get_option__out_var="$_get_option__default_val"
            return 0
        fi
        _get_option__out_var=""
        return 0
    fi

    # 4. 若沒有預設值，報錯並終止 script
    echo "missing option. '$_get_option__key1', '$_get_option__key2', $_get_option__doc" >&2
    exit 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "正在執行測試模式..."
    echo "ARGS: " "${_parse_arguments__ARGS[@]}"
    echo "OPTS: " "${_parse_arguments__OPTS[@]}"
    echo "FLAGS: " "${_parse_arguments__FLAGS[@]}"
    exit 0
fi

u_safe_delete() {
    local _safe_delete__target="$1"
    
    # 1. 檢查是否為空
    [[ -z "$_safe_delete__target" ]] && { echo "empty path"; return 1; }
    
    # 2. 絕對禁止的路徑黑名單
    if [[ "$_safe_delete__target" == "/" || "$_safe_delete__target" == "/bin" || "$_safe_delete__target" == "/usr" || "$_safe_delete__target" == "/etc" ]]; then
        echo "forbidden path: $_safe_delete__target"
        return 1
    fi
    
    local _safe_delete__basename
    u_get_base_name "$_safe_delete__target" _safe_delete__basename

    # 3. 執行刪除
    mkdir -p /tmp/recycle
    rm -rf /tmp/recycle/"$_safe_delete__basename"
    mv "$_safe_delete__target" /tmp/recycle
}

u_check_version_format() {
    local version="$1"
    
    # 定義正則表達式：開頭(^) + 數字(\.) + 數字(\.) + 數字 + 結尾($)
    # ⚠️ 注意：在 Bash 中，=~ 右邊的正則表達式絕對不可以加雙引號 ""
    local regex="^[0-9]+\.[0-9]+\.[0-9]+$"

    if [[ "$version" =~ $regex ]]; then
        return 0
    else
        return 1
    fi
}

# 定義一個 function 來取得 .deb 檔案的套件名稱
u_get_package_name() {
    local _get_package_name__deb_file="$1"
    local -n _get_package_name__out_var="$2"

    # 檢查是否有傳入參數
    if [ -z "$_get_package_name__deb_file" ]; then
        echo "錯誤：請提供 .deb 檔案的路徑。" >&2
        return 1
    fi

    # 檢查檔案是否存在且為 .deb 檔案
    if [ ! -f "$_get_package_name__deb_file" ] || [[ ! "$_get_package_name__deb_file" =~ \.deb$ ]]; then
        echo "錯誤：檔案不存在或不是有效的 .deb 檔案。" >&2
        return 1
    fi

    _get_package_name__out_var=$(dpkg-deb -f "$_get_package_name__deb_file" Package)
}

u_is_package_installed() {
    if dpkg-query -W --showformat='${Status}\n' "$1" 2>/dev/null | grep "install ok installed" >/dev/null; then
        return 0
    fi

    return 1
}

u_install_or_upgrade_deb() {
    local _install_or_upgrade_deb__deb_file="$1"

    if [ -z "$_install_or_upgrade_deb__deb_file" ]; then
        return 0
    fi

    # 1. 檢查檔案是否存在
    if [ ! -f "$_install_or_upgrade_deb__deb_file" ]; then
        echo "file not found: '$_install_or_upgrade_deb__deb_file'" >&2
        return 0
    fi

    # 2. 從 .deb 檔案中讀取套件名稱與新版本
    # 使用 dpkg-deb --field 直接讀取 metadata
    local _install_or_upgrade_deb__pkg_name
    local _install_or_upgrade_deb__new_ver
    _install_or_upgrade_deb__pkg_name=$(dpkg-deb --field "$_install_or_upgrade_deb__deb_file" Package)
    _install_or_upgrade_deb__new_ver=$(dpkg-deb --field "$_install_or_upgrade_deb__deb_file" Version)

    if [ -z "$_install_or_upgrade_deb__pkg_name" ] || [ -z "$_install_or_upgrade_deb__new_ver" ]; then
        echo "failed to read package name or version: $_install_or_upgrade_deb__deb_file" >&2
        return 1
    fi

    echo "checking: $_install_or_upgrade_deb__pkg_name ($_install_or_upgrade_deb__new_ver)"

    # 3. 檢查系統是否已安裝此套件
    # dpkg-query -W 用來查詢，如果沒安裝會回傳非 0，我們把錯誤訊息丟掉
    local _install_or_upgrade_deb__cur_ver
    if _install_or_upgrade_deb__cur_ver=$(dpkg-query -W -f='${Version}' "$_install_or_upgrade_deb__pkg_name" 2>/dev/null); then
        # --- 情況 A：已安裝，檢查版本 ---
        
        # 使用 dpkg --compare-versions 進行專業的版本比較
        # 語法：dpkg --compare-versions <v1> <op> <v2>
        # gt = greater than (大於)
        if dpkg --compare-versions "$_install_or_upgrade_deb__new_ver" gt "$_install_or_upgrade_deb__cur_ver"; then
            echo "upgrading $_install_or_upgrade_deb__pkg_name ($_install_or_upgrade_deb__cur_ver -> $_install_or_upgrade_deb__new_ver)..."
            sudo apt-get install -y "$_install_or_upgrade_deb__deb_file"
        else
            echo "no need to upgrade ($_install_or_upgrade_deb__cur_ver)"
        fi
    else
        # --- 情況 B：未安裝 ---
        echo "Installing $_install_or_upgrade_deb__pkg_name ($_install_or_upgrade_deb__new_ver)..."
        sudo apt-get install -y "$_install_or_upgrade_deb__deb_file"
    fi
}

u_apt_install() {
    local _apt_install__pkg_name="$1"

    # 1. 檢查是否已安裝
    # dpkg -s 會檢查套件狀態，&> /dev/null 把輸出丟掉，只看回傳值
    if dpkg -s "$_apt_install__pkg_name" &> /dev/null; then
        return 0
    fi

    # 2. 未安裝則執行安裝
    echo "installing $_apt_install__pkg_name ..."
    # -y 代表自動回答 yes，避免腳本卡住
    sudo apt-get install -y "$_apt_install__pkg_name"
}

u_check_cmd() {
    local _check_cmd__cmd=("${@}")
    
    echo "command:"
    for i in "${_check_cmd__cmd[@]}"; do
        echo "    $i"
    done
    echo ""
    read -t 5 -n 1 -s -r -p "Press any key to continue (5s)..." input || true
    echo ""
}

u_check_uv() {
    local _check_uv__cwd="$1"
    
    if [ -z "$_check_uv__cwd" ]; then
        return 1
    fi
    

    if [ ! -f "$_check_uv__cwd/uv/uv" ]; then
        echo "uv is not found"
        return 1
    fi

    return 0
}

u_install_uv() {
    local _install_uv__cwd="$1"
    
    if [ -z "$_install_uv__cwd" ]; then
        return 1
    fi
    
    local _install_uv__dst="$2"

    if [ -n "$_install_uv__dst" ]; then
        _install_uv__dst=$(realpath "$_install_uv__dst" 2>/dev/null)
    else
        _install_uv__dst="$_install_uv__cwd"/uv
    fi

    if [ "$_install_uv__dst" != "$_install_uv__cwd"/uv ] && [ -f "$_install_uv__dst"/uv ]; then
        echo "link uv to $_install_uv__dst"
        ln -sf "$_install_uv__dst" "$_install_uv__cwd"/uv
    elif ! u_check_uv "$_install_uv__cwd"; then
        echo "install uv to $_install_uv__dst"
        u_apt_install curl
        curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="$_install_uv__dst" UV_NO_MODIFY_PATH=1 sh
    else
        echo "uv is already installed at $_install_uv__dst"
    fi

    return 0
}

u_clean_uv() {
    local _clean_uv__cwd="$1"
    
    if [ -z "$_clean_uv__cwd" ]; then
        return 1
    fi
    
    if ! u_check_uv "$_clean_uv__cwd"; then
        return 0
    fi

    if [ -L "$_clean_uv__cwd/uv" ]; then
        unlink "$_clean_uv__cwd/uv"
    else
        "$_clean_uv__cwd"/uv/uv cache clean
        u_safe_delete "$("$_clean_uv__cwd"/uv/uv python dir)"
        u_safe_delete "$("$_clean_uv__cwd"/uv/uv tool dir)"
        u_safe_delete "$_clean_uv__cwd"/uv
    fi

    return 0
}

u_check_py_version() {
    local _check_py_version__ver="$1"

    # 1. Regex 優化：支援多位數 (如 3.10) 且不強制要求第三位版號
    # ^ 代表開頭，確保不會比對到奇怪的字串
    if [[ "$_check_py_version__ver" =~ ^([0-9]+)\.([0-9]+) ]]; then
        local _check_py_version__major=${BASH_REMATCH[1]}
        local _check_py_version__minor=${BASH_REMATCH[2]}

        # 2. 邏輯檢查：使用 (( ... )) 進行數值運算較直觀
        # 這裡保留你的邏輯：必須是 Python 3，且次版本需 >= 6
        if (( _check_py_version__major != 3 )) || (( _check_py_version__minor < 6 )); then
            echo "Invalid python version: $_check_py_version__ver. Only 3.6+ is supported."
            return 1  # 3. 關鍵修正：使用 return 立即退出函式
        fi
    fi

    # 驗證通過
    return 0
}

u_check_python() {
    local _check_python__cwd="$1"
    
    if [ -z "$_check_python__cwd" ]; then
        return 1
    fi
    
    local _check_python__uv_python
    local _check_python__sys_python
    _check_python__uv_python=$("$_check_python__cwd"/uv/uv python find 2>/dev/null)
    _check_python__sys_python=$(which python 2>/dev/null)

    # 確保兩個變數都有值
    if [ -n "$_check_python__uv_python" ] && [ -n "$_check_python__sys_python" ]; then
        if [ "$(realpath "$_check_python__uv_python" 2>/dev/null)" = "$(realpath "$_check_python__sys_python" 2>/dev/null)" ]; then
            return 0
        else
            echo "not using local python"
            return 1
        fi
    else
        echo "python is not found"
        return 1
    fi
}

u_check_pymodule() {
    local _check_pymodule__cwd="$1"
    
    if [ -z "$_check_pymodule__cwd" ]; then
        return 1
    fi
    
    local _check_pymodule__module="$2"
    if u_check_python "$_check_pymodule__cwd"; then
        if "$_check_pymodule__cwd"/uv/uv pip show "$_check_pymodule__module" >/dev/null; then
            return 0
        else
            return 1
        fi
    fi

    return 1
}


u_install_python() {
    local _install_python__cwd="$1"
    
    if [ -z "$_install_python__cwd" ]; then
        return 1
    fi
    
    local _install_python__ver="$2"
    local _install_python__venv="$3"
    local _install_python__is_force="$4"

    if ! u_check_version_format "$_install_python__ver"; then
        echo "invalid version: '$_install_python__ver'"
        return 1
    fi

    echo "Installing python: $_install_python__ver"
    echo "Virtual environment name: $_install_python__venv"

    if ! u_check_py_version "$_install_python__ver"; then
        exit 1
    fi

    if ! u_check_uv "$_install_python__cwd"; then
        exit 1
    fi

    "$_install_python__cwd"/uv/uv python install -i "$_install_python__cwd"/uv "$_install_python__ver"

    if [ "$_install_python__is_force" -eq 1 ] && [ -d "$_install_python__cwd/$.venv_$_install_python__venv-$_install_python__ver" ]; then
        local _install_python__path
        _install_python__path="$_install_python__cwd/.venv_$_install_python__venv-$_install_python__ver"
        u_safe_delete "$_install_python__path"
    fi

    if [ ! -d "$_install_python__cwd/.venv_$_install_python__venv-$_install_python__ver" ]; then
        local _install_python__arch
        local _install_python__osname
        _install_python__arch=$(uname -m)
        _install_python__osname=$(uname -s | tr '[:upper:]' '[:lower:]')
        "$_install_python__cwd"/uv/uv venv -p "$_install_python__cwd/uv/cpython-$_install_python__ver-$_install_python__osname-$_install_python__arch-gnu/bin/python" "$_install_python__cwd/.venv_$_install_python__venv-$_install_python__ver"
    fi

    if [ -L "$_install_python__cwd/activate_$_install_python__venv-$_install_python__ver" ]; then
        unlink "$_install_python__cwd/activate_$_install_python__venv-$_install_python__ver"
    fi

    ln -s "$_install_python__cwd/.venv_$_install_python__venv-$_install_python__ver"/bin/activate "$_install_python__cwd/activate_$_install_python__venv-$_install_python__ver"
    echo "source activate_$_install_python__venv-$_install_python__ver to use python"
    
    return 0
}

u_clean_python() {
    local _clean_python__cwd="$1"
    
    if [ -z "$_clean_python__cwd" ]; then
        return 1
    fi
    
    if ! u_check_python "$_clean_python__cwd"; then
        return 0
    fi

    for f in "$_clean_python__cwd"/.venv*; do
        u_safe_delete "$f"
    done
    
    for f in "$_clean_python__cwd"/activate*; do
        unlink "$f"
    done
}

u_check_go_version() {
    local _check_go_version__ver="$1"

    # 1. Regex 優化：支援多位數 (如 3.10) 且不強制要求第三位版號
    # ^ 代表開頭，確保不會比對到奇怪的字串
    if [[ "$_check_go_version__ver" =~ 1\.([0-9]+)\.[0-9]+ ]]; then
        local major=${BASH_REMATCH[1]}

        # 2. 邏輯檢查：使用 (( ... )) 進行數值運算較直觀
        if (( major < 18 )); then
            echo "Invalid go version: $_check_go_version__ver. Only 1.18+ is supported."
            return 1  # 3. 關鍵修正：使用 return 立即退出函式
        fi
    fi

    # 驗證通過
    return 0
}

u_check_go() {
    local _check_go__cwd="$1"
    
    if [ -z "$_check_go__cwd" ]; then
        return 1
    fi
    
    if [ ! -d "$_check_go__cwd/.goenv/versions" ]; then
        echo "go is not found"
        return 1
    fi

    local _check_go__dir
    local _check_go__ver
    u_get_latest_file "$_check_go__cwd/.goenv/versions/*.*.*" _check_go__dir
    u_get_base_name "$_check_go__dir" _check_go__ver

    if ! u_check_go_version "$_check_go__ver"; then
        echo "go version is not supported"
        return 1
    fi
    
    return 0
}

u_get_go() {
    local _get_go__cwd="$1"
    local -n _get_go__out_var="$2"
    
    if [ -z "$_get_go__cwd" ]; then
        return 1
    fi
    
    if ! u_check_go "$_get_go__cwd"; then
        return 1
    fi

    local _get_go__go_ver_path
    u_get_latest_file "$_get_go__cwd/.goenv/versions/*.*.*" _get_go__go_ver_path

    _get_go__out_var=$_get_go__go_ver_path/bin/go
}

u_get_gobin() {
    local _get_gobin__cwd="$1"
    local _get_gobin__binname="$2"
    local -n _get_gobin__out_var="$3"
    
    if [ -z "$_get_gobin__cwd" ]; then
        return 1
    fi
    
    if ! u_check_go "$_get_gobin__cwd"; then
        return 1
    fi

    local _get_gobin__gobin
    local _get_gobin__gopath
    u_get_go "$_get_gobin__cwd" _get_gobin__gobin
    _get_gobin__gopath=$($_get_gobin__gobin env GOPATH)

    if [ ! -f "$_get_gobin__gopath"/bin/"$_get_gobin__binname" ]; then
        return 1
    fi

    _get_gobin__out_var="$_get_gobin__gopath"/bin/"$_get_gobin__binname"
}



u_check_gopkg() {
    local _check_gopkg__cwd="$1"
    local _check_gopkg__pkgname="$2"
    
    if [ -z "$_check_gopkg__cwd" ]; then
        return 1
    fi

    local _check_gopkg__gobin
    local _check_gopkg__gopath
    u_get_go "$_check_gopkg__cwd" _check_gopkg__gobin
    _check_gopkg__gopath=$($_check_gopkg__gobin env GOPATH)

    if [ ! -f "$_check_gopkg__gopath"/pkg/mod/"$_check_gopkg__pkgname" ]; then
        return 1
    fi

    return 0
}

u_check_gobin() {
    local _check_gobin__cwd="$1"
    local _check_gobin__binname="$2"
    
    if [ -z "$_check_gobin__cwd" ]; then
        return 1
    fi

    local _check_gobin__gobin
    local _check_gobin__gopath
    u_get_go "$_check_gobin__cwd" _check_gobin__gobin
    _check_gobin__gopath=$($_check_gobin__gobin env GOPATH)

    if [ ! -f "$_check_gobin__gopath"/bin/"$_check_gobin__binname" ]; then
        return 1
    fi

    return 0
}    

u_install_go() {
    local _install_go__cwd="$1"
    
    if [ -z "$_install_go__cwd" ]; then
        return 1
    fi
    
    local go_ver="$2"
    local is_force="$3"

    if ! u_check_version_format "$go_ver"; then
        echo "invalid version: '$go_ver'"
        return 1
    fi

    echo "Installing go $go_ver"
    
    if ! u_check_go_version "$go_ver"; then
        exit 1
    fi

    if [ "$is_force" -eq 1 ] && [ -d "$_install_go__cwd/.goenv/versions/$go_ver" ]; then
        GOENV_ROOT="$_install_go__cwd"/.goenv "$_install_go__cwd"/.goenv/bin/goenv uninstall "$go_ver"
    fi

    if [ ! -d "$_install_go__cwd/.goenv/versions/$go_ver" ]; then
        u_git_clone https://github.com/syndbg/goenv.git 2.2.34 "$_install_go__cwd"/.goenv
        GOENV_ROOT="$_install_go__cwd"/.goenv "$_install_go__cwd"/.goenv/bin/goenv install "$go_ver"
    fi

    if [ -L "$_install_go__cwd/activate_go-$go_ver" ]; then
        unlink "$_install_go__cwd/activate_go-$go_ver"
    fi

    echo "PATH=$_install_go__cwd/.goenv/versions/$go_ver/bin:\$PATH" >"$_install_go__cwd/activate_go-$go_ver"

    echo "source activate_go-$go_ver to use go"
    
}

u_install_gopkg() {
    local _install_gopkg__cwd="$1"
    local _install_gopkg__url="$2"
    
    if [ -z "$_install_gopkg__cwd" ]; then
        return 1
    fi

    local gobin
    u_get_go "$_install_gopkg__cwd" gobin

    "$gobin" install "$_install_gopkg__url"
}

u_build_golib() {
    local _build_golib__cwd="$1"
    local _build_golib__dst="$2"
    
    if [ -z "$_build_golib__cwd" ]; then
        return 1
    fi

    local gobin
    u_get_go "$_build_golib__cwd" gobin

    if ! ( 
        cd "$_build_golib__cwd" && 
        "$gobin" build -buildvcs=false -o "$_build_golib__dst"
    ); then
        return 1
    fi
}

u_clean_go() {
    local _clean_go__cwd="$1"
    
    if [ -z "$_clean_go__cwd" ]; then
        return 1
    fi

    if ! u_check_go "$_clean_go__cwd"; then
        return 0
    fi

    local _clean_go__gobin
    local _clean_go__gopath
    u_get_go "$_clean_go__cwd" _clean_go__gobin
    _clean_go__gopath=$($_clean_go__gobin env GOPATH)

    u_safe_delete "$_clean_go__gopath"

    u_safe_delete "$_clean_go__cwd"/.goenv

    for f in "$_clean_go__cwd"/activate*; do
        unlink "$f"
    done

}

u_install_project() {
    local _install_project__cwd="$1"
    
    if [ -z "$_install_project__cwd" ]; then
        return 1
    fi
    
    # pip install cuml-cu11==21.12.02 --extra-index-url=https://pypi.nvidia.com
    "$_install_project__cwd"/uv/uv pip install -e "$_install_project__cwd"
}

u_install_package() {
    local _install_package__cwd="$1"
    local _install_package__pkgname="$2"
    
    if [ -z "$_install_package__cwd" ]; then
        return 1
    fi

    "$_install_package__cwd"/uv/uv pip install "$_install_package__pkgname"
}

u_install_pybind() {
    local _install_pybind__dst="$1"
    local _install_pybind__ver="$2"

    if [ -z "$_install_pybind__ver" ]; then
        _install_pybind__ver=2.12.0
    fi

    if [ ! -d "$_install_pybind__dst"/pybind11 ]; then
        u_git_clone https://github.com/pybind/pybind11.git v"$_install_pybind__ver" "$_install_pybind__dst"/pybind11
    fi
}


u_check_cmake() {
    if [ ! -x "$(which cmake)" ]; then
        echo "cmake is not found"
        return 1
    else
        local _check_cmake__required_ver="$1"
        local _check_cmake__current_ver
        _check_cmake__current_ver=$(cmake --version | awk 'NR==1 {print $3}')

        if dpkg --compare-versions "$_check_cmake__current_ver" "ge" "$_check_cmake__required_ver"; then
            echo "CMake version: $_check_cmake__current_ver >= $_check_cmake__required_ver"
            return 0
        else
            echo "CMake version: $_check_cmake__current_ver < $_check_cmake__required_ver"
            return 1
        fi
    fi
}

u_install_cmake() {
    local _install_cmake__cwd="$1"
    local _install_cmake__ver="$2"
    local _install_cmake__is_link="$3"
    
    if [ -z "$_install_cmake__cwd" ]; then
        return 1
    fi

    if ! u_check_version_format "$_install_cmake__ver"; then
        echo "invalid version: '$_install_cmake__ver'"
        return 1
    fi

    mkdir -p "$_install_cmake__cwd/.cache"

    if ! u_check_cmake "$_install_cmake__ver"; then
        echo "Installing cmake $_install_cmake__ver"
        local _install_cmake__arch
        _install_cmake__arch=$(uname -m)
        if [ ! -f "$_install_cmake__cwd/.cache/cmake-$_install_cmake__ver-linux-$_install_cmake__arch.sh" ]; then
            echo "Downloading cmake-$_install_cmake__ver-linux-$_install_cmake__arch.sh"
            wget -P "$_install_cmake__cwd/.cache" "https://github.com/Kitware/CMake/releases/download/v$_install_cmake__ver/cmake-$_install_cmake__ver-linux-$_install_cmake__arch.sh"
        fi
        if [ ! -d "$_install_cmake__cwd/.cache/cmake-$_install_cmake__ver-linux-$_install_cmake__arch" ]; then
            cd "$_install_cmake__cwd/.cache" && bash "cmake-$_install_cmake__ver-linux-$_install_cmake__arch.sh" --include-subdir --skip-license && cd -
        fi
        if [ "$_install_cmake__is_link" -eq 1 ]; then
            if [ -L /usr/local/bin/cmake ]; then
                sudo unlink /usr/local/bin/cmake
                echo "unlink /usr/local/bin/cmake"
            fi
            sudo ln -s "$_install_cmake__cwd/.cache/cmake-$_install_cmake__ver-linux-$_install_cmake__arch/bin/cmake" /usr/local/bin/cmake
            echo "create symlink /usr/local/bin/cmake"
        fi
    fi
}

u_clean_cmake() {
    local _clean_cmake__cwd="$1"
    
    if [ -z "$_clean_cmake__cwd" ]; then
        return 1
    fi
    
    if ! u_check_cmake "$_clean_cmake__cwd"; then
        return 0
    fi

    if [ -L /usr/local/bin/cmake ]; then
        local _clean_cmake__real_path
        local _clean_cmake__real_parent="$_clean_cmake__cwd/.cache/cmake"
        _clean_cmake__real_path=$(readlink /usr/local/bin/cmake)

        if [[ "$_clean_cmake__real_path" == "$_clean_cmake__real_parent"/* ]]; then
            sudo unlink /usr/local/bin/cmake
            echo "unlink /usr/local/bin/cmake"
        fi
    fi

    for f in "$_clean_cmake__cwd"/.cache/cmake*; do
        u_safe_delete "$f"
    done

    return 0
}

u_build_wheel() {
    local _build_wheel__cwd="$1"
    
    if [ -z "$_build_wheel__cwd" ]; then
        return 1
    fi
    
    "$_build_wheel__cwd"/uv/uv build --wheel
}

u_build_lib() {
    local _build_lib__cwd="$1"
    local _build_lib__src="$2"
    local _build_lib__output="$3"
    
    if [ -z "$_build_lib__cwd" ]; then
        return 1
    fi

    if [ ! -x "$(which nuitka)" ]; then
        "$_build_lib__cwd"/uv/uv pip install nuitka
    fi

    nuitka --include-package=mrtabn --output-dir="$_build_lib__output" --module "$_build_lib__src"
}