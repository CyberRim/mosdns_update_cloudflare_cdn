# ## Mosdns update Cloudflare CDN
#
# 此脚本用于更新mosdns配置文件中的Cloudflare CDN IP，详见https://github.com/XIU2/CloudflareSpeedTest/discussions/317
# 适用mosdns版本：v5，先前版本不兼容，可能需要修改一定的正则表达式
# 适用CloudflareSpeedTest版本：v2.2.5，先前版本未测试
# 脚本测试环境：debian12，其他linux发行版未测试
#
# ### 脚本工作流程：
#
# 1. 找到mosdns配置文件中带有black_hole和#tag::cloudflare_cdn_fastest_ip的行
# 2. 检查此行中的black_hole ip是否需要更新
# 3. 如果需要更新，测试Cloudflare CDN最快ip
# 4. 更新black_hole ip
# 5. 重启mosdns
#
# ### 使用方法：
#
# 1. 部署mosdns
# 2. 部署CloudflareSpeedTest
# 3. 根据根目录下的配置文件default.config修改配置
#    ipset_ipv4_file：CloudflareSpeedTest项目中的ip.txt文件路径
#    ipset_ipv6_file：为CloudflareSpeedTest项目中的ipv6.txt文件路径
#    cloudflare_speed_test_cmd：CloudflareSpeedTest项目中CloudflareST可执行文件路径
#    mosdns_config_file：mosdns项目中的配置文件路径
#    restart_mosdns_cmd：重启mosdns的命令
#    log_file：日志文件路径
# 4. 编写mosdns配置文件，写法参考https://github.com/XIU2/CloudflareSpeedTest/discussions/317#discussioncomment-5824217
# 5. 为mosdns配置文件中的exec：black_hole 这一行的末尾加上#tag::cloudflare_cdn_fastest_ip的注释
# 6. 执行脚本。需要定时任务可自行编写crontab或systemd的timer

LATENCY_THRESHOLD=200                                                                # 延迟下限，为整数，单位ms，详见CloudflareST的-tl参数
SPEED_THRESHOLD=3                                                                    # 速度下限，为正数，单位Mbps，详见CloudflareST的-sl参数
TEST_URL="https://cdn.cloudflare.steamstatic.com/steam/apps/256843155/movie_max.mp4" # 测速链接，如测速出现0.00，请换其他链接，详见https://github.com/XIU2/CloudflareSpeedTest/issues/168

TAG_STRING="#tag::cloudflare_cdn_fastest_ip"

ipv4_pattern="((1[0-9][0-9]\.)|(2[0-4][0-9]\.)|(25[0-5]\.)|([1-9][0-9]\.)|([0-9]\.)){3}((1[0-9][0-9])|(2[0-4][0-9])|(25[0-5])|([1-9][0-9])|([0-9]))"
ipv6_pattern="((([0-9A-Fa-f]{1,4}:){7}([0-9A-Fa-f]{1,4}|:))|(([0-9A-Fa-f]{1,4}:){6}(:[0-9A-Fa-f]{1,4}|((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3})|:))|(([0-9A-Fa-f]{1,4}:){5}(((:[0-9A-Fa-f]{1,4}){1,2})|:((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3})|:))|(([0-9A-Fa-f]{1,4}:){4}(((:[0-9A-Fa-f]{1,4}){1,3})|((:[0-9A-Fa-f]{1,4})?:((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3}))|:))|(([0-9A-Fa-f]{1,4}:){3}(((:[0-9A-Fa-f]{1,4}){1,4})|((:[0-9A-Fa-f]{1,4}){0,2}:((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3}))|:))|(([0-9A-Fa-f]{1,4}:){2}(((:[0-9A-Fa-f]{1,4}){1,5})|((:[0-9A-Fa-f]{1,4}){0,3}:((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3}))|:))|(([0-9A-Fa-f]{1,4}:){1}(((:[0-9A-Fa-f]{1,4}){1,6})|((:[0-9A-Fa-f]{1,4}){0,4}:((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3}))|:))|(:(((:[0-9A-Fa-f]{1,4}){1,7})|((:[0-9A-Fa-f]{1,4}){0,5}:((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])){3}))|:)))(%.+)?"

