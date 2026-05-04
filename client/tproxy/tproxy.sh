#!/bin/sh
export PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH
export TZ=Europe/Moscow

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
# Version (use YY.MM.DD format)
readonly SCRIPT_VERSION="v27.01.02"

# Configuration (modify as needed)

# Proxy core configuration
# Proxy running user and group
readonly DEFAULT_CORE_USER_GROUP="root:net_admin"
# Proxy traffic mark
readonly DEFAULT_ROUTING_MARK=""
readonly DEFAULT_FORCE_MARK_BYPASS=0
# Proxy ports (transparent proxy listening ports)
readonly DEFAULT_PROXY_TCP_PORT="1536"
readonly DEFAULT_PROXY_UDP_PORT="1536"

# Proxy mode: TPROXY (preferred, preserves original source IP/port)
readonly DEFAULT_PROXY_MODE=1

# Performance mode (0=normal, 1=performance optimized)
# When enabled, may enable some features (e.g. conntrack) for better speed
readonly DEFAULT_PERFORMANCE_MODE=0

# DNS configuration
# DNS hijack method (0: disabled, 1: tproxy, 2: redirect)
readonly DEFAULT_DNS_HIJACK_ENABLE=1
# DNS listening port
readonly DEFAULT_DNS_PORT="1053"

# Interface definitions
# Mobile data interface
readonly DEFAULT_MOBILE_INTERFACE="rmnet_data+"
# WiFi interface
readonly DEFAULT_WIFI_INTERFACE="wlan0"
# Hotspot interface
readonly DEFAULT_HOTSPOT_INTERFACE="wlan2"
# USB tethering interface
readonly DEFAULT_USB_INTERFACE="rndis+"

# Other interfaces that require bypassing or proxying. Multiple interfaces can be separated by spaces
readonly DEFAULT_OTHER_BYPASS_INTERFACES=""
readonly DEFAULT_OTHER_PROXY_INTERFACES=""

# Proxy switches
readonly DEFAULT_PROXY_MOBILE=1
readonly DEFAULT_PROXY_WIFI=1
readonly DEFAULT_PROXY_HOTSPOT=0
readonly DEFAULT_PROXY_USB=0
readonly DEFAULT_PROXY_TCP=1
readonly DEFAULT_PROXY_UDP=1

# IPv6 proxy control:
#  0 = disable proxy (but IPv6 stack remains active)
#  1 = enable proxy (normal IPv6 proxy)
# -1 = force disable IPv6 stack entirely (disable_ipv6=1 on all interfaces)
readonly DEFAULT_PROXY_IPV6=0

# The use of 100.0.0.0/8 instead of 100.64.0.0/10 is purely due to a mistake by China Telecom's service provider, and you can change it back
readonly DEFAULT_BYPASS_IPv4_LIST="0.0.0.0/8 10.0.0.0/8 100.0.0.0/8 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.88.99.0/24 192.168.0.0/16 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4 255.255.255.255/32"
readonly DEFAULT_BYPASS_IPv6_LIST="::/128 ::1/128 ::ffff:0:0/96 100::/64 64:ff9b::/96 2001::/32 2001:10::/28 2001:20::/28 2001:db8::/32 2002::/16 fe80::/10 ff00::/8 fd00::/8"
readonly DEFAULT_PROXY_IPv4_LIST=""
readonly DEFAULT_PROXY_IPv6_LIST=""

# Hotspot subnet when WiFi and hotspot share the same interface (common on older devices)
# Only used when HOTSPOT_INTERFACE == WIFI_INTERFACE
readonly DEFAULT_HOTSPOT_SUBNET_IPV4="192.168.43.0/24"
readonly DEFAULT_HOTSPOT_SUBNET_IPV6="fe80::/10"

# Mark values
readonly DEFAULT_MARK_VALUE=20
readonly DEFAULT_MARK_VALUE6=25

# Routing table ID
readonly DEFAULT_TABLE_ID=2025

# Per-app proxy (use space to separate package names, supports user:package format)
readonly DEFAULT_APP_PROXY_ENABLE=0
readonly DEFAULT_PROXY_APPS_LIST=""
# Example: "com.example.app com.other"
readonly DEFAULT_BYPASS_APPS_LIST=""
# Example: "com.android.shell"
readonly DEFAULT_APP_PROXY_MODE="blacklist"
# "blacklist" or "whitelist"

# RU IP bypass configuration
readonly DEFAULT_BYPASS_RU_IP=0
# RU IP list file name
readonly DEFAULT_RU_IP_FILE="ru.zone"
readonly DEFAULT_RU_IPV6_FILE="ru_ipv6.zone"
# RU IP source URLs
readonly DEFAULT_RU_IP_URL="https://raw.githubusercontent.com/ipverse/country-ip-blocks/master/country/ru/ipv4-aggregated.txt"
readonly DEFAULT_RU_IPV6_URL="https://raw.githubusercontent.com/ipverse/country-ip-blocks/master/country/ru/ipv6-aggregated.txt"

# MAC address blacklist/whitelist configuration (hotspot mode)
readonly DEFAULT_MAC_FILTER_ENABLE=0
# MAC address blacklist/whitelist (use space to separate MAC addresses)
readonly DEFAULT_PROXY_MACS_LIST=""
# Example: "AA:BB:CC:DD:EE:FF 11:22:33:44:55:66"
readonly DEFAULT_BYPASS_MACS_LIST=""
# Example: "FF:EE:DD:CC:BB:AA"
readonly DEFAULT_MAC_PROXY_MODE="blacklist"
# "blacklist" or "whitelist"

# block quic
readonly DEFAULT_BLOCK_QUIC=0

# Whether to include timestamp in logs (0=disable, 1=enable)
# Disabling this can improve performance by avoiding a process fork for each log entry.
readonly DEFAULT_LOG_TIMESTAMP=1

# Dry-run mode (disabled by default)
readonly DEFAULT_DRY_RUN=0

log() {
    local level="$1"
    local message="$2"
    local color_code

    case "$level" in
        Debug) color_code="\033[0;36m" ;;
        Info) color_code="\033[1;32m" ;;
        Warn) color_code="\033[1;33m" ;;
        Error) color_code="\033[1;31m" ;;
        *)
            level="Unknown"
            color_code="\033[0m"
            ;;
    esac

    local should_print=0

    if [ "$DRY_RUN" -eq 1 ]; then
        if [ "$VERBOSE" -eq 1 ]; then
            should_print=1
        elif [ "$level" = "Debug" ] && case "$message" in "[EXEC] "*) true ;; *) false ;; esac then
            should_print=1
        fi
    else
        if [ "$level" = "Info" ] || [ "$level" = "Warn" ] || [ "$level" = "Error" ]; then
            should_print=1
        elif [ "$VERBOSE" -eq 1 ] && [ "$level" = "Debug" ]; then
            should_print=1
        fi
    fi

    [ "$should_print" -eq 0 ] && return 0

    local timestamp=""
    if [ "$LOG_TIMESTAMP" -eq 1 ]; then
        timestamp="$(date +"%Y-%m-%d %H:%M:%S") "
    fi

    if [ -t 2 ]; then
        printf "%b\n" "${color_code}${timestamp}[${level}]: ${message}\033[0m" >&2
    else
        printf "%s\n" "${timestamp}[${level}]: ${message}" >&2
    fi
}

