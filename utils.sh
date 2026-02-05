#!/usr/bin/env bash

set -e


u_WD=$PWD
u_CACHE=$u_WD/.cache
u_UV=$u_WD/uv
u_PYTHON_DIR=$u_WD/uv

if [ ! -d $u_CACHE ]; then
    mkdir -p $u_CACHE
fi


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
    [ -n "$(find $2 -maxdepth 1 -type f -name "$1")" ]
}

u_is_dir_exist() {
    [ -n "$(find $2 -maxdepth 1 -type d -name "$1")" ]
}

u_glob_dir() {
    local -n _out_var=$2
    _out_var=$(find $2 -maxdepth 1 -type d -name "$1")
}

u_get_base_name() {
    local input="$1"
    local -n _out_var="$2"

    # 1. 移除結尾的 slash (如果有)
    # ${變數%/} 代表：若變數結尾是 / 則移除它，否則保持原樣
    local temp="${input%/}"

    # 2. 執行原有的邏輯：取出最後一段
    _out_var="${temp##*/}"
}

u_get_name() {
    local input="$1"
    local -n _out_var="$2"

    # 1. 移除結尾的 slash (如果有)
    # ${變數%/} 代表：若變數結尾是 / 則移除它，否則保持原樣
    local temp="${input%/}"

    # 2. 執行原有的邏輯：取出最後一段
    _out_var="${temp%%.*}"
}