log() {
    echo "$1" | sed -E "s/^/[$(date +%Y-%m-%d\ %H:%M:%S)]/" | tee -a "${log_file}" >/dev/stderr
}

config() {
    local default_config_file="./default.config"
    local config_file_list=(
        "${default_config_file}"
    )
    # IFS=$'\n' config_file_list+=($(find ./ -maxdepth 1 -type f -regex '^.*\.config$' | grep -v -E "^${default_config_file//\./\\.}$" | sort))
    mapfile -t -O ${#config_file_list[@]} config_file_list < <(find ./ -maxdepth 1 -type f -regex '^.*\.config$' | grep -v -E "^${default_config_file//\./\\.}$" | sort -r)
    for config_file in "${config_file_list[@]}"; do
        if [[ -f "$config_file" ]]; then
            source "$config_file"
            log "Loaded config file: $config_file"
        else
            log "Config file $config_file does not exist."
        fi
    done
}

format_ip_from_test_result() {
    local result="$1"
    echo "${result}" | awk '{print $1}'
}

format_latency_from_test_result() {
    local result="$1"
    echo "${result}" | awk '{print $2}'
}

format_speed_from_test_result() {
    local result="$1"
    echo "${result}" | awk '{print $3}'
}

format_test_reslut() {
    local result="$1"
    echo "${result}" | grep -E "(${ipv4_pattern})|(${ipv6_pattern})" | awk -v OFS='\t' '{print $1,$5,$6}'
}

test_ip() {
    local opt=(
        -url "${TEST_URL}"
        -tl "${LATENCY_THRESHOLD}"
        -sl "${SPEED_THRESHOLD}"
        -dn 1
        -p 1
    )
    if [[ "$1" =~ ${ipv4_pattern} || "$1" =~ ${ipv6_pattern} ]]; then
        opt+=(-ip "$1")
    else
        opt+=(-f "$1")
    fi
    if [[ -n ${cloudflare_speed_test_remote_host} ]]; then
        opt+=(-o \"\")
        log "ssh to ${cloudflare_speed_test_remote_host} with command: ${cloudflare_speed_test_cmd} ${opt[*]}"
        ssh -o BatchMode=yes "${cloudflare_speed_test_remote_host}" "${cloudflare_speed_test_cmd}" "${opt[@]}" 2>/dev/null
        [[ "$?" -ne 0 ]] && log "ssh to ${cloudflare_speed_test_remote_host} failed, check the remote host and publickey"
    else
        opt+=(-o "")
        log "running command: ${cloudflare_speed_test_cmd} ${opt[*]}"
        "${cloudflare_speed_test_cmd}" "${opt[@]}" 2>/dev/null
        [[ "$?" -ne 0 ]] && log "run command ${cloudflare_speed_test_cmd} failed, check the command and parameters"
    fi
}

test_fastest_ip() {
    local ip_version="$1"
    local ipset_file=
    if [[ "$ip_version" == "ipv4" ]]; then
        ipset_file="${ipset_ipv4_file}"
    elif [[ "$ip_version" == "ipv6" ]]; then
        ipset_file="${ipset_ipv6_file}"
    else
        log "unknown ip version"
        exit 1
    fi
    log "testing fastest ${ip_version}"
    local result_raw="$(test_ip "${ipset_file}")"
    local result="$(format_test_reslut "${result_raw}")"
    log "fastest ${ip_version}: ${result}"
    echo "${result}"
}

is_ip_good() {
    local ip="$1"
    local result_raw="$(test_ip "${ip}")"
    local result="$(format_test_reslut "${result_raw}")"
    log "config ip test: ${result}"
    local latency="$(format_latency_from_test_result "${result}" | sed -E "s/\.[0-9]+//")"
    local speed="$(format_speed_from_test_result "${result}" | sed -E "s/\.[0-9]+//")"
    if [[ "${latency}" -gt "${LATENCY_THRESHOLD}" || "${speed}" -lt "${SPEED_THRESHOLD}" ]]; then
        return 1
    else
        log "${ip} is good"
        return 0
    fi
}

is_need_update() {
    local ip_version="$1"
    if [[ "$ip_version" == "ipv4" ]]; then
        local ip_pattern="${ipv4_pattern}"
    elif [[ "$ip_version" == "ipv6" ]]; then
        local ip_pattern="${ipv6_pattern}"
    else
        log "unknown update ip version"
        exit 1
    fi
    local ip=$(sed -n -E "s/^.*?black_hole.*?\b(${ip_pattern}).*?${TAG_STRING}.*$/\1/p" "${mosdns_config_file}")
    if [[ -z "${ip}" ]]; then
        log "${ip_version} empty"
        return 0
    fi
    is_ip_good "${ip}"
    if [ $? -ne 0 ]; then
        log "${ip_version} need to update"
        return 0
    fi
    return 1
}

update() {
    local ip_version="$1"
    if [[ "$ip_version" == "ipv4" ]]; then
        local ip_pattern="${ipv4_pattern}"
    elif [[ "$ip_version" == "ipv6" ]]; then
        local ip_pattern="${ipv6_pattern}"
    else
        log "unknown update ip version"
        exit 1
    fi
    local fastest_ip_info="$(test_fastest_ip "${ip_version}")"
    local fastest_ip="$(format_ip_from_test_result "${fastest_ip_info}")"
    if [[ -z "${fastest_ip}" ]]; then
        log "acceptable ${ip_version} ip not found"
    else
        local old_ip="$(sed -n -E "s/^.*?black_hole.*?\b(${ip_pattern}).*?${TAG_STRING}.*$/\1/p" "${mosdns_config_file}")"
        if [[ -z "${old_ip}" ]]; then
            sed -i.backup -E "s/(\s?)${TAG_STRING}/\1${fastest_ip} ${TAG_STRING}/" "${mosdns_config_file}"
        else
            local old_ip_pattern="$(echo "${old_ip}" | sed -E "s/\./\./")"
            sed -i.backup -E "s/${old_ip_pattern}(.*?${TAG_STRING})/${fastest_ip}\1/" "${mosdns_config_file}"
        fi
        if [ $? -ne 0 ]; then
            log "update ${ip_version} to mosdns config error"
            exit 1
        fi
        log "update to ${fastest_ip}"
    fi
}

make_sure_mosdns_config_file_right() {
    if [[ ! -f "${mosdns_config_file}" ]]; then
        log "mosdns config file not found"
        exit 1
    fi
    local reg_result="$(sed -n -E "/black_hole.*?${TAG_STRING}/p" "${mosdns_config_file}")"
    if [[ -z "${reg_result}" ]]; then
        log "mosdns config file not found black_hole and tag"
        exit 1
    fi
    log "mosdns config file :${mosdns_config_file}"
    local ip_pattern="(((${ipv4_pattern})|(${ipv6_pattern}))\s+)*((${ipv4_pattern})|(${ipv6_pattern}))"
    local reg_result="$(sed -n -E "s/^.*black_hole\s+((${ip_pattern})|\s)\s*${TAG_STRING}/\1/p" "${mosdns_config_file}")"
    if [[ -z "${reg_result}" ]]; then
        log "black_hole ip format is not right or empty,now clean all of them"
        sed -i.backup -E "s/(^.*?black_hole).*?(${TAG_STRING}.*$)/\1 \2/" "${mosdns_config_file}"
    fi
}

root_dir="$(cd "$(dirname "$0")" && pwd)"
cd "${root_dir}"
config
log "update Cloudflare CDN fastest IP start"
log "pwd:$(pwd)"

is_restart_mosdns=1
make_sure_mosdns_config_file_right
is_need_update "ipv4"
if [[ $? -eq 0 ]]; then
    update "ipv4"
    is_restart_mosdns=0
fi

is_need_update "ipv6"
if [[ $? -eq 0 ]]; then
    update "ipv6"
    is_restart_mosdns=0
fi

if [[ ${is_restart_mosdns} -eq 0 ]]; then
    bash -c "${restart_mosdns_cmd}"
    if [ $? -ne 0 ]; then
        log "restart mosdns error,check the resatart command"
        log "restart command: ${restart_mosdns_cmd}"
        exit 1
    fi
    log "restart mosdns success"
    log "update Cloudflare CDN fastest IP finished"
    exit 0
fi

log "no need to update"
log "update Cloudflare CDN fastest IP finished"