load_config() {
    if [ -z "$CONFIG_DIR" ]; then
        CONFIG_DIR="$SCRIPT_DIR"
        log Warn "CONFIG_DIR not specified, fallback to script directory: $CONFIG_DIR"
    fi

    if [ -f "$CONFIG_DIR/tproxy.conf" ]; then
        log Info "Sourcing configuration file: $CONFIG_DIR/tproxy.conf"
        . "$CONFIG_DIR/tproxy.conf"
    else
        log Info "No tproxy.conf found in $CONFIG_DIR, using script defaults + environment variables"
    fi

    log Info "Loading configuration from environment or defaults..."

    DRY_RUN="${DRY_RUN:-$DEFAULT_DRY_RUN}"
    CORE_USER_GROUP="${CORE_USER_GROUP:-$DEFAULT_CORE_USER_GROUP}"
    ROUTING_MARK="${ROUTING_MARK:-$DEFAULT_ROUTING_MARK}"
    FORCE_MARK_BYPASS="${FORCE_MARK_BYPASS:-$DEFAULT_FORCE_MARK_BYPASS}"
    PROXY_TCP_PORT="${PROXY_TCP_PORT:-$DEFAULT_PROXY_TCP_PORT}"
    PROXY_UDP_PORT="${PROXY_UDP_PORT:-$DEFAULT_PROXY_UDP_PORT}"
    PROXY_MODE="${PROXY_MODE:-$DEFAULT_PROXY_MODE}"
    PERFORMANCE_MODE="${PERFORMANCE_MODE:-$DEFAULT_PERFORMANCE_MODE}"
    DNS_HIJACK_ENABLE="${DNS_HIJACK_ENABLE:-$DEFAULT_DNS_HIJACK_ENABLE}"
    DNS_PORT="${DNS_PORT:-$DEFAULT_DNS_PORT}"
    MOBILE_INTERFACE="${MOBILE_INTERFACE:-$DEFAULT_MOBILE_INTERFACE}"
    WIFI_INTERFACE="${WIFI_INTERFACE:-$DEFAULT_WIFI_INTERFACE}"
    HOTSPOT_INTERFACE="${HOTSPOT_INTERFACE:-$DEFAULT_HOTSPOT_INTERFACE}"
    USB_INTERFACE="${USB_INTERFACE:-$DEFAULT_USB_INTERFACE}"
    OTHER_BYPASS_INTERFACES="${OTHER_BYPASS_INTERFACES:-$DEFAULT_OTHER_BYPASS_INTERFACES}"
    OTHER_PROXY_INTERFACES="${OTHER_PROXY_INTERFACES:-$DEFAULT_OTHER_PROXY_INTERFACES}"
    PROXY_MOBILE="${PROXY_MOBILE:-$DEFAULT_PROXY_MOBILE}"
    PROXY_WIFI="${PROXY_WIFI:-$DEFAULT_PROXY_WIFI}"
    PROXY_HOTSPOT="${PROXY_HOTSPOT:-$DEFAULT_PROXY_HOTSPOT}"
    PROXY_USB="${PROXY_USB:-$DEFAULT_PROXY_USB}"
    PROXY_TCP="${PROXY_TCP:-$DEFAULT_PROXY_TCP}"
    PROXY_UDP="${PROXY_UDP:-$DEFAULT_PROXY_UDP}"
    PROXY_IPV6="${PROXY_IPV6:-$DEFAULT_PROXY_IPV6}"
    MARK_VALUE="${MARK_VALUE:-$DEFAULT_MARK_VALUE}"
    MARK_VALUE6="${MARK_VALUE6:-$DEFAULT_MARK_VALUE6}"
    TABLE_ID="${TABLE_ID:-$DEFAULT_TABLE_ID}"
    PROXY_IPv4_LIST="${PROXY_IPv4_LIST:-$DEFAULT_PROXY_IPv4_LIST}"
    PROXY_IPv6_LIST="${PROXY_IPv6_LIST:-$DEFAULT_PROXY_IPv6_LIST}"
    BYPASS_IPv4_LIST="${BYPASS_IPv4_LIST:-$DEFAULT_BYPASS_IPv4_LIST}"
    BYPASS_IPv6_LIST="${BYPASS_IPv6_LIST:-$DEFAULT_BYPASS_IPv6_LIST}"
    HOTSPOT_SUBNET_IPV4="${HOTSPOT_SUBNET_IPV4:-$DEFAULT_HOTSPOT_SUBNET_IPV4}"
    HOTSPOT_SUBNET_IPV6="${HOTSPOT_SUBNET_IPV6:-$DEFAULT_HOTSPOT_SUBNET_IPV6}"
    APP_PROXY_ENABLE="${APP_PROXY_ENABLE:-$DEFAULT_APP_PROXY_ENABLE}"
    PROXY_APPS_LIST="${PROXY_APPS_LIST:-$DEFAULT_PROXY_APPS_LIST}"
    BYPASS_APPS_LIST="${BYPASS_APPS_LIST:-$DEFAULT_BYPASS_APPS_LIST}"
    APP_PROXY_MODE="${APP_PROXY_MODE:-$DEFAULT_APP_PROXY_MODE}"
    BYPASS_RU_IP="${BYPASS_RU_IP:-$DEFAULT_BYPASS_RU_IP}"
    RU_IP_FILE="${RU_IP_FILE:-$DEFAULT_RU_IP_FILE}"
    RU_IPV6_FILE="${RU_IPV6_FILE:-$DEFAULT_RU_IPV6_FILE}"
    RU_IP_URL="${RU_IP_URL:-$DEFAULT_RU_IP_URL}"
    RU_IPV6_URL="${RU_IPV6_URL:-$DEFAULT_RU_IPV6_URL}"
    MAC_FILTER_ENABLE="${MAC_FILTER_ENABLE:-$DEFAULT_MAC_FILTER_ENABLE}"
    PROXY_MACS_LIST="${PROXY_MACS_LIST:-$DEFAULT_PROXY_MACS_LIST}"
    BYPASS_MACS_LIST="${BYPASS_MACS_LIST:-$DEFAULT_BYPASS_MACS_LIST}"
    MAC_PROXY_MODE="${MAC_PROXY_MODE:-$DEFAULT_MAC_PROXY_MODE}"
    BLOCK_QUIC="${BLOCK_QUIC:-$DEFAULT_BLOCK_QUIC}"
    LOG_TIMESTAMP="${LOG_TIMESTAMP:-$DEFAULT_LOG_TIMESTAMP}"
    SKIP_CHECK_FEATURE="${SKIP_CHECK_FEATURE:-0}"

    if [ "$VERBOSE" -eq 1 ]; then
        for _var in DRY_RUN CORE_USER_GROUP ROUTING_MARK FORCE_MARK_BYPASS \
            PROXY_TCP_PORT PROXY_UDP_PORT PROXY_MODE PERFORMANCE_MODE \
            DNS_HIJACK_ENABLE DNS_PORT \
            MOBILE_INTERFACE WIFI_INTERFACE HOTSPOT_INTERFACE USB_INTERFACE \
            OTHER_BYPASS_INTERFACES OTHER_PROXY_INTERFACES \
            PROXY_MOBILE PROXY_WIFI PROXY_HOTSPOT PROXY_USB \
            PROXY_TCP PROXY_UDP PROXY_IPV6 \
            MARK_VALUE MARK_VALUE6 TABLE_ID \
            PROXY_IPv4_LIST PROXY_IPv6_LIST BYPASS_IPv4_LIST BYPASS_IPv6_LIST \
            HOTSPOT_SUBNET_IPV4 HOTSPOT_SUBNET_IPV6 \
            APP_PROXY_ENABLE PROXY_APPS_LIST BYPASS_APPS_LIST APP_PROXY_MODE \
            BYPASS_RU_IP RU_IP_FILE RU_IPV6_FILE RU_IP_URL RU_IPV6_URL \
            MAC_FILTER_ENABLE PROXY_MACS_LIST BYPASS_MACS_LIST MAC_PROXY_MODE \
            BLOCK_QUIC LOG_TIMESTAMP SKIP_CHECK_FEATURE; do
            eval "log Debug \"$_var: \$$_var\""
        done
    fi

    log Info "Configuration loading completed"
}

save_runtime_config() {
    if [ "$DRY_RUN" -eq 1 ]; then
        log Debug "Skip saving runtime config"
        return 0
    fi

    local runtime_file="$CONFIG_DIR/runtime_tproxy.conf"
    log Info "Saving runtime config to $runtime_file"

    {
        echo "# Runtime config slice for stop/cleanup only (generated at $(date))"
        echo "CONFIG_DIR=$CONFIG_DIR"
        echo "CORE_USER_GROUP=$CORE_USER_GROUP"
        echo "PROXY_TCP=$PROXY_TCP"
        echo "PROXY_UDP=$PROXY_UDP"
        echo "PROXY_IPV6=$PROXY_IPV6"
        echo "PROXY_MODE=$PROXY_MODE"
        echo "OTHER_PROXY_INTERFACES=$OTHER_PROXY_INTERFACES"
        echo "BYPASS_RU_IP=$BYPASS_RU_IP"
        echo "BLOCK_QUIC=$BLOCK_QUIC"
        echo "DNS_HIJACK_ENABLE=$DNS_HIJACK_ENABLE"
        echo "TABLE_ID=$TABLE_ID"
        echo "MARK_VALUE=$MARK_VALUE"
        echo "MARK_VALUE6=$MARK_VALUE6"
        echo "USE_TPROXY=$USE_TPROXY"
    } > "$runtime_file" || {
        log Warn "Failed to save runtime config to $runtime_file"
    }
}

load_runtime_config() {
    if [ "$DRY_RUN" -eq 1 ]; then
        log Debug "Skip loading runtime config"
        return 0
    fi

    local runtime_file="$CONFIG_DIR/runtime_tproxy.conf"
    if [ -f "$runtime_file" ]; then
        log Info "Loading runtime config from $runtime_file for cleanup"
        . "$runtime_file" || {
            log Warn "Failed to load runtime config from $runtime_file, using current config"
            return 1
        }
    else
        log Warn "No runtime config found at $runtime_file, using current config for cleanup"
        return 1
    fi
}

init_tmpdir() {
    for d in /tmp /data/local/tmp "$CONFIG_DIR/tmp"; do
        if [ -d "$d" ] && [ -w "$d" ]; then
            export TMPDIR="$d"
            log Debug "Using TMPDIR: $TMPDIR"
            return 0
        fi
    done

    if mkdir -p "$CONFIG_DIR/tmp" 2> /dev/null && [ -w "$CONFIG_DIR/tmp" ]; then
        export TMPDIR="$CONFIG_DIR/tmp"
        log Debug "Created fallback TMPDIR: $TMPDIR"
        return 0
    else
        log Error "Failed to find or create writable TMPDIR"
        exit 1
    fi
}


init_kernel_config_cache() {
    [ "$DRY_RUN" -eq 1 ] && return 0
    [ "$SKIP_CHECK_FEATURE" = "1" ] && return 0

    if [ -f /proc/config.gz ]; then
        if zcat /proc/config.gz > "$TMPDIR/kernel_config.cache" 2> /dev/null; then
            log Debug "Kernel config cached to $TMPDIR/kernel_config.cache"
        else
            log Warn "Failed to cache /proc/config.gz"
            rm -f "$TMPDIR/kernel_config.cache" 2> /dev/null
        fi
    fi
}
# Helper: validate a value is a positive integer (zero forks)
is_positive_integer() {
    case "$1" in
        '' | *[!0-9]*) return 1 ;;
    esac
    return 0
}