u_git_clone() {
    local url=$1
    local tag=$2
    local dst=$3
    local repo

    repo=${url##*/}
    repo=${repo%*.git}

    if [ ! -d $dst ]; then
        if [ ! -d $u_CACHE/$repo ]; then
            git clone $url $u_CACHE/$repo
        fi

        echo $PWD
        cp -r $u_CACHE/$repo $dst
    fi

    (
        cd $dst &&
            git fetch &&
            git checkout $tag
    )
}

u_get_latest_file() {
    local target_files=$1
    local -n _out_var=$2

    latest=""
    for file in $target_files; do
        # 如果還沒有 latest，或者當前 file 比 latest 新 (-nt = newer than)
        if [[ -z "$latest" || "$file" -nt "$latest" ]]; then
            latest="$file"
        fi
    done

    _out_var=$latest
}

u_parse_arguments() {
    # 建議加上 -g (global) 確保變數在函數外可用，視你的需求而定
    declare -Ag OPTS
    ARGS=()
    FLAGS=()

    # 使用 while 迴圈配合 $# (剩餘參數個數) 是處理 shift 的標準做法
    while [ $# -gt 0 ]; do
        local key="$1"

        # 檢查是否為 Option (以 - 開頭)
        if [ "${key:0:1}" = "-" ]; then
            # 檢查是否有 Value (下一個參數存在且不是以 - 開頭)
            # 注意：這裡使用了 "${2-}" 來避免 unbound variable 錯誤
            local val="${2-}"
            
            # 判斷下一個參數是否為有效的值
            # 邏輯：如果沒有下一個參數，或者下一個參數是以 - 開頭 (視為下一個 Flag)
            if [ -z "$val" ] || [ "${val:0:1}" = "-" ]; then
                # 視為 Flag (開關)
                FLAGS+=("$key")  # <--- 重要：加上雙引號，防止 * 被展開
                shift 1
            else
                # 視為 Key-Value
                OPTS["$key"]="$val" # <--- 這裡也要確保賦值安全
                shift 2
            fi
        else
            # 一般參數 (Positional Arguments)
            
            # 你的原始邏輯：嚴格禁止參數出現在 Option 之後
            if [ ${#FLAGS[@]} -ne 0 ] || [ ${#OPTS[@]} -ne 0 ]; then
                echo "Error: Positional argument '$key' found after options/flags." >&2
                # print_commands 1  # 假設你有這個函數
                return 1
            fi

            ARGS+=("$key") # <--- 重要：加上雙引號，防止 * 被展開
            shift 1
        fi
    done
}

u_get_argument() {
    local index="$1"
    local default_val="$2"
    local doc="$3"
    local -n _out_var="$4"

    # 1. 檢查 key1 是否存在且有值
    if [ -n "${ARGS[$index]}" ]; then
        _out_var="${ARGS[$index]}"
        return 0
    fi

    # 3. 若都找不到，檢查參數數量是否大於等於 3 (代表有傳入 default_val)
    if [ ! -z $default_val ]; then
        echo "use default value for argument '$index': $default_val" >&2
        _out_var="$default_val"
        return 0
    fi

    # 4. 若沒有預設值，報錯並終止 script
    echo "missing argument. '$index', $doc" >&2
    exit 1

    _out_var=${ARGS[$index]}
}

u_has_flag() {
    local -n _out_var="$2"
    
    if [ ${#FLAGS[@]} -eq 0 ]; then
        _out_var=0
        return 0
    fi

    if echo ${FLAGS[*]} | grep -q "\<${1:2}\>"; then
        _out_var=1
        return 0
    fi

    _out_var=0
}

u_get_option() {
    local key1="$1"
    local key2="$2"
    local default_val="$3"
    local doc="$4"
    local -n _out_var="$5"

    # 1. 檢查 key1 是否存在且有值
    if [ ! -z "$key1" ] && [ -n "${OPTS["$key1"]}" ]; then
        _out_var="${OPTS["$key1"]}"
        return 0
    fi

    # 2. 檢查 key2 是否存在且有值
    if [ -n "${OPTS["$key2"]}" ]; then
        _out_var="${OPTS["$key2"]}"
        return 0
    fi

    # 3. 若都找不到，檢查參數數量是否大於等於 3 (代表有傳入 default_val)
    if [ ! -z $default_val ]; then
        if [ $default_val != "x" ]; then
            echo "use default value for option '$key1', '$key2': $default_val" >&2
        fi
        _out_var="$default_val"
        return 0
    fi

    # 4. 若沒有預設值，報錯並終止 script
    echo "missing option. '$key1', '$key2', $doc" >&2
    exit 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "正在執行測試模式..."
    echo "ARGS: ${ARGS[@]}"
    echo "OPTS: ${OPTS[@]}"
    echo "FLAGS: ${FLAGS[@]}"
    exit 0
fi

u_check_py_version() {
    local version="$1"

    # 1. Regex 優化：支援多位數 (如 3.10) 且不強制要求第三位版號
    # ^ 代表開頭，確保不會比對到奇怪的字串
    if [[ "$version" =~ ^([0-9]+)\.([0-9]+) ]]; then
        local major=${BASH_REMATCH[1]}
        local minor=${BASH_REMATCH[2]}

        # 2. 邏輯檢查：使用 (( ... )) 進行數值運算較直觀
        # 這裡保留你的邏輯：必須是 Python 3，且次版本需 >= 6
        if (( major != 3 )) || (( minor < 6 )); then
            echo "Invalid python version: $version. Only 3.6+ is supported."
            return 1  # 3. 關鍵修正：使用 return 立即退出函式
        fi
    else
        echo "Failed to parse Python version: '$version'"
        return 1
    fi

    # 驗證通過
    return 0
}

# 定義一個 function 來取得 .deb 檔案的套件名稱
u_get_package_name() {
    local deb_file="$1"
    local -n _out_var="$2"

    # 檢查是否有傳入參數
    if [ -z $deb_file ]; then
        echo "錯誤：請提供 .deb 檔案的路徑。" >&2
        return 1
    fi

    # 檢查檔案是否存在且為 .deb 檔案
    if [ ! -f $deb_file ] || [[ ! $deb_file =~ \.deb$ ]]; then
        echo "錯誤：檔案不存在或不是有效的 .deb 檔案。" >&2
        return 1
    fi

    _out_var=$(dpkg-deb -f "$deb_file" Package)
}

u_is_package_installed() {
    dpkg-query -W --showformat='${Status}\n' "$1" 2>/dev/null | grep "install ok installed" >/dev/null
    if [ $? -eq 0 ]; then
        return 0
    fi

    return 1
}

u_install_or_upgrade_deb() {
    local deb_file="$1"

    # 1. 檢查檔案是否存在
    if [ ! -f "$deb_file" ]; then
        echo "file not found: '$deb_file'" >&2
        return 1
    fi

    # 2. 從 .deb 檔案中讀取套件名稱與新版本
    # 使用 dpkg-deb --field 直接讀取 metadata
    local pkg_name
    local new_ver
    pkg_name=$(dpkg-deb --field "$deb_file" Package)
    new_ver=$(dpkg-deb --field "$deb_file" Version)

    if [ -z "$pkg_name" ] || [ -z "$new_ver" ]; then
        echo "failed to read package name or version: $deb_file" >&2
        return 1
    fi

    echo "checking: $pkg_name ($new_ver)"

    # 3. 檢查系統是否已安裝此套件
    # dpkg-query -W 用來查詢，如果沒安裝會回傳非 0，我們把錯誤訊息丟掉
    local cur_ver
    if cur_ver=$(dpkg-query -W -f='${Version}' "$pkg_name" 2>/dev/null); then
        # --- 情況 A：已安裝，檢查版本 ---
        
        # 使用 dpkg --compare-versions 進行專業的版本比較
        # 語法：dpkg --compare-versions <v1> <op> <v2>
        # gt = greater than (大於)
        if dpkg --compare-versions "$new_ver" gt "$cur_ver"; then
            echo "upgrading $pkg_name ($cur_ver -> $new_ver)..."
            sudo apt-get install -y "$deb_file"
        else
            echo "no need to upgrade ($cur_ver)"
        fi
    else
        # --- 情況 B：未安裝 ---
        echo "Installing $pkg_name ($new_ver)..."
        sudo apt-get install -y "$deb_file"
    fi
}

u_apt_install() {
    local pkg_name="$1"

    # 1. 檢查是否已安裝
    # dpkg -s 會檢查套件狀態，&> /dev/null 把輸出丟掉，只看回傳值
    if dpkg -s "$pkg_name" &> /dev/null; then
        echo "$pkg_name has already been installed。"
        return 0
    fi

    # 2. 未安裝則執行安裝
    echo "installing $pkg_name ..."
    # -y 代表自動回答 yes，避免腳本卡住
    sudo apt-get install -y "$pkg_name"
}

u_check_cmd() {
    local cmd=("${@}")
    echo "command:"
    for i in "${cmd[@]}"; do
        echo "    $i"
    done
    echo ""
    if [ $IS_CHECK_CMD -eq 1 ]; then
        read -n 1 -s -r -p "Press any key to continue..."
        echo ""
    else
        read -t 5 -n 1 -s -r -p "Press any key to continue (5s)..." input || true
        echo ""
    fi
}

u_check_uv() {
    if [ ! -f $u_UV/uv ]; then
        echo "uv is not found"
        return 1
    fi

    return 0
}


u_is_python_installed() {
    local uv_python=$($u_UV/uv python find 2>/dev/null)
    local sys_python=$(which python 2>/dev/null)

    # 確保兩個變數都有值
    if [ -n "$uv_python" ] && [ -n "$sys_python" ]; then
        [ "$(realpath "$uv_python" 2>/dev/null)" = "$(realpath "$sys_python" 2>/dev/null)" ]
    else
        return 1
    fi
}

u_is_pymodule_installed() {
    [ u_is_python_installed ] && $($u_UV/uv pip show $1 >/dev/null)
}

u_install_uv() {
    local dst=$1

    if [ $dst != $u_UV ] && [ -f $dst/uv ]; then
        echo "link uv to $dst/uv"
        ln -sf $dst/uv $u_UV/uv
    elif ! check_uv; then
        echo "install uv to $dst"
        apt_install curl
        curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=$dst UV_NO_MODIFY_PATH=1 sh
    else
        echo "uv is already installed at $u_UV"
    fi

    return 0
}


u_install_python() {
    local py_ver=$1
    local venv=$2
    local is_force=$3

    echo "Installing python: $py_ver"
    echo "Virtual environment name: $venv"

    if ! u_check_py_version $py_ver; then
        exit 1
    fi

    if ! u_check_uv; then
        exit 1
    fi

    $u_UV/uv python install -i $u_PYTHON_DIR $py_ver

    if [ $is_force -eq 1 ] && [ -d $u_WD/.venv_$venv-$py_ver ]; then
        rm -rf $u_WD/.venv_$venv-$py_ver
    fi

    if [ ! -d $u_WD/.venv_$venv-$py_ver ]; then
        $u_UV/uv venv -p $u_PYTHON_DIR/cpython*/bin/python .venv_$venv-$py_ver
    fi

    if [ -L activate_$venv-$py_ver ]; then
        unlink activate_$venv-$py_ver
    fi

    ln -s .venv_$venv-$py_ver/bin/activate activate_$venv-$py_ver
    echo "source activate_$venv-$py_ver to use python"
    
    return 0
}


u_check_python_environment() {

    if ! u_is_python_installed; then
        echo "python is not found"
        echo "if python has been installed, run 'source activate_<venv-name>' to activate"
        return 1
    fi

    return 0
}

u_install_project() {
    # pip install cuml-cu11==21.12.02 --extra-index-url=https://pypi.nvidia.com
    $u_UV/uv pip install -e .
}

u_install_package() {
    local pkgname=$1

    $u_UV/uv pip install $pkgname
}

u_install_pybind() {
    local dst=$1
    local ver=$2

    if [ -z $ver ]; then
        ver=2.12.0
    fi

    if [ ! -d $dst/pybind11 ]; then
        u_git_clone https://github.com/pybind/pybind11.git v2.12.0 $dst/pybind11
    fi
}


u_check_cmake() {
    if [ ! -x "$(which cmake)" ]; then
        echo "cmake is not found"
        return 1
    else
        local required_version=$1
        local current_version=$(cmake --version | awk 'NR==1 {print $3}')

        if dpkg --compare-versions "$current_version" "ge" "$required_version"; then
            echo "CMake version: $current_version >= $required_version"
            return 0
        else
            echo "CMake version: $current_version < $required_version"
            return 1
        fi
    fi
}

u_install_cmake() {
    local ver=$1
    local is_link=$2

    if ! u_check_cmake $ver; then
        echo "Installing cmake $ver"
        local arch=$(uname -m)
        if [ ! -f $u_CACHE/cmake-${ver}-linux-${arch}.sh ]; then
            echo "Downloading cmake-${ver}-linux-$arch.sh"
            wget -P $u_CACHE https://github.com/Kitware/CMake/releases/download/v${ver}/cmake-${ver}-linux-${arch}.sh
        fi
        if [ ! -d $u_CACHE/cmake-${ver}-linux-${arch} ]; then
            cd $u_CACHE && bash cmake-${ver}-linux-${arch}.sh --include-subdir --skip-license && cd -
        fi
        if [ $is_link -eq 1 ]; then
            if [ -L /usr/local/bin/cmake ]; then
                sudo unlink /usr/local/bin/cmake
                echo "unlink /usr/local/bin/cmake"
            fi
            sudo ln -s $u_CACHE/cmake-${ver}-linux-${arch}/bin/cmake /usr/local/bin/cmake
            echo "create symlink /usr/local/bin/cmake"
        fi
    fi
}

u_build_wheel() {
    $u_UV/uv build --wheel
}

u_build_lib() {
    local src=$1
    local output=$2

    if [ ! -x "$(which nuitka)" ]; then
        $u_UV/uv pip install nuitka
    fi

    nuitka --include-package=mrtabn --output-dir=$output --module $src
}