validate_config() {
    log Debug "Validating configuration..."

    if ! is_positive_integer "$PROXY_TCP_PORT" || [ "$PROXY_TCP_PORT" -lt 1 ] || [ "$PROXY_TCP_PORT" -gt 65535 ]; then
        log Error "Invalid PROXY_TCP_PORT: $PROXY_TCP_PORT"
        return 1
    fi

    if ! is_positive_integer "$PROXY_UDP_PORT" || [ "$PROXY_UDP_PORT" -lt 1 ] || [ "$PROXY_UDP_PORT" -gt 65535 ]; then
        log Error "Invalid PROXY_UDP_PORT: $PROXY_UDP_PORT"
        return 1
    fi

    case "$PROXY_MODE" in
        0 | 1) ;;
        *)
            log Error "Invalid PROXY_MODE: $PROXY_MODE (must be 0=auto, 1=force TPROXY)"
            return 1
            ;;
    esac

    case "$DNS_HIJACK_ENABLE" in
        0 | 1) ;;
        *)
            log Error "Invalid DNS_HIJACK_ENABLE: $DNS_HIJACK_ENABLE (must be 0=disabled, 1=tproxy)"
            return 1
            ;;
    esac

    if ! is_positive_integer "$DNS_PORT" || [ "$DNS_PORT" -lt 1 ] || [ "$DNS_PORT" -gt 65535 ]; then
        log Error "Invalid DNS_PORT: $DNS_PORT"
        return 1
    fi

    if ! is_positive_integer "$MARK_VALUE" || [ "$MARK_VALUE" -lt 1 ] || [ "$MARK_VALUE" -gt 2147483647 ]; then
        log Error "Invalid MARK_VALUE: $MARK_VALUE"
        return 1
    fi

    if ! is_positive_integer "$MARK_VALUE6" || [ "$MARK_VALUE6" -lt 1 ] || [ "$MARK_VALUE6" -gt 2147483647 ]; then
        log Error "Invalid MARK_VALUE6: $MARK_VALUE6"
        return 1
    fi

    if ! is_positive_integer "$TABLE_ID" || [ "$TABLE_ID" -lt 1 ] || [ "$TABLE_ID" -gt 65535 ]; then
        log Error "Invalid TABLE_ID: $TABLE_ID"
        return 1
    fi

    case "$CORE_USER_GROUP" in
        *:*)
            CORE_USER="${CORE_USER_GROUP%%:*}"
            CORE_GROUP="${CORE_USER_GROUP#*:}"
            log Debug "Parsed user:group as '$CORE_USER:$CORE_GROUP'"
            ;;
    esac

    if [ -z "$CORE_USER" ] || [ -z "$CORE_GROUP" ]; then
        log Warn "Empty user or group detected, Using default user:group 'root:net_admin'"
        CORE_USER="root"
        CORE_GROUP="net_admin"
    fi

    case "$APP_PROXY_MODE" in
        blacklist | whitelist) ;;
        *)
            log Error "Invalid APP_PROXY_MODE: $APP_PROXY_MODE"
            return 1
            ;;
    esac

    case "$MAC_PROXY_MODE" in
        blacklist | whitelist) ;;
        *)
            log Error "Invalid MAC_PROXY_MODE: $MAC_PROXY_MODE"
            return 1
            ;;
    esac

    log Debug "Configuration validation passed"
    return 0
}

check_root() {
    if [ "$DRY_RUN" -eq 1 ]; then
        log Debug "Skip root check"
        return 0
    fi
    if [ "$(id -u 2> /dev/null || echo 1)" != "0" ]; then
        log Error "Must run with root privileges"
        exit 1
    fi
}

check_kernel_feature() {
    local feature="$1"
    local config_name="CONFIG_${feature}"
    local ipt_name=""

    # 1. Mapping Configuration to iptables/Netfilter internal names
    case "$feature" in
        NETFILTER_XT_TARGET_TPROXY)   ipt_name="TPROXY" ;;
        NETFILTER_XT_MATCH_CONNTRACK) ipt_name="conntrack" ;;
        NETFILTER_XT_MATCH_OWNER)     ipt_name="owner" ;;
        NETFILTER_XT_MATCH_MARK)      ipt_name="mark" ;;
        NETFILTER_XT_TARGET_MARK)     ipt_name="MARK" ;;
        NETFILTER_XT_MATCH_SOCKET)    ipt_name="socket" ;;
        NETFILTER_XT_MATCH_ADDRTYPE)  ipt_name="addrtype" ;;
        NETFILTER_XT_MATCH_MAC)       ipt_name="mac" ;;
        IP_SET)                       ipt_name="set" ;;
        NETFILTER_XT_SET)             ipt_name="set" ;;
    esac

    # 2. Check /proc/net (Fast check for active functions, GKI 5.10+)
    if [ -n "$ipt_name" ]; then
        if grep -qE "(^|[[:space:]])${ipt_name}([[:space:]]|$)" \
            /proc/net/ip_tables_matches /proc/net/ip_tables_targets /proc/net/ip_tables_names \
            /proc/net/ip6_tables_matches /proc/net/ip6_tables_targets /proc/net/ip6_tables_names 2>/dev/null; then
            log Info "Feature [$feature] detected via /proc/net"
            return 0
        fi
    fi

    # 3. Trigger lazy loading
    if [ "$ipt_name" = "nat" ]; then
        if ip6tables -w 100 -t nat -L -n >/dev/null 2>&1; then
            log Info "Feature [$feature] detected via iptables"
            return 0
        fi
    elif [ -n "$ipt_name" ]; then
        iptables -w 100 -m "$ipt_name" --help >/dev/null 2>&1 || iptables -w 100 -j "$ipt_name" --help >/dev/null 2>&1
        if grep -qE "(^|[[:space:]])${ipt_name}([[:space:]]|$)" \
            /proc/net/ip_tables_matches /proc/net/ip_tables_targets /proc/net/ip_tables_names \
            /proc/net/ip6_tables_matches /proc/net/ip6_tables_targets /proc/net/ip6_tables_names 2>/dev/null; then
            log Info "Feature [$feature] detected via lazy-loading"
            return 0
        fi
    fi

    # 4. Check compile-time config (Critical for legacy 4.14 kernels and built-in features)
    if [ -f "$TMPDIR/kernel_config.cache" ]; then
        if grep -qE "^${config_name}=[ym]$" "$TMPDIR/kernel_config.cache" 2> /dev/null; then
            log Info "Feature [$feature] detected via kernel config"
            return 0
        fi
    fi

    log Warn "Kernel feature [$feature] is disabled or not found"
    return 1
}

init_feature_flags() {
    if [ "$SKIP_CHECK_FEATURE" = "1" ] || [ "$DRY_RUN" -eq 1 ]; then
        log Warn "Kernel feature check skipped"
        HAS_TPROXY=1
        HAS_CONNTRACK=1
        HAS_OWNER=1
        HAS_MARK_MT=1
        HAS_MARK_TG=1
        HAS_SOCKET=1
        HAS_ADDRTYPE=1
        HAS_MAC=1
        HAS_IPSET=1
        HAS_XT_SET=1
        return 0
    fi

    log Info "Detecting kernel features..."
    check_kernel_feature "NETFILTER_XT_TARGET_TPROXY" && HAS_TPROXY=1
    check_kernel_feature "NETFILTER_XT_MATCH_CONNTRACK" && HAS_CONNTRACK=1
    check_kernel_feature "NETFILTER_XT_MATCH_OWNER" && HAS_OWNER=1
    check_kernel_feature "NETFILTER_XT_MATCH_MARK" && HAS_MARK_MT=1
    check_kernel_feature "NETFILTER_XT_TARGET_MARK" && HAS_MARK_TG=1
    check_kernel_feature "NETFILTER_XT_MATCH_SOCKET" && HAS_SOCKET=1
    check_kernel_feature "NETFILTER_XT_MATCH_ADDRTYPE" && HAS_ADDRTYPE=1
    check_kernel_feature "NETFILTER_XT_MATCH_MAC" && HAS_MAC=1
    check_kernel_feature "IP_SET" && HAS_IPSET=1
    check_kernel_feature "NETFILTER_XT_SET" && HAS_XT_SET=1
}

check_tproxy_support() {
    if [ "$DRY_RUN" -eq 1 ]; then
        log Debug "TPROXY support check skipped"
        return 0
    fi

    if [ "$HAS_TPROXY" -eq 1 ]; then
        log Info "Kernel TPROXY support confirmed"
        return 0
    else
        log Warn "Kernel TPROXY support not available"
        return 1
    fi
}

# Unified command wrapper functions
run_ipt_command() {
    local cmd="$1"
    shift

    log Debug "[EXEC] $cmd -w 100 $*"

    [ "$DRY_RUN" -eq 1 ] && return 0

    command "$cmd" -w 100 "$@"
}

iptables() {
    run_ipt_command iptables "$@"
}

ip6tables() {
    run_ipt_command ip6tables "$@"
}

ip_rule() {
    log Debug "[EXEC] ip rule $*"
    [ "$DRY_RUN" -eq 1 ] && return 0
    command ip rule "$@"
}

ip6_rule() {
    log Debug "[EXEC] ip -6 rule $*"
    [ "$DRY_RUN" -eq 1 ] && return 0
    command ip -6 rule "$@"
}

ip_route() {
    log Debug "[EXEC] ip route $*"
    [ "$DRY_RUN" -eq 1 ] && return 0
    command ip route "$@"
}

ip6_route() {
    log Debug "[EXEC] ip -6 route $*"
    [ "$DRY_RUN" -eq 1 ] && return 0
    command ip -6 route "$@"
}

find_packages_uid() {
    [ $# -eq 0 ] && return 0

    awk -v tokens="$*" '
    BEGIN {
        n = split(tokens, t_arr, " ")
        for (i = 1; i <= n; i++) {
            t = t_arr[i]
            if (t ~ /:/) {
                split(t, parts, ":")
                pfx = parts[1]; pkg = parts[2]
            } else {
                pfx = 0; pkg = t
            }
            # Record that we want this package and store its prefix(es)
            wanted[pkg] = 1
            # Multiple prefixes might exist for the same package
            pfxs[pkg] = (pkg in pfxs) ? pfxs[pkg] " " pfx : pfx
        }
    }
    ($1 in wanted) {
        base_uid = ""
        if ($2 ~ /^[0-9]+$/) base_uid = $2
        else if ($(NF-1) ~ /^[0-9]+$/) base_uid = $(NF-1)

        if (base_uid != "") {
            m = split(pfxs[$1], p_arr, " ")
            for (j = 1; j <= m; j++) {
                # Store result keyed by package and prefix to preserve order later
                res[$1, p_arr[j]] = (p_arr[j] * 100000 + base_uid)
            }
        }
    }
    END {
        final_out = ""
        for (i = 1; i <= n; i++) {
            t = t_arr[i]
            if (t ~ /:/) {
                split(t, parts, ":")
                pfx = parts[1]; pkg = parts[2]
            } else {
                pfx = 0; pkg = t
            }

            if ((pkg, pfx) in res) {
                final_out = (final_out == "") ? res[pkg, pfx] : final_out " " res[pkg, pfx]
            }
        }
        print final_out
    }
    ' /data/system/packages.list
}

safe_chain_create() {
    local family="$1"
    local table="$2"
    local chain="$3"
    local cmd="iptables"

    [ "$family" = "6" ] && cmd="ip6tables"

    $cmd -t "$table" -N "$chain" 2> /dev/null || true
    $cmd -t "$table" -F "$chain"
}

download_file() {
    local url="$1"
    local output="$2"

    if [ "$DRY_RUN" -eq 1 ]; then
        log Debug "[EXEC] download $url -> $output (skipped, dry-run)"
        return 0
    fi

    if command -v curl > /dev/null 2>&1; then
        log Debug "[EXEC] curl -fsSL --connect-timeout 10 --retry 3 $url -o $output"
        curl -fsSL --connect-timeout 10 --retry 3 "$url" -o "$output"
    elif command -v busybox > /dev/null 2>&1; then
        log Debug "[EXEC] busybox wget -q -T 10 -t 3 -O $output $url"
        busybox wget -q -T 10 -t 3 -O "$output" "$url"
    else
        log Error "No curl or busybox found for downloading"
        return 1
    fi
}

download_ru_ip_list() {
    if [ "$BYPASS_RU_IP" -eq 0 ]; then
        log Debug "RU IP bypass is disabled, download skipped"
        return 0
    fi

    log Info "Checking/Downloading Russia IP list to $CONFIG_DIR/$RU_IP_FILE"

    # Re-download if file doesn't exist or is older than 7 days
    if [ ! -f "$CONFIG_DIR/$RU_IP_FILE" ] || [ "$(find "$CONFIG_DIR/$RU_IP_FILE" -mtime +7 2> /dev/null)" ]; then
        log Info "Fetching latest Russia IP list from $RU_IP_URL"

        if ! download_file "$RU_IP_URL" "$CONFIG_DIR/$RU_IP_FILE.tmp"; then
            log Error "Failed to download Russia IP list"
            log Debug "[EXEC] rm -f $CONFIG_DIR/$RU_IP_FILE.tmp"
            rm -f "$CONFIG_DIR/$RU_IP_FILE.tmp"
            return 1
        fi

        log Debug "[EXEC] mv $CONFIG_DIR/$RU_IP_FILE.tmp $CONFIG_DIR/$RU_IP_FILE"
        if [ "$DRY_RUN" -eq 0 ]; then
            mv "$CONFIG_DIR/$RU_IP_FILE.tmp" "$CONFIG_DIR/$RU_IP_FILE"
        fi
        log Info "Russia IP list saved to $CONFIG_DIR/$RU_IP_FILE"
    else
        log Debug "Using existing Russia IP list: $CONFIG_DIR/$RU_IP_FILE"
    fi

    if [ "$PROXY_IPV6" -eq 1 ]; then
        log Info "Checking/Downloading Russia IPv6 list to $CONFIG_DIR/$RU_IPV6_FILE"

        if [ ! -f "$CONFIG_DIR/$RU_IPV6_FILE" ] || [ "$(find "$CONFIG_DIR/$RU_IPV6_FILE" -mtime +7 2> /dev/null)" ]; then
            log Info "Fetching latest Russia IPv6 list from $RU_IPV6_URL"

            if ! download_file "$RU_IPV6_URL" "$CONFIG_DIR/$RU_IPV6_FILE.tmp"; then
                log Error "Failed to download Russia IPv6 list"
                log Debug "[EXEC] rm -f $CONFIG_DIR/$RU_IPV6_FILE.tmp"
                rm -f "$CONFIG_DIR/$RU_IPV6_FILE.tmp"
                return 1
            fi

            log Debug "[EXEC] mv $CONFIG_DIR/$RU_IPV6_FILE.tmp $CONFIG_DIR/$RU_IPV6_FILE"
            if [ "$DRY_RUN" -eq 0 ]; then
                mv "$CONFIG_DIR/$RU_IPV6_FILE.tmp" "$CONFIG_DIR/$RU_IPV6_FILE"
            fi
            log Info "Russia IPv6 list saved to $CONFIG_DIR/$RU_IPV6_FILE"
        else
            log Debug "Using existing Russia IPv6 list: $CONFIG_DIR/$RU_IPV6_FILE"
        fi
    fi
}

setup_ru_ipset() {
    if [ "$BYPASS_RU_IP" -eq 0 ]; then
        log Debug "RU IP bypass is disabled, ipset setup skipped"
        return 0
    fi

    if ! command -v ipset > /dev/null 2>&1; then
        log Error "ipset command not found. Cannot bypass RU IPs"
        return 1
    fi

    log Info "Setting up ipset for Russia IPs"

    log Debug "[EXEC] ipset destroy ruip"
    log Debug "[EXEC] ipset destroy ruip6"
    if [ "$DRY_RUN" -eq 0 ]; then
        ipset destroy ruip 2> /dev/null || true
        ipset destroy ruip6 2> /dev/null || true
    fi

    local ipv4_count
    local ipv6_count

    if [ -f "$CONFIG_DIR/$RU_IP_FILE" ]; then
        log Debug "Loading IPv4 CIDR from $CONFIG_DIR/$RU_IP_FILE"

        ipv4_count=$(wc -l < "$CONFIG_DIR/$RU_IP_FILE" 2> /dev/null || echo "0")

        log Debug "[EXEC] ipset create ruip hash:net family inet hashsize 8192 maxelem 65536"
        log Debug "[EXEC] Generating temporary ipset restore file with $ipv4_count entries"

        if [ "$DRY_RUN" -eq 0 ]; then
            temp_file=$(mktemp) || {
                log Error "Failed to create temporary file for ipset restore"
                return 1
            }
            {
                echo "create ruip hash:net family inet hashsize 8192 maxelem 65536"
                awk '!/^[[:space:]]*#/ && NF > 0 {printf "add ruip %s\n", $0}' "$CONFIG_DIR/$RU_IP_FILE"
            } > "$temp_file" || {
                log Error "Failed to write to temporary file: $temp_file"
                rm -f "$temp_file"
                return 1
            }
        else
            log Debug "[EXEC] Would create temporary file and add $ipv4_count entries to ruip"
        fi

        log Debug "[EXEC] ipset restore -f \"$temp_file\""

        if [ "$DRY_RUN" -eq 0 ]; then
            if ipset restore -f "$temp_file" 2> /dev/null; then
                log Info "Successfully loaded $ipv4_count IPv4 CIDR entries into ipset 'ruip'"
            else
                log Error "Failed to create ipset 'ruip' or load IPv4 CIDR entries"
                rm -f "$temp_file" 2> /dev/null
                return 1
            fi
            log Debug "[EXEC] rm -f $temp_file"
            rm -f "$temp_file"
        else
            log Debug "[EXEC] Would load $ipv4_count IPv4 CIDR entries via ipset restore"
        fi

    else
        log Error "RU IP file not found: $CONFIG_DIR/$RU_IP_FILE"
        return 1
    fi
    log Info "ipset 'ruip' loaded with Russia IPs"

    if [ "$PROXY_IPV6" -eq 1 ]; then
        if [ -f "$CONFIG_DIR/$RU_IPV6_FILE" ]; then
            log Debug "Loading IPv6 CIDR from $CONFIG_DIR/$RU_IPV6_FILE"

            ipv6_count=$(wc -l < "$CONFIG_DIR/$RU_IPV6_FILE" 2> /dev/null || echo "0")

            log Debug "[EXEC] ipset create ruip6 hash:net family inet6 hashsize 8192 maxelem 65536"
            log Debug "[EXEC] Generating temporary ipset restore file with $ipv6_count entries"

            if [ "$DRY_RUN" -eq 0 ]; then
                temp_file6=$(mktemp) || {
                    log Error "Failed to create temporary file for ipset restore"
                    return 1
                }
                {
                    echo "create ruip6 hash:net family inet6 hashsize 8192 maxelem 65536"
                    awk '!/^[[:space:]]*#/ && NF > 0 {printf "add ruip6 %s\n", $0}' "$CONFIG_DIR/$RU_IPV6_FILE"
                } > "$temp_file6" || {
                    log Error "Failed to write to temporary file: $temp_file6"
                    rm -f "$temp_file6"
                    return 1
                }
            else
                log Debug "[EXEC] Would create temporary file and add $ipv6_count entries to ruip6"
            fi

            log Debug "[EXEC] ipset restore -f \"$temp_file6\""

            if [ "$DRY_RUN" -eq 0 ]; then
                if ipset restore -f "$temp_file6" 2> /dev/null; then
                    log Info "Successfully loaded $ipv6_count IPv6 CIDR entries into ipset 'ruip6'"
                else
                    log Error "Failed to create ipset 'ruip6' or load IPv6 CIDR entries"
                    rm -f "$temp_file6" 2> /dev/null
                    return 1
                fi
                log Debug "[EXEC] rm -f $temp_file6"
                rm -f "$temp_file6"
            else
                log Debug "[EXEC] Would load $ipv6_count IPv6 CIDR entries via ipset restore"
            fi

        else
            log Error "RU IPv6 file not found: $CONFIG_DIR/$RU_IPV6_FILE"
            return 1
        fi

        log Info "ipset 'ruip6' loaded with Russia IPv6 IPs"
    fi
}

# Helper: add sub-chain jump rules with optional performance mode conntrack optimization
# Uses dynamic scoping for $cmd and $table from the calling function
_add_chain_jumps() {
    local parent="$1" perf="$2"
    shift 2
    local target
    for target in "$@"; do
        if [ "$perf" -eq 1 ]; then
            $cmd -t "$table" -A "$parent" -p tcp --syn -j "$target"
            $cmd -t "$table" -A "$parent" -p udp -m conntrack --ctstate NEW,RELATED -j "$target"
        else
            $cmd -t "$table" -A "$parent" -j "$target"
        fi
    done
}

setup_proxy_chain() {
    local family="$1"
    local suffix=""
    local mark="$MARK_VALUE"
    local cmd="iptables"

    if [ "$family" = "6" ]; then
        suffix="6"
        mark="$MARK_VALUE6"
        cmd="ip6tables"
    fi

    log Info "Setting up TPROXY chains for IPv${family}"

    local chains=""
    chains="PROXY_PREROUTING$suffix PROXY_OUTPUT$suffix DIVERT$suffix PROXY_IP$suffix BYPASS_IP$suffix BYPASS_INTERFACE$suffix PROXY_INTERFACE$suffix DNS_HIJACK_PRE$suffix DNS_HIJACK_OUT$suffix APP_CHAIN$suffix MAC_CHAIN$suffix"

    local table="mangle"

    # Create chains
    for c in $chains; do
        safe_chain_create "$family" "$table" "$c"
    done

    if [ "$HAS_MARK_TG" -eq 1 ] && [ "$HAS_SOCKET" -eq 1 ]; then
        $cmd -t "$table" -A DIVERT$suffix -j MARK --set-mark "$mark"
        $cmd -t "$table" -A DIVERT$suffix -j ACCEPT

        $cmd -t "$table" -A "PROXY_PREROUTING$suffix" -p tcp -m socket --transparent -j DIVERT$suffix
    fi

    if [ "$HAS_CONNTRACK" -eq 1 ]; then
        $cmd -t "$table" -A "PROXY_PREROUTING$suffix" -m conntrack --ctdir REPLY -j ACCEPT
        $cmd -t "$table" -A "PROXY_OUTPUT$suffix" -m conntrack --ctdir REPLY -j ACCEPT
        log Info "Added reply connection direction bypass"
    fi

    local bypass_success=0
    if [ "$FORCE_MARK_BYPASS" -eq 1 ] && [ "$HAS_MARK_MT" -eq 1 ] && [ -n "$ROUTING_MARK" ]; then
        $cmd -t "$table" -A "PROXY_PREROUTING$suffix" -m mark --mark "$ROUTING_MARK" -j ACCEPT
        $cmd -t "$table" -A "PROXY_OUTPUT$suffix" -m mark --mark "$ROUTING_MARK" -j ACCEPT
        log Info "Added bypass for marked traffic with core mark $ROUTING_MARK (forced)"
        bypass_success=1
    elif [ "$HAS_OWNER" -eq 1 ]; then
        $cmd -t "$table" -A "PROXY_OUTPUT$suffix" -m owner --uid-owner "$CORE_USER" --gid-owner "$CORE_GROUP" -j ACCEPT
        log Info "Added bypass for core user $CORE_USER:$CORE_GROUP"
        bypass_success=1
    elif [ "$HAS_MARK_MT" -eq 1 ] && [ -n "$ROUTING_MARK" ]; then
        $cmd -t "$table" -A "PROXY_OUTPUT$suffix" -m mark --mark "$ROUTING_MARK" -j ACCEPT
        log Info "Added bypass for marked traffic with core mark $ROUTING_MARK"
        bypass_success=1
    fi
    if [ "$bypass_success" -eq 0 ]; then
        log Error "Core traffic bypass not configured, may cause traffic loop"
    fi

    # Pre-check performance mode with conntrack
    local _perf_ct=0
    if [ "$PERFORMANCE_MODE" -eq 1 ] && [ "$HAS_CONNTRACK" -eq 1 ]; then
        _perf_ct=1
    fi

    _add_chain_jumps "PROXY_PREROUTING$suffix" "$_perf_ct" \
        "PROXY_IP$suffix" "BYPASS_IP$suffix" "PROXY_INTERFACE$suffix" "MAC_CHAIN$suffix" "DNS_HIJACK_PRE$suffix"

    _add_chain_jumps "PROXY_OUTPUT$suffix" "$_perf_ct" \
        "PROXY_IP$suffix" "BYPASS_IP$suffix" "BYPASS_INTERFACE$suffix" "APP_CHAIN$suffix" "DNS_HIJACK_OUT$suffix"

    local subnet4
    local subnet6
    if [ "$family" = "6" ]; then
        if [ -n "$PROXY_IPv6_LIST" ]; then
            for subnet6 in $PROXY_IPv6_LIST; do
                $cmd -t "$table" -A "PROXY_IP$suffix" -d "$subnet6" -j RETURN
            done
            log Info "Added proxy rules for PROXY IPv6 ranges"
        fi
    else
        if [ -n "$PROXY_IPv4_LIST" ]; then
            for subnet4 in $PROXY_IPv4_LIST; do
                $cmd -t "$table" -A "PROXY_IP$suffix" -d "$subnet4" -j RETURN
            done
            log Info "Added proxy rules for PROXY IPv4 ranges"
        fi
    fi

    if [ "$HAS_ADDRTYPE" -eq 1 ]; then
        $cmd -t "$table" -A "BYPASS_IP$suffix" -m addrtype --dst-type LOCAL -p udp ! --dport 53 -j ACCEPT
        $cmd -t "$table" -A "BYPASS_IP$suffix" -m addrtype --dst-type LOCAL ! -p udp -j ACCEPT
        log Info "Added local address type bypass"
    fi

    if [ "$family" = "6" ]; then
        for subnet6 in $BYPASS_IPv6_LIST; do
            $cmd -t "$table" -A "BYPASS_IP$suffix" -d "$subnet6" -p udp ! --dport 53 -j ACCEPT
            $cmd -t "$table" -A "BYPASS_IP$suffix" -d "$subnet6" ! -p udp -j ACCEPT
        done
        log Info "Added bypass rules for BYPASS IPv6 ranges"
    else
        for subnet4 in $BYPASS_IPv4_LIST; do
            $cmd -t "$table" -A "BYPASS_IP$suffix" -d "$subnet4" -p udp ! --dport 53 -j ACCEPT
            $cmd -t "$table" -A "BYPASS_IP$suffix" -d "$subnet4" ! -p udp -j ACCEPT
        done
        log Info "Added bypass rules for BYPASS IPv4 ranges"
    fi

    if [ "$BYPASS_RU_IP" -eq 1 ]; then
        local ipset_name="ruip"
        if [ "$family" = "6" ]; then
            ipset_name="ruip6"
        fi
        if command -v ipset > /dev/null 2>&1 && ipset list "$ipset_name" > /dev/null 2>&1; then
            $cmd -t "$table" -A "BYPASS_IP$suffix" -m set --match-set "$ipset_name" dst -p udp ! --dport 53 -j ACCEPT
            $cmd -t "$table" -A "BYPASS_IP$suffix" -m set --match-set "$ipset_name" dst ! -p udp -j ACCEPT
            log Info "Added ipset-based RU IP bypass rule"
        else
            log Warn "ipset '$ipset_name' not available, skipping RU IP bypass"
        fi
    fi

    log Info "Configuring interface proxy rules"
    $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i lo -j RETURN
    if [ "$PROXY_MOBILE" -eq 1 ]; then
        $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$MOBILE_INTERFACE" -j RETURN
        log Info "Mobile interface $MOBILE_INTERFACE will be proxied"
    else
        $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$MOBILE_INTERFACE" -j ACCEPT
        $cmd -t "$table" -A "BYPASS_INTERFACE$suffix" -o "$MOBILE_INTERFACE" -j ACCEPT
        log Info "Mobile interface $MOBILE_INTERFACE will bypass proxy"
    fi

    local subnet
    if [ "$family" = "6" ]; then
        subnet="$HOTSPOT_SUBNET_IPV6"
    else
        subnet="$HOTSPOT_SUBNET_IPV4"
    fi

    if [ "$HOTSPOT_INTERFACE" = "$WIFI_INTERFACE" ]; then
        if [ "$PROXY_HOTSPOT" -eq 1 ]; then
            $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$HOTSPOT_INTERFACE" -s "$subnet" -j RETURN
            log Info "Hotspot interface $HOTSPOT_INTERFACE will be proxied"
        else
            $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$HOTSPOT_INTERFACE" -s "$subnet" -j ACCEPT
            log Info "Hotspot interface $HOTSPOT_INTERFACE will bypass proxy"
        fi

        if [ "$PROXY_WIFI" -eq 1 ]; then
            $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$WIFI_INTERFACE" ! -s "$subnet" -j RETURN
            log Info "WiFi interface $WIFI_INTERFACE will be proxied"
        else
            $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$WIFI_INTERFACE" ! -s "$subnet" -j ACCEPT
            $cmd -t "$table" -A "BYPASS_INTERFACE$suffix" -o "$WIFI_INTERFACE" -j ACCEPT
            log Info "WiFi interface $WIFI_INTERFACE will bypass proxy"
        fi
    else
        if [ "$PROXY_WIFI" -eq 1 ]; then
            $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$WIFI_INTERFACE" -j RETURN
            log Info "WiFi interface $WIFI_INTERFACE will be proxied"
        else
            $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$WIFI_INTERFACE" -j ACCEPT
            $cmd -t "$table" -A "BYPASS_INTERFACE$suffix" -o "$WIFI_INTERFACE" -j ACCEPT
            log Info "WiFi interface $WIFI_INTERFACE will bypass proxy"
        fi

        if [ "$PROXY_HOTSPOT" -eq 1 ]; then
            $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$HOTSPOT_INTERFACE" -j RETURN
            log Info "Hotspot interface $HOTSPOT_INTERFACE will be proxied"
        else
            $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$HOTSPOT_INTERFACE" -j ACCEPT
            $cmd -t "$table" -A "BYPASS_INTERFACE$suffix" -o "$HOTSPOT_INTERFACE" -j ACCEPT
            log Info "Hotspot interface $HOTSPOT_INTERFACE will bypass proxy"
        fi
    fi

    if [ "$PROXY_USB" -eq 1 ]; then
        $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$USB_INTERFACE" -j RETURN
        log Info "USB interface $USB_INTERFACE will be proxied"
    else
        $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$USB_INTERFACE" -j ACCEPT
        $cmd -t "$table" -A "BYPASS_INTERFACE$suffix" -o "$USB_INTERFACE" -j ACCEPT
        log Info "USB interface $USB_INTERFACE will bypass proxy"
    fi

    local interface
    if [ -n "$OTHER_PROXY_INTERFACES" ]; then
        for interface in $OTHER_PROXY_INTERFACES; do
            $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$interface" -j RETURN
        done
        log Info "Other interface $OTHER_PROXY_INTERFACES will be proxied"
    fi

    if [ -n "$OTHER_BYPASS_INTERFACES" ]; then
        for interface in $OTHER_BYPASS_INTERFACES; do
            $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$interface" -j ACCEPT
            $cmd -t "$table" -A "BYPASS_INTERFACE$suffix" -o "$interface" -j ACCEPT
        done
        log Info "Other interface $OTHER_PROXY_INTERFACES will bypass proxy"
    fi

    log Info "Interface proxy rules configuration completed"

    local mac
    if [ "$MAC_FILTER_ENABLE" -eq 1 ] && [ "$PROXY_HOTSPOT" -eq 1 ] && [ -n "$HOTSPOT_INTERFACE" ]; then
        if [ "$HAS_MAC" -eq 1 ]; then
            log Info "Setting up MAC address filter rules for interface $HOTSPOT_INTERFACE"
            case "$MAC_PROXY_MODE" in
                blacklist)
                    if [ -n "$BYPASS_MACS_LIST" ]; then
                        for mac in $BYPASS_MACS_LIST; do
                            if [ -n "$mac" ]; then
                                $cmd -t "$table" -A "MAC_CHAIN$suffix" -m mac --mac-source "$mac" -i "$HOTSPOT_INTERFACE" -j ACCEPT
                                log Info "Added MAC bypass rule for $mac"
                            fi
                        done
                    else
                        log Warn "MAC blacklist mode enabled but no bypass MACs configured"
                    fi
                    $cmd -t "$table" -A "MAC_CHAIN$suffix" -i "$HOTSPOT_INTERFACE" -j RETURN
                    ;;
                whitelist)
                    if [ -n "$PROXY_MACS_LIST" ]; then
                        for mac in $PROXY_MACS_LIST; do
                            if [ -n "$mac" ]; then
                                $cmd -t "$table" -A "MAC_CHAIN$suffix" -m mac --mac-source "$mac" -i "$HOTSPOT_INTERFACE" -j RETURN
                                log Info "Added MAC proxy rule for $mac"
                            fi
                        done
                    else
                        log Warn "MAC whitelist mode enabled but no proxy MACs configured"
                    fi
                    $cmd -t "$table" -A "MAC_CHAIN$suffix" -i "$HOTSPOT_INTERFACE" -j ACCEPT
                    ;;
            esac
        else
            log Warn "MAC filtering requires NETFILTER_XT_MATCH_MAC kernel feature which is not available"
        fi
    fi

    local uids
    local uid
    if [ "$APP_PROXY_ENABLE" -eq 1 ]; then
        if [ "$HAS_OWNER" -eq 1 ]; then
            log Info "Setting up application filter rules in $APP_PROXY_MODE mode"
            case "$APP_PROXY_MODE" in
                blacklist)
                    if [ -n "$BYPASS_APPS_LIST" ]; then
                        uids=$(find_packages_uid $BYPASS_APPS_LIST)
                        if [ $? -eq 0 ] && [ -n "$uids" ]; then
                            for uid in $uids; do
                                if [ -n "$uid" ]; then
                                    $cmd -t "$table" -A "APP_CHAIN$suffix" -m owner --uid-owner "$uid" -j ACCEPT
                                    log Info "Added bypass for UID $uid"
                                fi
                            done
                        fi
                    else
                        log Warn "App blacklist mode enabled but no bypass apps configured"
                    fi
                    $cmd -t "$table" -A "APP_CHAIN$suffix" -j RETURN
                    ;;
                whitelist)
                    if [ -n "$PROXY_APPS_LIST" ]; then
                        uids=$(find_packages_uid $PROXY_APPS_LIST)
                        if [ $? -eq 0 ] && [ -n "$uids" ]; then
                            for uid in $uids; do
                                if [ -n "$uid" ]; then
                                    $cmd -t "$table" -A "APP_CHAIN$suffix" -m owner --uid-owner "$uid" -j RETURN
                                    log Info "Added proxy for UID $uid"
                                fi
                            done
                        fi
                    else
                        log Warn "App whitelist mode enabled but no proxy apps configured"
                    fi
                    $cmd -t "$table" -A "APP_CHAIN$suffix" -j ACCEPT
                    ;;
            esac
        else
            log Warn "Application filtering requires NETFILTER_XT_MATCH_OWNER kernel feature which is not available"
        fi
    fi

    if [ "$DNS_HIJACK_ENABLE" -ne 0 ]; then
        setup_dns_hijack "$family" "tproxy"
    fi

    if [ "$_perf_ct" -eq 1 ]; then
        $cmd -t "$table" -A "PROXY_PREROUTING$suffix" -m conntrack --ctstate NEW,RELATED -j CONNMARK --set-mark "$mark"
        $cmd -t "$table" -A "PROXY_PREROUTING$suffix" -p tcp -m connmark --mark "$mark" -j TPROXY --on-port "$PROXY_TCP_PORT" --tproxy-mark "$mark"
        $cmd -t "$table" -A "PROXY_PREROUTING$suffix" -p udp -m connmark --mark "$mark" -j TPROXY --on-port "$PROXY_UDP_PORT" --tproxy-mark "$mark"

        $cmd -t "$table" -A "PROXY_OUTPUT$suffix" -m conntrack --ctstate NEW,RELATED -j CONNMARK --set-mark "$mark"
        $cmd -t "$table" -A "PROXY_OUTPUT$suffix" -m connmark --mark "$mark" -j MARK --set-mark "$mark"
        log Info "TPROXY mode rules added"
    else
        $cmd -t "$table" -A "PROXY_PREROUTING$suffix" -p tcp -j TPROXY --on-port "$PROXY_TCP_PORT" --tproxy-mark "$mark"
        $cmd -t "$table" -A "PROXY_PREROUTING$suffix" -p udp -j TPROXY --on-port "$PROXY_UDP_PORT" --tproxy-mark "$mark"
        $cmd -t "$table" -A "PROXY_OUTPUT$suffix" -j MARK --set-mark "$mark"
        log Info "TPROXY mode rules added"
    fi

    # Add rules to main chains
    if [ "$PROXY_UDP" -eq 1 ]; then
        $cmd -t "$table" -I PREROUTING -p udp -j "PROXY_PREROUTING$suffix"
        $cmd -t "$table" -I OUTPUT -p udp -j "PROXY_OUTPUT$suffix"
        log Info "Added UDP rules to PREROUTING and OUTPUT chains"
    fi
    if [ "$PROXY_TCP" -eq 1 ]; then
        $cmd -t "$table" -I PREROUTING -p tcp -j "PROXY_PREROUTING$suffix"
        $cmd -t "$table" -I OUTPUT -p tcp -j "PROXY_OUTPUT$suffix"
        log Info "Added TCP rules to PREROUTING and OUTPUT chains"
    fi

    log Info "TPROXY chains for IPv${family} setup completed"
}

setup_dns_hijack() {
    local family="$1"
    local suffix=""
    local mark="$MARK_VALUE"
    local cmd="iptables"

    if [ "$family" = "6" ]; then
        suffix="6"
        mark="$MARK_VALUE6"
        cmd="ip6tables"
    fi

    $cmd -t mangle -A "DNS_HIJACK_PRE$suffix" -j RETURN
    $cmd -t mangle -A "DNS_HIJACK_OUT$suffix" -j RETURN

    log Info "DNS hijack enabled using TPROXY mode"
}

setup_tproxy_chain4() {
    setup_proxy_chain 4
}

setup_tproxy_chain6() {
    setup_proxy_chain 6
}

setup_routing4() {
    log Info "Setting up routing rules for IPv4"

    ip_rule del fwmark "$MARK_VALUE" table "$TABLE_ID" pref "$TABLE_ID" 2>/dev/null || true
    ip_route del local 0.0.0.0/0 dev lo table "$TABLE_ID" 2>/dev/null || true

    ip_rule add fwmark "$MARK_VALUE" table "$TABLE_ID" pref "$TABLE_ID" || {
        log Error "Failed to add IPv4 routing rule"
        return 1
    }
    ip_route add local 0.0.0.0/0 dev lo table "$TABLE_ID" || {
        log Error "Failed to add IPv4 route"
        return 1
    }

    log Debug "[EXEC] echo 1 > /proc/sys/net/ipv4/ip_forward"
    [ "$DRY_RUN" -eq 0 ] && echo 1 > /proc/sys/net/ipv4/ip_forward

    log Info "IPv4 routing setup completed"
}

setup_routing6() {
    log Info "Setting up routing rules for IPv6"

    ip6_rule del fwmark "$MARK_VALUE6" table "$TABLE_ID" pref "$TABLE_ID" 2>/dev/null || true
    ip6_route del local ::/0 dev lo table "$TABLE_ID" 2>/dev/null || true

    ip6_rule add fwmark "$MARK_VALUE6" table "$TABLE_ID" pref "$TABLE_ID" || {
        log Error "Failed to add IPv6 routing rule"
        return 1
    }
    ip6_route add local ::/0 dev lo table "$TABLE_ID" || {
        log Error "Failed to add IPv6 route"
        return 1
    }

    log Debug "[EXEC] echo 1 > /proc/sys/net/ipv6/conf/all/forwarding"
    [ "$DRY_RUN" -eq 0 ] && echo 1 > /proc/sys/net/ipv6/conf/all/forwarding

    log Info "IPv6 routing setup completed"
}

cleanup_chain() {
    local family="$1"
    local suffix=""
    local cmd="iptables"

    if [ "$family" = "6" ]; then
        suffix="6"
        cmd="ip6tables"
    fi

    log Info "Cleaning up TPROXY chains for IPv${family}"

    local table="mangle"

    # Remove from main chains (symmetric with setup)
    if [ "$PROXY_TCP" -eq 1 ]; then
        while $cmd -t "$table" -D PREROUTING -p tcp -j "PROXY_PREROUTING$suffix" 2> /dev/null; do :; done
        while $cmd -t "$table" -D OUTPUT -p tcp -j "PROXY_OUTPUT$suffix" 2> /dev/null; do :; done
    fi
    if [ "$PROXY_UDP" -eq 1 ]; then
        while $cmd -t "$table" -D PREROUTING -p udp -j "PROXY_PREROUTING$suffix" 2> /dev/null; do :; done
        while $cmd -t "$table" -D OUTPUT -p udp -j "PROXY_OUTPUT$suffix" 2> /dev/null; do :; done
    fi

    # Define chains based on family
    local chains="PROXY_PREROUTING$suffix PROXY_OUTPUT$suffix DIVERT$suffix PROXY_IP$suffix BYPASS_IP$suffix BYPASS_INTERFACE$suffix PROXY_INTERFACE$suffix DNS_HIJACK_PRE$suffix DNS_HIJACK_OUT$suffix APP_CHAIN$suffix MAC_CHAIN$suffix"

    # Clean up chains
    for c in $chains; do
        $cmd -t "$table" -F "$c" 2> /dev/null || true
        $cmd -t "$table" -X "$c" 2> /dev/null || true
    done

    log Info "TPROXY chains for IPv${family} cleanup completed"
}

cleanup_tproxy_chain4() {
    cleanup_chain 4
}

cleanup_tproxy_chain6() {
    cleanup_chain 6
}

cleanup_routing4() {
    log Info "Cleaning up IPv4 routing rules"

    ip_rule del fwmark "$MARK_VALUE" table "$TABLE_ID" pref "$TABLE_ID"
    ip_route del local 0.0.0.0/0 dev lo table "$TABLE_ID"

    log Debug "[EXEC] echo 0 > /proc/sys/net/ipv4/ip_forward"
    [ "$DRY_RUN" -eq 0 ] && echo 0 > /proc/sys/net/ipv4/ip_forward

    log Info "IPv4 routing cleanup completed"
}

cleanup_routing6() {
    log Info "Cleaning up IPv6 routing rules"

    ip6_rule del fwmark "$MARK_VALUE6" table "$TABLE_ID" pref "$TABLE_ID"
    ip6_route del local ::/0 dev lo table "$TABLE_ID"

    log Debug "[EXEC] echo 0 > /proc/sys/net/ipv6/conf/all/forwarding"
    [ "$DRY_RUN" -eq 0 ] && echo 0 > /proc/sys/net/ipv6/conf/all/forwarding

    log Info "IPv6 routing cleanup completed"
}

cleanup_ipset() {
    if [ "$BYPASS_RU_IP" -eq 0 ]; then
        log Debug "RU IP bypass is disabled, ipset cleanup skipped"
        return 0
    fi

    log Debug "[EXEC] ipset destroy ruip"
    log Debug "[EXEC] ipset destroy ruip6"
    if [ "$DRY_RUN" -eq 0 ]; then
        ipset destroy ruip 2> /dev/null || true
        ipset destroy ruip6 2> /dev/null || true
        log Info "ipset 'ruip' and 'ruip6' destroyed"
    fi
}

detect_proxy_mode() {
    USE_TPROXY=0
    case "$PROXY_MODE" in
        0)
            if check_tproxy_support; then
                USE_TPROXY=1
                log Info "Kernel supports TPROXY, using TPROXY mode (auto)"
            else
                log Error "Kernel does not support TPROXY, cannot use transparent proxy"
                return 1
            fi
            ;;
        1)
            if check_tproxy_support; then
                USE_TPROXY=1
                log Info "Using TPROXY mode (forced by configuration)"
            else
                log Error "TPROXY mode forced but kernel does not support TPROXY"
                return 1
            fi
            ;;
    esac
}

start_proxy() {
    log Info "Starting proxy setup..."
    if [ "$BYPASS_RU_IP" -eq 1 ]; then
        if [ "$HAS_IPSET" -eq 0 ] || [ "$HAS_XT_SET" -eq 0 ]; then
            log Error "Kernel does not support ipset (CONFIG_IP_SET, CONFIG_NETFILTER_XT_SET). Cannot bypass RU IPs"
            BYPASS_RU_IP=0
        else
            download_ru_ip_list || log Warn "Failed to download Russia IP list, continuing without it"
            if ! setup_ru_ipset; then
                log Error "Failed to setup ipset, RU bypass disabled"
                BYPASS_RU_IP=0
            fi
        fi
    fi

    if [ "$USE_TPROXY" -eq 1 ]; then
        setup_tproxy_chain4
        setup_routing4
        if [ "$PROXY_IPV6" -eq 1 ]; then
            setup_tproxy_chain6
            setup_routing6
        fi
    else
        log Error "TPROXY not available"
        return 1
    fi
    log Info "Proxy setup completed"
    block_loopback_traffic enable
    [ "$BLOCK_QUIC" -eq 1 ] && block_quic enable
    if [ "$PROXY_IPV6" -eq -1 ]; then
        manage_ipv6 disable || log Warn "Failed to disable IPv6 stack"
    fi
    save_runtime_config
}

stop_proxy() {
    log Info "Stopping proxy..."
    if load_runtime_config; then
        log Info "Using runtime config for cleanup"
    else
        log Warn "Using current config for cleanup (runtime config unavailable)"
    fi
    if [ "$USE_TPROXY" -eq 1 ]; then
        log Info "Cleaning up TPROXY chains"
        cleanup_tproxy_chain4
        cleanup_routing4
        if [ "$PROXY_IPV6" -eq 1 ]; then
            cleanup_tproxy_chain6
            cleanup_routing6
        fi
    else
        log Error "TPROXY was not active"
    fi
    cleanup_ipset
    log Info "Proxy stopped"
    block_loopback_traffic disable
    block_quic disable
    if [ "$PROXY_IPV6" -eq -1 ]; then
        manage_ipv6 restore || log Warn "Failed to restore IPv6 settings"
    fi
    [ "$DRY_RUN" -eq 1 ] || rm -f "$CONFIG_DIR/runtime_tproxy.conf" 2> /dev/null
}

# This rule blocks local access to tproxy-port to prevent traffic loopback.
block_loopback_traffic() {
    case "$1" in
        enable)
            ip6tables -t filter -A OUTPUT -d ::1 -p tcp -m owner --uid-owner "$CORE_USER" --gid-owner "$CORE_GROUP" -m tcp --dport "$PROXY_TCP_PORT" -j REJECT
            iptables -t filter -A OUTPUT -d 127.0.0.1 -p tcp -m owner --uid-owner "$CORE_USER" --gid-owner "$CORE_GROUP" -m tcp --dport "$PROXY_TCP_PORT" -j REJECT
            ;;
        disable)
            ip6tables -t filter -D OUTPUT -d ::1 -p tcp -m owner --uid-owner "$CORE_USER" --gid-owner "$CORE_GROUP" -m tcp --dport "$PROXY_TCP_PORT" -j REJECT 2> /dev/null || true
            iptables -t filter -D OUTPUT -d 127.0.0.1 -p tcp -m owner --uid-owner "$CORE_USER" --gid-owner "$CORE_GROUP" -m tcp --dport "$PROXY_TCP_PORT" -j REJECT 2> /dev/null || true
            ;;
    esac
}

block_quic() {
    case "$1" in
        enable)
            iptables -N BLOCK_QUIC 2> /dev/null || true
            iptables -F BLOCK_QUIC
            if [ "$BYPASS_RU_IP" -eq 1 ]; then
                iptables -A BLOCK_QUIC -p udp --dport 443 -m set ! --match-set ruip dst -j REJECT
            else
                iptables -A BLOCK_QUIC -p udp --dport 443 -j REJECT
            fi
            iptables -I INPUT -j BLOCK_QUIC
            iptables -I FORWARD -j BLOCK_QUIC
            iptables -I OUTPUT -j BLOCK_QUIC

            if [ "$PROXY_IPV6" -eq 1 ]; then
                ip6tables -N BLOCK_QUIC6 2> /dev/null || true
                ip6tables -F BLOCK_QUIC6
                if [ "$BYPASS_RU_IP" -eq 1 ]; then
                    ip6tables -A BLOCK_QUIC6 -p udp --dport 443 -m set ! --match-set ruip6 dst -j REJECT
                else
                    ip6tables -A BLOCK_QUIC6 -p udp --dport 443 -j REJECT
                fi
                ip6tables -I INPUT -j BLOCK_QUIC6
                ip6tables -I FORWARD -j BLOCK_QUIC6
                ip6tables -I OUTPUT -j BLOCK_QUIC6
            fi
            log Info "QUIC traffic blocked"
            ;;
        disable)
            local chain
            for chain in INPUT FORWARD OUTPUT; do
                iptables -D "$chain" -j BLOCK_QUIC 2> /dev/null || true
                ip6tables -D "$chain" -j BLOCK_QUIC6 2> /dev/null || true
            done
            iptables -F BLOCK_QUIC 2> /dev/null || true
            iptables -X BLOCK_QUIC 2> /dev/null || true
            ip6tables -F BLOCK_QUIC6 2> /dev/null || true
            ip6tables -X BLOCK_QUIC6 2> /dev/null || true
            log Info "QUIC traffic blocking disabled"
            ;;
    esac
}

manage_ipv6() {
    local action="$1"
    local ipv6_backup_file="$CONFIG_DIR/ipv6_backup.conf"

    case "$action" in
        backup | disable | restore) ;;
        *)
            log Error "Invalid action for manage_ipv6: $action (must be backup, disable, or restore)"
            return 1
            ;;
    esac

    if [ "$DRY_RUN" -eq 1 ]; then
        log Debug "Would $action IPv6 settings"
        return 0
    fi

    if [ "$action" = "backup" ] || [ "$action" = "disable" ]; then
        log Info "Backing up current IPv6 settings to $ipv6_backup_file"

        {
            echo "# IPv6 settings backup (generated at $(date))"
            echo "accept_ra=$(cat /proc/sys/net/ipv6/conf/all/accept_ra 2> /dev/null || echo unknown)"
            echo "autoconf=$(cat /proc/sys/net/ipv6/conf/all/autoconf 2> /dev/null || echo unknown)"
            echo "forwarding=$(cat /proc/sys/net/ipv6/conf/all/forwarding 2> /dev/null || echo unknown)"

            for iface in /proc/sys/net/ipv6/conf/*; do
                if [ -f "$iface/disable_ipv6" ]; then
                    iface_name=$(basename "$iface")
                    current=$(cat "$iface/disable_ipv6" 2> /dev/null || echo unknown)
                    echo "$iface_name=$current"
                fi
            done
        } > "$ipv6_backup_file" || {
            log Warn "Failed to backup IPv6 settings"
            return 1
        }

        log Debug "IPv6 backup completed"
    fi

    if [ "$action" = "disable" ]; then
        log Info "Force disabling IPv6 stack (disable_ipv6=1)"

        echo 0 > /proc/sys/net/ipv6/conf/all/accept_ra 2> /dev/null || true
        echo 0 > /proc/sys/net/ipv6/conf/all/autoconf 2> /dev/null || true
        echo 0 > /proc/sys/net/ipv6/conf/all/forwarding 2> /dev/null || true

        for iface in /proc/sys/net/ipv6/conf/*; do
            if [ -f "$iface/disable_ipv6" ]; then
                echo 1 > "$iface/disable_ipv6" 2> /dev/null || true
            fi
        done

        log Info "IPv6 stack fully disabled"
    fi

    if [ "$action" = "restore" ]; then
        if [ ! -f "$ipv6_backup_file" ]; then
            log Warn "No IPv6 backup file found: $ipv6_backup_file, skip restore"
            return 0
        fi

        log Info "Restoring IPv6 settings from $ipv6_backup_file"

        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            case "$key" in
                \#* | "") continue ;;
            esac

            case "$key" in
                accept_ra)
                    echo "$value" > /proc/sys/net/ipv6/conf/all/accept_ra 2> /dev/null || true
                    ;;
                autoconf)
                    echo "$value" > /proc/sys/net/ipv6/conf/all/autoconf 2> /dev/null || true
                    ;;
                forwarding)
                    echo "$value" > /proc/sys/net/ipv6/conf/all/forwarding 2> /dev/null || true
                    ;;
                *)
                    if [ -f "/proc/sys/net/ipv6/conf/$key/disable_ipv6" ]; then
                        echo "$value" > "/proc/sys/net/ipv6/conf/$key/disable_ipv6" 2> /dev/null || true
                    fi
                    ;;
            esac
        done < "$ipv6_backup_file"

        rm -f "$ipv6_backup_file" 2> /dev/null
        log Info "IPv6 settings restored"
    fi

    return 0
}

status_proxy() {
    log Info "Checking proxy status..."

    if load_runtime_config; then
        log Info "Loaded runtime config for status check"
    else
        log Warn "Runtime config unavailable, showing status based on current config"
    fi

    echo "--- [ Routing Rules ] ---"
    echo "IPv4 rules:"
    ip rule show | grep -E "table $TABLE_ID|from all"
    echo "IPv4 routes (table $TABLE_ID):"
    ip route show table "$TABLE_ID"

    if [ "$PROXY_IPV6" -ne 0 ]; then
        echo "IPv6 rules:"
        ip -6 rule show | grep -E "table $TABLE_ID|from all"
        echo "IPv6 routes (table $TABLE_ID):"
        ip -6 route show table "$TABLE_ID"
    fi

    echo "--- [ Iptables Rules ] ---"
    local table
    for table in mangle nat filter; do
        echo "Table: $table (IPv4)"
        iptables -w 100 -t "$table" -S 2>/dev/null | grep -E "PROXY_|DIVERT|BYPASS_|DNS_HIJACK|APP_CHAIN|MAC_CHAIN|BLOCK_QUIC" || echo "  (no rules found)"

        if [ "$PROXY_IPV6" -ne 0 ]; then
             echo "Table: $table (IPv6)"
             ip6tables -w 100 -t "$table" -S 2>/dev/null | grep -E "PROXY_|DIVERT|BYPASS_|DNS_HIJACK|APP_CHAIN|MAC_CHAIN|BLOCK_QUIC" || echo "  (no rules found)"
        fi
    done

    if command -v ipset > /dev/null 2>&1; then
        echo "--- [ Ipset Status ] ---"
        ipset list -n 2>/dev/null | grep -E "ruip|ruip6" || echo "  (no relevant ipsets found)"
    fi

    echo "--- [ Kernel Settings ] ---"
    echo "IPv4 forwarding: $(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo "N/A")"
    if [ "$PROXY_IPV6" -ne 0 ]; then
        echo "IPv6 forwarding (all): $(cat /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null || echo "N/A")"
    fi

    log Info "Status check completed"
}

is_func() {
    command -v "$1" > /dev/null 2>&1
}

call_func() {
    local func="$1"
    shift
    if is_func "$func"; then
        log Info "Calling user hook: $func"
        "$func" "$@"
    else
        log Debug "No user hook defined: $func"
    fi
}

show_usage() {
    local script_name
    script_name=$(basename "$0")

    cat << EOF
Usage: $script_name {start|stop|restart|status} [options]

This script sets up / cleans up transparent proxy (TPROXY) rules
for TCP/UDP traffic redirection, DNS hijacking, per-app proxy, RU IP bypass, etc.

Commands:
  start     Apply proxy rules, routing tables, ipset, sysctl changes
  stop      Remove all added rules, routes, ipset sets, restore sysctl
  restart   Equivalent to stop → short delay → start
  status    Show current rules and routing (check)

Options:
  -v, --version              Show version number and exit

  -d DIR, --dir DIR
      Specify the base configuration directory.
      Default: the directory where this script is located.

      Files that may be read from or written to in this directory:
      • tproxy.conf          (optional) user configuration overrides
      • runtime_tproxy.conf  (generated/used during runtime for cleanup)
      • ru.zone              (Russia IPv4 CIDR list, auto-downloaded if missing/old)
      • ru_ipv6.zone         (Russia IPv6 CIDR list, auto-downloaded if IPv6 enabled)
      • tmp/                 (temporary subdirectory for mktemp files, downloads, etc.)

      Requirements:
      - The directory must exist and be writable by the script (root usually).
      - If using custom location (e.g. /data/adb/modules/xxx), ensure it has
        read/write/execute permissions for root, and is persistent across reboots
        if you want downloaded lists and runtime config to survive.

  --dry-run
      Simulate all operations without actually modifying:
      • iptables / ip6tables rules
      • ip rules / routes
      • ipset sets
      • sysctl settings (/proc/sys/...)
      • file system writes (downloads, temp files, runtime config)
      Ideal for previewing what changes would be made.

  --verbose
      Increase logging detail:
      • With --dry-run: shows ALL log levels (Info, Warn, Error, Debug, [EXEC])
      • Without --dry-run: shows normal output + Debug-level messages
      • Without this flag: shows only Info, Warn, Error (quiet mode)

  -h, --help
      Show this help message and exit

Examples:
  $script_name start --dry-run
      # Preview changes without applying anything

  $script_name start --dry-run --verbose
      # Very detailed simulation (shows every command that would run)

  $script_name start -d /data/adb/myproxy
      # Use custom config directory

  $script_name restart --verbose
      # Restart with extra debug output

  $script_name stop -d /sdcard/myproxy
      # Stop using a specific config directory

Note:
  • Almost all operations require root privileges.
  • Some features (TPROXY, ipset, owner matching, etc.) depend on kernel support.
EOF
}

parse_args() {
    MAIN_CMD=""
    VERBOSE=0
    while [ $# -gt 0 ]; do
        case "$1" in
            start | stop | restart | status | check)
                if [ -n "$MAIN_CMD" ]; then
                    log Error "Multiple commands specified."
                    exit 1
                fi
                MAIN_CMD="$1"
                ;;
            --dry-run)
                DRY_RUN=1
                ;;
            --verbose)
                VERBOSE=1
                ;;
            -v | --version)
                echo "$SCRIPT_VERSION"
                exit 0
                ;;
            -d | --dir)
                shift
                if [ $# -eq 0 ] || [ -z "$1" ]; then
                    log Error "Option -d/--dir requires a directory argument"
                    show_usage
                    exit 1
                fi
                if [ ! -d "$1" ]; then
                    log Error "Directory does not exist or is not a directory: $1"
                    show_usage
                    exit 1
                fi
                CONFIG_DIR="$(cd "$1" 2> /dev/null && pwd -P)" || {
                    log Error "Failed to resolve absolute path for directory: $1"
                    exit 1
                }
                ;;
            -h | --help)
                show_usage
                exit 0
                ;;
            *)
                log Error "Invalid argument: $1"
                show_usage
                exit 1
                ;;
        esac
        shift
    done
    if [ -z "$MAIN_CMD" ]; then
        log Error "No command specified"
        show_usage
        exit 1
    fi
}

main() {
    local script_name
    script_name=$(basename "$0")
    log Debug "Starting ${script_name} ${SCRIPT_VERSION}"

    load_config

    if [ "$DRY_RUN" -eq 1 ]; then
        if [ "$VERBOSE" -eq 1 ]; then
            log Info "Dry-run mode + verbose: showing ALL logs"
        else
            log Info "Dry-run mode: only showing commands that would be executed"
        fi
    elif [ "$VERBOSE" -eq 1 ]; then
        log Info "Verbose mode: showing debug information"
    fi

    if ! validate_config; then
        log Error "Configuration validation failed"
        exit 1
    fi

    check_root

    init_tmpdir
    init_kernel_config_cache
    init_feature_flags

    detect_proxy_mode

    case "$MAIN_CMD" in
        start)
            call_func pre_start_hook
            start_proxy
            ;;
        stop)
            stop_proxy
            call_func post_stop_hook
            ;;
        restart)
            log Info "Restarting proxy..."
            stop_proxy
            call_func post_stop_hook
            sleep 2
            call_func pre_start_hook
            start_proxy
            log Info "Proxy restarted"
            ;;
        status | check)
            status_proxy
            ;;
        *)
            log Error "Invalid command: $MAIN_CMD"
            show_usage
            exit 1
            ;;
    esac
}

# Pre-initialize variables for set -u safety
DRY_RUN=0
VERBOSE=0
CONFIG_DIR=""
USE_TPROXY=0
HAS_TPROXY=0
HAS_CONNTRACK=0
HAS_OWNER=0
HAS_MARK_MT=0
HAS_MARK_TG=0
HAS_SOCKET=0
HAS_ADDRTYPE=0
HAS_MAC=0
HAS_IPSET=0
HAS_XT_SET=0

parse_args "$@"

main
