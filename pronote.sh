#!/usr/bin/env bash
# ==============================================================================
# Installation Pronote Client 2026 - Script universel Linux v4.6
# Support natif : Debian, Ubuntu, Mint, Fedora, Arch, CachyOS, Manjaro,
#                 Omarchy, EndeavourOS, Garuda, openSUSE, NixOS, GLF OS,
#                 Solus, Alpine Linux, Void Linux
# Support expérimental : Slackware
# Ce script n'est pas écrit ni supporté par Index Education.
# Il n'y a pas de support technique lié à son utilisation.
# Support automatique étendu : toute distribution dérivée (via ID_LIKE)
#
# Préfixes Wine :
#   64 bits : ~/.local/share/wineprefixes/pronote-2026
#   32 bits : ~/.local/share/wineprefixes/pronote-2026-32
#
# Changelog v4.6 :
#   - Fix Kubuntu/Ubuntu 26.04 (resolute) : erreur 127 « wineboot introuvable ».
#     WineHQ 11 place les binaires dans /opt/wine-stable/bin sans toujours
#     créer les liens /usr/bin. Le script découvre wine, wineboot, wineserver
#     et winecfg, les injecte dans le PATH, et n'utilise plus « env wineboot »
#     (qui provoquait exactement le code 127 constaté).
#   - Fix Ubuntu 26.04 : clé WineHQ enregistrée aussi en .asc (APT 3.2 refuse
#     une clé ASCII sous une extension .key).
#   - Fix ordre Debian/Ubuntu : WineHQ est installé AVANT winetricks.
#     winetricks dépend du paquet « wine » Ubuntu ; l'installer en premier
#     tirait Wine 10 des dépôts, ensuite remplacé par WineHQ, d'où
#     « wineserver not found » et wineboot absent.
#     Avec WineHQ, winetricks est désormais le script officiel autonome.
#   - Fix 32 bits / Wine 10+ / Wine 11 (Ubuntu 26.04, Fedora, Arch, CachyOS) :
#     « WINEARCH is set to win32 but this is not supported in wow64 mode ».
#     Le script sonde le support win32. S'il est absent, Pronote 32 bits
#     s'installe dans un préfixe WoW64 dédié (toujours séparé du 64 bits).
#     Mint / Debian avec wine32 conservent un vrai préfixe WINEARCH=win32.
#   - Les versions 32 et 64 bits restent installables en parallèle partout,
#     y compris quand les deux préfixes sont techniquement WoW64.
#   - Fix NixOS / GLF OS : plus de fetchTarball ni de liens WineHQ.
#     Utilisation de nix-shell -p sur le nixpkgs système, avec repli
#     wineWow64Packages.stable → wineWowPackages.stable → wine64 → wine,
#     puis « nix shell nixpkgs#... » (flakes) si le canal est absent.
#   - Support complet Solus (eopkg, wine + wine-32bit, 32 et 64 en parallèle).
#   - Support Alpine Linux (apk, dépôt community, winetricks autonome).
#   - Support Void Linux (xbps, void-repo-multilib, wine-32bit).
#   - Support openSUSE renforcé (wine + wine-32bit, motif 32bit).
#   - sudo / doas : Alpine et dérivées sans sudo sont gérées.
#
# Changelog v4.5 :
#   - Fix Debian/Ubuntu/Mint : Windows 10 forcé sur la famille debian.
#   - Préfixes séparés par architecture + désinstallateurs 32/64.
#   - Fix Mint XFCE PATH / NixOS épinglage (remplacé en v4.6).
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Configuration générale
# ------------------------------------------------------------------------------

readonly DEFAULT_YEAR="2026"
readonly DEFAULT_VERSION="2026.2.6"
readonly MIN_WINE_VERSION="9.0"
readonly PRONOTE_ICON_URL="https://img.icons8.com/doodle/1200/pronote-logo.jpg"
readonly ICON_SIZES=(16 22 24 32 48 64 128 256)
readonly ICON_BASE_DIR="$HOME/.local/share/icons/hicolor"
readonly ICON_DIR="$ICON_BASE_DIR/scalable/apps"
readonly PIXMAP_DIR="$HOME/.local/share/pixmaps"
readonly BIN_DIR="$HOME/.local/bin"
readonly APP_DIR="$HOME/.local/share/applications"
readonly LOG_DIR="$HOME/.local/share/pronote-installer"
readonly LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"

readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# URLs de base (seront potentiellement mises à jour par le scraping)
URL_32="https://tele3.index-education.com/telechargement/pn/v${DEFAULT_YEAR}.0/exe/Install_PRNclient_FR_${DEFAULT_VERSION}_win32.exe"
URL_64="https://tele3.index-education.com/telechargement/pn/v${DEFAULT_YEAR}.0/exe/Install_PRNclient_FR_${DEFAULT_VERSION}_win64.exe"
DEFAULT_URL="$URL_64"

# ------------------------------------------------------------------------------
# Variables globales
# ------------------------------------------------------------------------------

DISTRO_ID="unknown"
DISTRO_NAME="Inconnue"
DISTRO_FAMILY="unknown"

PRONOTE_URL="$DEFAULT_URL"
PRONOTE_YEAR="$DEFAULT_YEAR"
PRONOTE_VERSION="$DEFAULT_VERSION"
PRONOTE_ARCH="64"

SHOW_WINE_LOGS="0"
ASSUME_YES="0"
UNINSTALL_ONLY="0"
UNINSTALL_ARCH=""
IN_NIX_SHELL="0"

WIN_VERSION="win11"

# Binaires Wine résolus (corrigent l'erreur 127 et wineserver not found)
WINE_BIN=""
WINEBOOT_BIN=""
WINECFG_BIN=""
WINESERVER_BIN=""
WINE_WIN32_PREFIX_OK="unknown"

# Arguments d'origine (reprise NixOS)
ALL_ARGS=("$@")

# Permettre à l'utilisateur de forcer WINEPREFIX
WINEPREFIX_USER="${WINEPREFIX:-}"
WINEPREFIX="${WINEPREFIX_USER:-$HOME/.local/share/wineprefixes/pronote-$DEFAULT_YEAR}"
export WINEPREFIX

TMP_DIR="$(mktemp -d /tmp/pronote-installer-XXXXXX)"
trap 'rm -rf "$TMP_DIR" 2>/dev/null || true' EXIT

RUN_QUIET_ACTIVITY_DIR=""
RUN_QUIET_FINALIZE_MSG=""

# ==============================================================================
# Affichage / journalisation  (toujours sur stderr)
# ==============================================================================

log_info()    { echo -e "${BLUE}ℹ️  $*${NC}" >&2; }
log_success() { echo -e "${GREEN}✅ $*${NC}" >&2; }
log_warning() { echo -e "${YELLOW}⚠️  $*${NC}" >&2; }
log_error()   { echo -e "${RED}❌ $*${NC}" >&2; }

repeat_char() {
    local char="$1"
    local count="$2"
    local out=""
    local i

    for ((i = 0; i < count; i++)); do
        out+="$char"
    done

    printf "%s" "$out"
}

box_title() {
    local title="$1"
    local width="${2:-62}"
    local inner=$((width - 2))

    printf "╔"
    repeat_char "═" "$width"
    printf "╗\n"

    printf "║ %-*s ║\n" "$inner" "$title"

    printf "╚"
    repeat_char "═" "$width"
    printf "╝\n"
}

box_two_lines() {
    local line1="$1"
    local line2="$2"
    local width="${3:-62}"
    local inner=$((width - 2))

    printf "╔"
    repeat_char "═" "$width"
    printf "╗\n"

    printf "║ %-*s ║\n" "$inner" "$line1"
    printf "║ %-*s ║\n" "$inner" "$line2"

    printf "╚"
    repeat_char "═" "$width"
    printf "╝\n"
}

# ==============================================================================
# sudo / doas (Alpine, Void minimal, images live)
# ==============================================================================

ensure_privilege_helper() {
    if [ "$(id -u)" -eq 0 ]; then
        sudo() { "$@"; }
        return 0
    fi

    if command -v sudo >/dev/null 2>&1; then
        return 0
    fi

    if command -v doas >/dev/null 2>&1; then
        sudo() { doas "$@"; }
        log_info "sudo absent : utilisation de doas."
        return 0
    fi

    return 1
}

require_privilege_helper() {
    if ensure_privilege_helper; then
        return 0
    fi
    log_error "Ni sudo ni doas n'est disponible. Installez l'un des deux, ou relancez en root."
    exit 1
}

# ==============================================================================
# Aide
# ==============================================================================

usage() {
    cat << 'EOF'
Usage: install-pronote.sh [options]

Options:
  --help                 Afficher cette aide
  --yes                  Mode non-interactif (répond oui aux défauts)
  --arch 32|64           Forcer l'architecture de l'installateur
  --url URL              Utiliser une URL personnalisée d'installateur
  --uninstall [32|64]    Lancer le désinstallateur Pronote (32 ou 64 bits)
  --in-nix-shell         Utilisé en interne pour NixOS (ne pas utiliser)

Notes :
  • Les versions 32 et 64 bits utilisent des préfixes Wine distincts et
    peuvent être installées en même temps.
  • Désinstallation : pronote-desinstaller-32 ou pronote-desinstaller-64
  • Wine 10+/11 en mode WoW64 : Pronote 32 bits s'installe dans un préfixe
    WoW64 dédié (WINEARCH=win32 n'est plus créé, car non supporté).
EOF
}

# ==============================================================================
# Animation de progression + exécution silencieuse
# ==============================================================================

progress_pulse() {
    local label="$1"
    local pid="$2"
    local activity_dir="${3:-}"
    local finalize_msg="${4:-Finalisation en cours, veuillez patienter quelques secondes...}"

    local width=24
    local block=7
    local pos=0
    local direction=1
    local start_time=$SECONDS

    local check_activity=0
    [ -n "$activity_dir" ] && check_activity=1

    local last_size=-1
    local stable_count=0
    local finalized=0
    local sample_tick=0
    local current_label="$label"

    if [ ! -t 1 ]; then
        while kill -0 "$pid" 2>/dev/null; do
            sleep 1
        done
        return
    fi

    while kill -0 "$pid" 2>/dev/null; do
        local bar=""
        local i
        local elapsed=$((SECONDS - start_time))
        local min=$((elapsed / 60))
        local sec=$((elapsed % 60))

        if [ "$check_activity" -eq 1 ] && [ "$finalized" -eq 0 ]; then
            sample_tick=$((sample_tick + 1))

            if (( sample_tick >= 8 )); then
                sample_tick=0
                local cur_size
                cur_size="$(du -sk "$activity_dir" 2>/dev/null | cut -f1)"
                cur_size="${cur_size:-0}"

                if [ "$cur_size" = "$last_size" ]; then
                    stable_count=$((stable_count + 1))
                else
                    stable_count=0
                fi
                last_size="$cur_size"

                if (( stable_count >= 3 && elapsed >= 5 )); then
                    finalized=1
                    current_label="$finalize_msg"
                fi
            fi
        fi

        for ((i = 0; i < width; i++)); do
            if (( i >= pos && i < pos + block )); then
                bar+="█"
            else
                bar+=" "
            fi
        done

        printf "\r\033[K%s [%s] %02d:%02d" "$current_label" "$bar" "$min" "$sec"

        pos=$((pos + direction))

        if (( pos <= 0 )); then
            pos=0
            direction=1
        elif (( pos + block >= width )); then
            pos=$((width - block))
            direction=-1
        fi

        sleep 0.12
    done

    printf "\r\033[K"
}

# run_quiet n'utilise plus « env COMMANDE » : env renvoyait 127 dès que
# wineboot/wineserver n'étaient pas dans le PATH (cas WineHQ 11 / Ubuntu 26.04).
# Un sous-shell bash exporte WINEDEBUG puis lance la commande, y compris
# lorsqu'il s'agit d'une fonction du script.
run_quiet() {
    local label="$1"
    shift

    if [[ "$SHOW_WINE_LOGS" == "1" ]]; then
        log_info "$label"
        echo "Mode expert actif : les messages Wine sont affichés."
        export WINEDEBUG="${WINEDEBUG:-}"
        "$@"
        return $?
    fi

    mkdir -p "$LOG_DIR"

    (
        export WINEDEBUG="${WINEDEBUG_QUIET:--all}"
        "$@"
    ) >>"$LOG_FILE" 2>&1 &

    local pid=$!
    progress_pulse "$label" "$pid" "$RUN_QUIET_ACTIVITY_DIR" "$RUN_QUIET_FINALIZE_MSG"

    set +e
    wait "$pid"
    local status=$?
    set -e

    if [ "$status" -eq 0 ]; then
        log_success "$label : terminé"
    else
        log_warning "$label : terminé avec un code retour $status"
        echo "Les détails techniques sont enregistrés ici :"
        echo "  $LOG_FILE"
    fi

    return "$status"
}

# ------------------------------------------------------------------------------
# Petit helper pour les questions (support --yes)
# ------------------------------------------------------------------------------

ask_user() {
    local prompt="$1"
    local default="$2"

    if [ "$ASSUME_YES" = "1" ]; then
        echo "$default"
        return 0
    fi

    local answer
    read -rp "$prompt" answer
    echo "${answer:-$default}"
}

ask_wine_output_mode() {
    if [ "$ASSUME_YES" = "1" ]; then
        SHOW_WINE_LOGS="0"
        return 0
    fi

    echo ""
    echo "Par défaut, les messages techniques de Wine seront masqués."
    echo "Ils sont utiles uniquement pour diagnostiquer un problème."
    read -rp "Afficher les messages techniques de Wine ? [o/N] : " answer

    case "$answer" in
        o|O|oui|Oui|OUI|y|Y|yes|YES)
            SHOW_WINE_LOGS="1"
            log_warning "Mode expert activé : les logs Wine seront affichés."
            ;;
        *)
            SHOW_WINE_LOGS="0"
            log_info "Mode silencieux activé : les logs Wine seront masqués."
            ;;
    esac

    return 0
}

# ==============================================================================
# Détection système
# ==============================================================================

detect_distro() {
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release

        DISTRO_ID="${ID:-unknown}"
        DISTRO_NAME="${NAME:-Inconnue}"

        case "$DISTRO_ID" in
            ubuntu|debian|linuxmint|pop|elementary|neon|zorin|kali|kubuntu)
                DISTRO_FAMILY="debian"
                ;;
            fedora|nobara|rhel|centos|almalinux|rocky)
                DISTRO_FAMILY="fedora"
                ;;
            arch|cachyos|manjaro|endeavouros|garuda|omarchy)
                DISTRO_FAMILY="arch"
                ;;
            opensuse*|suse|opensuse-tumbleweed|opensuse-leap|opensuse-slowroll)
                DISTRO_FAMILY="suse"
                ;;
            nixos|glfos|glf-os)
                DISTRO_FAMILY="nixos"
                ;;
            slackware)
                DISTRO_FAMILY="slackware"
                ;;
            solus)
                DISTRO_FAMILY="solus"
                ;;
            alpine)
                DISTRO_FAMILY="alpine"
                ;;
            void)
                DISTRO_FAMILY="void"
                ;;
            *)
                DISTRO_FAMILY="unknown"
                ;;
        esac

        if [ "$DISTRO_FAMILY" = "unknown" ] && [ -n "${ID_LIKE:-}" ]; then
            case " ${ID_LIKE} " in
                *" debian "*|*" ubuntu "*)   DISTRO_FAMILY="debian" ;;
                *" fedora "*|*" rhel "*)     DISTRO_FAMILY="fedora" ;;
                *" arch "*)                  DISTRO_FAMILY="arch" ;;
                *" suse "*|*" opensuse "*)   DISTRO_FAMILY="suse" ;;
                *" nixos "*)                 DISTRO_FAMILY="nixos" ;;
                *" slackware "*)             DISTRO_FAMILY="slackware" ;;
                *" solus "*)                 DISTRO_FAMILY="solus" ;;
                *" alpine "*)                DISTRO_FAMILY="alpine" ;;
                *" void "*)                  DISTRO_FAMILY="void" ;;
            esac

            if [ "$DISTRO_FAMILY" != "unknown" ]; then
                log_info "Distribution dérivée détectée via ID_LIKE (${ID_LIKE}) → famille : $DISTRO_FAMILY"
            fi
        fi
    else
        DISTRO_ID="unknown"
        DISTRO_NAME="Inconnue"
        DISTRO_FAMILY="unknown"
    fi
}

check_command() {
    command -v "$1" >/dev/null 2>&1
}

prepend_path() {
    local dir="$1"
    [ -d "$dir" ] || return 0
    case ":$PATH:" in
        *":$dir:"*) ;;
        *) export PATH="$dir:$PATH" ;;
    esac
}

get_wine_version() {
    local bin="${WINE_BIN:-}"
    if [ -z "$bin" ]; then
        bin="$(command -v wine 2>/dev/null || true)"
    fi
    if [ -n "$bin" ] && [ -x "$bin" ]; then
        "$bin" --version 2>/dev/null | grep -Eo '[0-9]+([.][0-9]+)+' | head -n1 || echo "0"
    else
        echo "0"
    fi
}

version_lt() {
    local v1="$1"
    local v2="$2"

    [ "$v1" != "$v2" ] && [ "$(printf '%s\n%s\n' "$v1" "$v2" | sort -V | head -n1)" = "$v1" ]
}

# ------------------------------------------------------------------------------
# Résolution des binaires Wine (erreur 127 / wineserver not found)
# ------------------------------------------------------------------------------
# WineHQ 11 sous Ubuntu 26.04 installe :
#   /opt/wine-stable/bin/wine
#   /opt/wine-stable/bin/wineboot
#   /opt/wine-stable/bin/wineserver
# sans garantir les liens dans /usr/bin. winetricks cherche wineserver dans
# le PATH. On reconstitue donc un PATH cohérent, et on mémorise les chemins.
# ------------------------------------------------------------------------------

discover_wine_paths() {
    local dir candidate resolved wine_dir

    for dir in \
        /opt/wine-stable/bin \
        /opt/wine-devel/bin \
        /opt/wine-staging/bin \
        /usr/lib/wine \
        /usr/lib64/wine \
        "$HOME/.local/bin" \
        /usr/local/bin \
        /usr/bin
    do
        prepend_path "$dir"
    done

    hash -r 2>/dev/null || true

    WINE_BIN=""
    WINEBOOT_BIN=""
    WINECFG_BIN=""
    WINESERVER_BIN=""

    for candidate in wine wine64; do
        if check_command "$candidate"; then
            WINE_BIN="$(command -v "$candidate")"
            break
        fi
    done

    if [ -z "$WINE_BIN" ]; then
        for candidate in \
            /opt/wine-stable/bin/wine \
            /opt/wine-devel/bin/wine \
            /opt/wine-staging/bin/wine \
            /usr/bin/wine \
            /usr/bin/wine64
        do
            if [ -x "$candidate" ]; then
                WINE_BIN="$candidate"
                prepend_path "$(dirname "$candidate")"
                break
            fi
        done
    fi

    if [ -n "$WINE_BIN" ]; then
        resolved="$(readlink -f "$WINE_BIN" 2>/dev/null || echo "$WINE_BIN")"
        wine_dir="$(dirname "$resolved")"
        prepend_path "$wine_dir"

        [ -x "$wine_dir/wineboot" ]    && WINEBOOT_BIN="$wine_dir/wineboot"
        [ -x "$wine_dir/winecfg" ]     && WINECFG_BIN="$wine_dir/winecfg"
        [ -x "$wine_dir/wineserver" ]  && WINESERVER_BIN="$wine_dir/wineserver"
    fi

    if [ -z "$WINEBOOT_BIN" ]   && check_command wineboot;   then WINEBOOT_BIN="$(command -v wineboot)"; fi
    if [ -z "$WINECFG_BIN" ]    && check_command winecfg;    then WINECFG_BIN="$(command -v winecfg)"; fi
    if [ -z "$WINESERVER_BIN" ] && check_command wineserver; then WINESERVER_BIN="$(command -v wineserver)"; fi

    hash -r 2>/dev/null || true

    if [ -n "$WINE_BIN" ]; then
        export WINE="$WINE_BIN"
    fi
    if [ -n "$WINESERVER_BIN" ]; then
        export WINESERVER="$WINESERVER_BIN"
    fi
}

wine_is_available() {
    discover_wine_paths
    [ -n "$WINE_BIN" ] && [ -x "$WINE_BIN" ]
}

# Lance wineboot même si le wrapper n'est pas dans le PATH.
# Wine 11 : « wine wineboot --init » fonctionne (wineboot.exe est un builtin).
run_wineboot_tool() {
    if [ -n "${WINEBOOT_BIN:-}" ] && [ -x "$WINEBOOT_BIN" ]; then
        "$WINEBOOT_BIN" "$@"
        return $?
    fi
    if [ -n "${WINE_BIN:-}" ] && [ -x "$WINE_BIN" ]; then
        "$WINE_BIN" wineboot "$@"
        return $?
    fi
    log_error "wineboot introuvable (ni wrapper, ni binaire wine)."
    return 127
}

run_winecfg_tool() {
    if [ -n "${WINECFG_BIN:-}" ] && [ -x "$WINECFG_BIN" ]; then
        "$WINECFG_BIN" "$@"
        return $?
    fi
    if [ -n "${WINE_BIN:-}" ] && [ -x "$WINE_BIN" ]; then
        "$WINE_BIN" winecfg "$@"
        return $?
    fi
    log_warning "winecfg introuvable."
    return 1
}

run_wineserver_tool() {
    if [ -n "${WINESERVER_BIN:-}" ] && [ -x "$WINESERVER_BIN" ]; then
        "$WINESERVER_BIN" "$@"
        return $?
    fi
    if check_command wineserver; then
        wineserver "$@"
        return $?
    fi
    return 0
}

run_wine_bin() {
    if [ -n "${WINE_BIN:-}" ] && [ -x "$WINE_BIN" ]; then
        "$WINE_BIN" "$@"
        return $?
    fi
    wine "$@"
}

print_wine_diagnostics() {
    echo ""
    echo "Diagnostic Wine :"
    echo "  PATH       = $PATH"
    echo "  wine       = ${WINE_BIN:-introuvable}"
    echo "  wineboot   = ${WINEBOOT_BIN:-introuvable (repli : wine wineboot)}"
    echo "  winecfg    = ${WINECFG_BIN:-introuvable}"
    echo "  wineserver = ${WINESERVER_BIN:-introuvable}"
    echo "  version    = $(get_wine_version)"
    echo "  WINEPREFIX = $WINEPREFIX"
    echo "  WINEARCH   = ${WINEARCH:-non défini}"
    echo ""
}

# ------------------------------------------------------------------------------
# winetricks autonome (GitHub) — évite le paquet Debian qui dépend de « wine »
# ------------------------------------------------------------------------------

install_winetricks_standalone() {
    log_info "Installation autonome de winetricks (script officiel Winetricks)..."
    mkdir -p "$BIN_DIR"
    prepend_path "$BIN_DIR"

    local wt="$BIN_DIR/winetricks"
    local url="https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks"

    if ! wget -q --timeout=20 --tries=3 "$url" -O "$wt"; then
        log_warning "Téléchargement de winetricks impossible."
        return 1
    fi

    chmod +x "$wt"

    if ! head -n1 "$wt" | grep -qE '^#!' || ! grep -q "winetricks" "$wt"; then
        log_error "Le fichier winetricks téléchargé est invalide."
        rm -f "$wt"
        return 1
    fi

    log_success "winetricks installé dans $wt"
    return 0
}

# ------------------------------------------------------------------------------
# Version Windows adaptée à la famille de distribution
# ------------------------------------------------------------------------------
# Sur Debian/Ubuntu/Mint, Wine est souvent livré en paquets séparés
# (wine32/wine64) et, avec « Windows 11 », l'installateur Index Éducation
# refuse de s'installer. Windows 10 contourne le refus.
# Arch / Fedora / SUSE / Solus / Void / Alpine conservent win11.
# ------------------------------------------------------------------------------

set_target_windows_version() {
    case "$DISTRO_FAMILY" in
        debian)
            WIN_VERSION="win10"
            log_info "Famille Debian détectée : la version Windows annoncée sera Windows 10."
            log_info "(contournement du refus d'installation 32/64 bits sur Debian/Ubuntu/Mint)"
            ;;
        *)
            WIN_VERSION="win11"
            ;;
    esac
}

detect_prefix_arch_at() {
    local prefix="$1"

    if [ ! -d "$prefix" ]; then
        echo "none"
        return
    fi

    if [ -f "$prefix/system.reg" ]; then
        if grep -qE '^#arch=win64' "$prefix/system.reg" 2>/dev/null; then
            echo "64"
            return
        fi
        if grep -qE '^#arch=win32' "$prefix/system.reg" 2>/dev/null; then
            echo "32"
            return
        fi
    fi

    echo "64"
}

detect_prefix_arch() {
    detect_prefix_arch_at "$WINEPREFIX"
}

# ------------------------------------------------------------------------------
# Préfixes séparés par architecture
# ------------------------------------------------------------------------------
# 64 bits : ~/.local/share/wineprefixes/pronote-ANNEE  (chemin historique)
# 32 bits : ~/.local/share/wineprefixes/pronote-ANNEE-32
# Même lorsque Wine refuse WINEARCH=win32 (mode WoW64), le préfixe 32 bits
# reste un dossier distinct : les deux clients coexistent.
# ------------------------------------------------------------------------------

set_wineprefix() {
    if [ -n "$WINEPREFIX_USER" ]; then
        WINEPREFIX="$WINEPREFIX_USER"
    else
        local base="$HOME/.local/share/wineprefixes/pronote-$PRONOTE_YEAR"

        if [ "$PRONOTE_ARCH" = "32" ]; then
            if [ ! -d "${base}-32" ] && [ "$(detect_prefix_arch_at "$base")" = "32" ]; then
                WINEPREFIX="$base"
            else
                WINEPREFIX="${base}-32"
            fi
        else
            WINEPREFIX="$base"
        fi
    fi

    export WINEPREFIX
    mkdir -p "$(dirname "$WINEPREFIX")"
}

# ------------------------------------------------------------------------------
# Sondage WINEARCH=win32 (Wine 11 / nouveau WoW64)
# ------------------------------------------------------------------------------

probe_win32_prefix_support() {
    if [ "$WINE_WIN32_PREFIX_OK" = "1" ]; then
        return 0
    fi
    if [ "$WINE_WIN32_PREFIX_OK" = "0" ]; then
        return 1
    fi

    discover_wine_paths

    if [ -z "$WINE_BIN" ]; then
        WINE_WIN32_PREFIX_OK="0"
        return 1
    fi

    log_info "Vérification du support des préfixes Wine 32 bits natifs (WINEARCH=win32)..."

    local test_prefix="$TMP_DIR/wine-win32-probe"
    rm -rf "$test_prefix"
    mkdir -p "$test_prefix"

    local out=""
    set +e
    out="$(
        export WINEPREFIX="$test_prefix"
        export WINEARCH="win32"
        export WINEDEBUG="-all"
        export WINEDLLOVERRIDES="mscoree,mshtml="
        run_wineboot_tool --init 2>&1
    )"
    local status=$?
    set -e

    rm -rf "$test_prefix" 2>/dev/null || true

    if grep -qi "not supported in wow64" <<< "$out"; then
        WINE_WIN32_PREFIX_OK="0"
        log_warning "Ce Wine est compilé en WoW64 : WINEARCH=win32 n'est pas disponible."
        log_info "Pronote 32 bits utilisera un préfixe WoW64 dédié, séparé du préfixe 64 bits."
        return 1
    fi

    if [ "$status" -eq 0 ]; then
        WINE_WIN32_PREFIX_OK="1"
        log_success "Les préfixes 32 bits natifs (WINEARCH=win32) sont supportés."
        return 0
    fi

    # Échec pour une autre raison : on évite win32, plus sûr sur Wine récent.
    WINE_WIN32_PREFIX_OK="0"
    log_warning "Le sondage WINEARCH=win32 n'a pas abouti (code $status). Repli sur un préfixe WoW64 dédié."
    return 1
}

choose_winearch_for_new_prefix() {
    unset WINEARCH || true

    if [ "$PRONOTE_ARCH" = "32" ]; then
        if probe_win32_prefix_support; then
            export WINEARCH="win32"
            log_info "Architecture du nouveau préfixe : 32 bits natif (WINEARCH=win32)"
        else
            export WINEARCH="win64"
            log_info "Architecture du nouveau préfixe : WoW64 dédié à Pronote 32 bits"
            log_info "(l'installateur win32 s'exécute dans ce préfixe, sans WINEARCH=win32)"
        fi
    else
        export WINEARCH="win64"
        log_info "Architecture du nouveau préfixe : 64 bits"
    fi
}

# ==============================================================================
# Dernière version Pronote
# ==============================================================================

check_latest_version() {
    if [ -n "${PRONOTE_URL_FROM_OPTION:-}" ]; then
        return
    fi

    log_info "Vérification de la dernière version de Pronote Client sur le site officiel..."

    local page=""
    page="$(wget -q --timeout=10 --tries=1 -L -O - "https://www.index-education.com/fr/telecharger-pronote.php" 2>/dev/null)" || true

    if [ -z "$page" ]; then
        log_warning "Impossible de vérifier la dernière version (site inaccessible). Version par défaut conservée : $DEFAULT_VERSION"
        return
    fi

    local ver64 ver32
    ver64="$(grep -oE 'Install_PRNclient_FR_[0-9]+\.[0-9]+\.[0-9]+_win64\.exe' <<< "$page" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -n1 || true)"
    ver32="$(grep -oE 'Install_PRNclient_FR_[0-9]+\.[0-9]+\.[0-9]+_win32\.exe' <<< "$page" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -n1 || true)"

    if [ -z "$ver64" ] && [ -z "$ver32" ]; then
        log_warning "Aucune version trouvée sur la page. Version par défaut conservée."
        return
    fi

    local latest=""
    if [ -n "$ver64" ]; then
        latest="$ver64"
    else
        latest="$ver32"
    fi

    if version_lt "$PRONOTE_VERSION" "$latest"; then
        log_info "Nouvelle version détectée : $latest (actuellement $PRONOTE_VERSION)."
        PRONOTE_VERSION="$latest"

        URL_32="https://tele3.index-education.com/telechargement/pn/v${PRONOTE_YEAR}.0/exe/Install_PRNclient_FR_${PRONOTE_VERSION}_win32.exe"
        URL_64="https://tele3.index-education.com/telechargement/pn/v${PRONOTE_YEAR}.0/exe/Install_PRNclient_FR_${PRONOTE_VERSION}_win64.exe"
        DEFAULT_URL="$URL_64"

        log_success "Liens mis à jour vers la version $PRONOTE_VERSION."
    else
        log_success "La version $PRONOTE_VERSION est à jour."
    fi
}

# ------------------------------------------------------------------------------
# Dépôt officiel WineHQ pour Ubuntu / Debian / dérivées
# ------------------------------------------------------------------------------

setup_winehq_repo_debian() {
    log_info "Configuration du dépôt officiel WineHQ (dernière version stable)..."

    local codename="" base_distro=""

    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
    fi

    if [ -n "${UBUNTU_CODENAME:-}" ]; then
        codename="$UBUNTU_CODENAME"
        base_distro="ubuntu"
    elif [ -n "${DEBIAN_CODENAME:-}" ]; then
        codename="$DEBIAN_CODENAME"
        base_distro="debian"
    elif check_command lsb_release; then
        codename="$(lsb_release -sc 2>/dev/null || true)"
        case " ${ID_LIKE:-} ${ID:-} " in
            *" ubuntu "*) base_distro="ubuntu" ;;
            *" debian "*) base_distro="debian" ;;
            *) base_distro="ubuntu" ;;
        esac
    fi

    if [ -z "$codename" ]; then
        log_warning "Impossible de déterminer le nom de code de la distribution."
        log_warning "Le dépôt WineHQ ne sera pas configuré ; Wine des dépôts standards sera utilisé."
        return 1
    fi

    log_info "Base : $base_distro / nom de code : $codename"

    sudo apt install -y wget gnupg ca-certificates >/dev/null 2>&1 || true
    sudo mkdir -p /etc/apt/keyrings

    # Ubuntu 26.04 / APT 3.2 : une clé ASCII doit s'appeler .asc, pas .key.
    if ! sudo wget -q -O /etc/apt/keyrings/winehq-archive.asc \
            https://dl.winehq.org/wine-builds/winehq.key; then
        log_warning "Impossible de télécharger la clé WineHQ (.asc)."
        return 1
    fi

    # Copie déarmorée sous le nom historique, pour les fichiers .sources WineHQ.
    wget -qO- https://dl.winehq.org/wine-builds/winehq.key \
        | sudo gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key 2>/dev/null || true
    sudo cp -f /etc/apt/keyrings/winehq-archive.asc /etc/apt/keyrings/winehq-archive.key 2>/dev/null || true

    local sources_url="https://dl.winehq.org/wine-builds/${base_distro}/dists/${codename}/winehq-${codename}.sources"
    local sources_file="/etc/apt/sources.list.d/winehq-${codename}.sources"

    if ! wget -q --spider "$sources_url" 2>/dev/null; then
        log_warning "Le dépôt WineHQ ne semble pas disponible pour '$codename'."
        log_warning "Cela peut arriver avec une version très récente ou une dérivée exotique."
        log_warning "Wine des dépôts standards sera utilisé à la place."
        return 1
    fi

    if ! sudo wget -q -O "$sources_file" "$sources_url"; then
        log_warning "Impossible d'écrire le fichier de sources WineHQ."
        return 1
    fi

    # Harmonise Signed-By si le .sources pointe vers un nom de clé différent.
    if [ -f "$sources_file" ] && grep -q "Signed-By:" "$sources_file"; then
        sudo sed -i 's|Signed-By:.*|Signed-By: /etc/apt/keyrings/winehq-archive.asc|' "$sources_file" || true
    fi

    log_success "Dépôt WineHQ configuré pour $base_distro ($codename)."
    return 0
}

apt_update_debian() {
    log_info "Mise à jour des index des paquets..."

    local tmp_log
    tmp_log="$(mktemp "$TMP_DIR/apt-update-XXXXXX.log")"

    set +e
    sudo apt update >"$tmp_log" 2>&1
    local status=$?
    set -e

    if [ "$status" -eq 0 ]; then
        log_success "Index des paquets à jour."
        return 0
    fi

    if grep -qiE "does not have a Release file|n'a pas de fichier Release|NO_PUBKEY|is not signed" "$tmp_log"; then
        echo ""
        log_warning "Un ou plusieurs dépôts tiers sont incompatibles avec cette version."
        log_warning "Ce n'est pas bloquant : l'installation continue avec les dépôts officiels."
        echo ""
        echo "Dépôts concernés :"
        grep -E "ppa\.launchpadcontent\.net|does not have a Release file|n'a pas de fichier Release|NO_PUBKEY" "$tmp_log" \
            | sed 's/^/  /' | head -n 8 || true
        echo ""
        echo "Pour supprimer l'avertissement de façon permanente :"
        echo "  • Paramètres > Logiciels et mises à jour > Autres logiciels"
        echo "  • ou, pour le PPA Geany :"
        echo "    sudo add-apt-repository --remove ppa:ubuntuhandbook1/geany"
        echo ""
        return 0
    fi

    log_warning "apt update a renvoyé un code $status. Poursuite malgré tout..."
    tail -n 15 "$tmp_log" | sed 's/^/  /'
    echo "Journal : $tmp_log"
    return 0
}

install_debian_winehq_or_distro() {
    local winehq_ready="$1"

    if [ "$winehq_ready" = "1" ]; then
        log_info "Installation de Wine depuis le dépôt officiel WineHQ (dernière version stable)..."

        set +e
        sudo DEBIAN_FRONTEND=noninteractive apt install --install-recommends -y winehq-stable
        local st=$?
        set -e

        if [ "$st" -ne 0 ]; then
            log_warning "Échec de winehq-stable ; tentative avec winehq-staging..."
            set +e
            sudo DEBIAN_FRONTEND=noninteractive apt install --install-recommends -y winehq-staging
            st=$?
            set -e
        fi

        if [ "$st" -ne 0 ]; then
            log_warning "WineHQ indisponible ; repli sur le paquet Wine des dépôts standards."
            sudo DEBIAN_FRONTEND=noninteractive apt install --install-recommends -y wine wine32 wine64 \
                || sudo DEBIAN_FRONTEND=noninteractive apt install -y wine
        fi
    else
        log_warning "Dépôt WineHQ non configuré ; installation de Wine des dépôts standards."
        log_warning "Cette version peut être trop ancienne pour Pronote 2026 (Wine 10+ recommandé)."
        sudo DEBIAN_FRONTEND=noninteractive apt install --install-recommends -y wine wine32 wine64 \
            || sudo DEBIAN_FRONTEND=noninteractive apt install -y wine
    fi

    discover_wine_paths

    if [ -z "$WINE_BIN" ]; then
        log_warning "Wine n'est toujours pas dans le PATH. Tentative de repli sur le Wine des dépôts..."
        sudo DEBIAN_FRONTEND=noninteractive apt install -y wine wine64 || true
        discover_wine_paths
    fi

    if [ -n "$WINE_BIN" ]; then
        log_success "Wine disponible : $WINE_BIN ($(get_wine_version))"
    else
        log_error "Impossible de trouver le binaire wine après installation."
        print_wine_diagnostics
        exit 1
    fi
}

# ==============================================================================
# Installation des dépendances
# ==============================================================================

install_dependencies() {
    log_info "Installation des dépendances nécessaires..."
    require_privilege_helper

    case "$DISTRO_FAMILY" in
        debian)
            log_info "Activation de l'architecture i386 (si le dépôt fournit encore wine32)..."
            sudo dpkg --add-architecture i386 || true

            local winehq_ready=0
            if setup_winehq_repo_debian; then
                winehq_ready=1
            fi

            apt_update_debian

            # winetricks n'est PAS installé ici : le paquet Debian dépend de
            # « wine » (paquet Ubuntu), ce qui installait Wine 10 puis le
            # faisait remplacer par WineHQ → wineboot/wineserver absents.
            sudo DEBIAN_FRONTEND=noninteractive apt install -y \
                wget cabextract icoutils desktop-file-utils imagemagick \
                || true

            install_debian_winehq_or_distro "$winehq_ready"

            log_info "Installation de winetricks (script autonome, compatible WineHQ)..."
            if ! install_winetricks_standalone; then
                log_warning "Repli : paquet winetricks des dépôts (peut tirer le Wine Ubuntu)."
                sudo DEBIAN_FRONTEND=noninteractive apt install -y winetricks || true
                discover_wine_paths
            fi

            sudo apt install -y librsvg2-bin >/dev/null 2>&1 || true
            ;;

        fedora)
            sudo dnf install -y wine wget cabextract winetricks icoutils desktop-file-utils ImageMagick \
                || sudo dnf install -y wine wget cabextract icoutils desktop-file-utils ImageMagick
            sudo dnf install -y wine.i686 wine-core.i686 >/dev/null 2>&1 || true
            sudo dnf install -y librsvg2-tools >/dev/null 2>&1 || true
            check_command winetricks || install_winetricks_standalone || true
            ;;

        arch)
            if ! grep -Eq '^[[:space:]]*\[multilib\]' /etc/pacman.conf; then
                log_error "Le dépôt [multilib] n'est pas activé dans /etc/pacman.conf."
                echo ""
                echo "Pour Arch, CachyOS, Manjaro, Omarchy ou dérivées, Wine a besoin de [multilib]."
                echo "Décommentez ces lignes dans /etc/pacman.conf :"
                echo ""
                echo "  [multilib]"
                echo "  Include = /etc/pacman.d/mirrorlist"
                echo ""
                echo "Puis relancez :"
                echo "  sudo pacman -Syu"
                echo ""
                exit 1
            fi

            log_warning "La commande 'sudo pacman -Syu' va mettre à jour l'ensemble du système."
            if [ "$ASSUME_YES" = "0" ]; then
                read -rp "Continuer ? [O/n] : " answer
                case "$answer" in
                    n|N|non|Non|NON)
                        log_error "Installation annulée."
                        exit 1
                        ;;
                esac
            fi

            sudo pacman -Syu --needed --noconfirm wine wget cabextract winetricks icoutils desktop-file-utils imagemagick
            sudo pacman -S --needed --noconfirm librsvg >/dev/null 2>&1 || true
            check_command winetricks || install_winetricks_standalone || true
            ;;

        suse)
            log_info "Installation Wine openSUSE (64 bits + 32 bits si disponible)..."
            sudo zypper --non-interactive install -t pattern 32bit >/dev/null 2>&1 || true
            sudo zypper --non-interactive install \
                wine wine-32bit wget cabextract winetricks icoutils desktop-file-utils ImageMagick \
                || sudo zypper --non-interactive install \
                    wine wget cabextract icoutils desktop-file-utils ImageMagick
            sudo zypper --non-interactive install librsvg2-tools >/dev/null 2>&1 || true
            check_command winetricks || install_winetricks_standalone || true
            ;;

        solus)
            install_solus_dependencies
            ;;

        alpine)
            install_alpine_dependencies
            ;;

        void)
            install_void_dependencies
            ;;

        nixos)
            install_nixos_dependencies
            ;;

        nixos-done)
            log_success "Environnement NixOS (ou dérivé, ex: GLF OS) déjà actif."
            ;;

        slackware)
            install_slackware_dependencies
            ;;

        *)
            log_error "Distribution non supportée automatiquement."
            echo ""
            echo "Installez manuellement au minimum :"
            echo "  wine wget cabextract winetricks imagemagick"
            echo ""
            echo "Puis relancez ce script."
            exit 1
            ;;
    esac

    discover_wine_paths
}

install_solus_dependencies() {
    log_info "Solus détecté : installation de Wine 64 bits + Wine 32 bits (eopkg)..."

    sudo eopkg update-repo || sudo eopkg ur || true

    # wine-32bit tire aussi wine 64 bits ; on installe les deux explicitement
    # pour garantir la coexistence Pronote 32 / 64.
    sudo eopkg install -y wine wine-32bit winetricks wget cabextract icoutils \
        desktop-file-utils imagemagick \
        || sudo eopkg install -y wine wine-32bit wget cabextract imagemagick

    sudo eopkg install -y librsvg >/dev/null 2>&1 || true

    check_command winetricks || install_winetricks_standalone || true
    discover_wine_paths
    log_success "Environnement Solus prêt (Wine 32 et 64 bits)."
}

install_alpine_dependencies() {
    log_info "Alpine Linux détecté : préparation des dépôts et de Wine..."

    if [ -f /etc/apk/repositories ]; then
        if ! grep -qE '^[^#].*/community' /etc/apk/repositories; then
            log_info "Activation du dépôt community (nécessaire pour Wine)..."
            sudo sed -i -E 's|^#(.*community.*)|\1|' /etc/apk/repositories || true
        fi
    fi

    sudo apk update || true
    sudo apk add --no-cache bash wget cabextract icoutils desktop-file-utils \
        imagemagick librsvg wine zenity ncurses \
        || sudo apk add --no-cache bash wget wine imagemagick

    sudo apk add --no-cache winetricks >/dev/null 2>&1 || true
    check_command winetricks || install_winetricks_standalone || true

    discover_wine_paths
    log_success "Environnement Alpine prêt."
}

install_void_dependencies() {
    log_info "Void Linux détecté : activation de multilib et installation de Wine 32/64..."

    sudo xbps-install -Sy void-repo-multilib || true
    sudo xbps-install -Sy void-repo-multilib-nonfree >/dev/null 2>&1 || true

    sudo xbps-install -Sy \
        wine wine-32bit wine-tools wine-common libwine libwine-32bit \
        winetricks wget cabextract icoutils desktop-file-utils ImageMagick \
        || sudo xbps-install -Sy wine wget cabextract ImageMagick

    sudo xbps-install -Sy librsvg >/dev/null 2>&1 || true
    check_command winetricks || install_winetricks_standalone || true

    discover_wine_paths
    log_success "Environnement Void prêt (Wine 32 et 64 bits)."
}

install_slackware_dependencies() {
    log_warning "Slackware détecté : support expérimental."
    echo "Wine n'est pas toujours disponible dans les dépôts officiels Slackware."
    echo ""

    if check_command slackpkg; then
        log_info "Tentative d'installation via slackpkg..."
        sudo slackpkg update || true
        sudo slackpkg install wine wget cabextract icoutils desktop-file-utils ImageMagick || true
    fi

    discover_wine_paths

    if [ -z "$WINE_BIN" ]; then
        log_error "Wine n'a pas pu être installé automatiquement sur Slackware."
        echo ""
        echo "Solutions recommandées :"
        echo "  • Dépôt non officiel AlienBOB (Eric Hameleers) : http://www.slackware.com/~alien/"
        echo "  • SlackBuilds.org (compilation depuis les sources) : https://slackbuilds.org/"
        echo ""
        echo "Une fois Wine $MIN_WINE_VERSION ou supérieur installé manuellement,"
        echo "relancez ce script : il détectera Wine automatiquement."
        exit 1
    fi

    if ! check_command winetricks; then
        install_winetricks_standalone || exit 1
    fi

    log_success "Environnement Slackware prêt (vérifiez les avertissements ci-dessus)."
}

# ------------------------------------------------------------------------------
# NixOS / GLF OS
# ------------------------------------------------------------------------------
# Plus de fetchTarball (liens canaux souvent cassés / rebuild complet de Wine).
# On utilise le nixpkgs du système :
#   nix-instantiate --eval -E 'with import <nixpkgs> {}; attr.name'
# puis nix-shell -p.
# Si <nixpkgs> est absent (NixOS flakes), repli sur :
#   nix shell nixpkgs#wineWow64Packages.stable ...
# ------------------------------------------------------------------------------

nixpkgs_has_attr() {
    local attr="$1"
    nix-instantiate --eval -E "with import <nixpkgs> {}; (${attr}).name" >/dev/null 2>&1
}

quote_args() {
    local a
    local out=""
    for a in "$@"; do
        out+=" $(printf '%q' "$a")"
    done
    printf "%s" "$out"
}

install_nixos_dependencies() {
    log_info "NixOS (ou dérivé, ex: GLF OS) détecté : préparation d'un environnement nix-shell..."

    if [ "$IN_NIX_SHELL" = "1" ]; then
        log_success "Déjà dans nix-shell."
        return 0
    fi

    if ! check_command nix-shell && ! check_command nix; then
        log_error "nix-shell / nix est introuvable sur ce système."
        echo "Installez Nix ou activez nix-command, puis relancez."
        exit 1
    fi

    local script_path
    script_path="$(readlink -f "$0" 2>/dev/null || echo "$0")"

    local extra
    extra="$(quote_args "${ALL_ARGS[@]}")"

    local -a wine_attrs=(
        "wineWow64Packages.stable"
        "wineWowPackages.stable"
        "wine64Packages.stable"
        "wine"
    )

    local common_pkgs="winetricks wget cabextract icoutils desktop-file-utils gnutls librsvg imagemagick"
    local attr=""
    local found=""

    if check_command nix-instantiate && check_command nix-shell; then
        log_info "Recherche d'un paquet Wine dans le nixpkgs système (<nixpkgs>)..."
        for attr in "${wine_attrs[@]}"; do
            log_info "  • test de $attr"
            if nixpkgs_has_attr "$attr"; then
                found="$attr"
                log_success "Paquet Wine trouvé : $attr"
                break
            fi
        done

        if [ -n "$found" ]; then
            log_info "Relance du script dans nix-shell (binaires du cache, sans compilation forcée)..."
            # shellcheck disable=SC2086
            exec nix-shell \
                --option substitute true \
                --option builders-use-substitutes true \
                -p $found $common_pkgs \
                --run "bash $(printf '%q' "$script_path") --in-nix-shell${extra}"
        fi

        log_warning "Aucun attribut Wine n'a pu être évalué via <nixpkgs>."
        log_warning "Le canal système est peut-être absent (NixOS flakes)."
    fi

    if check_command nix; then
        log_info "Repli flakes : nix shell nixpkgs#wineWow64Packages.stable ..."
        exec nix --extra-experimental-features 'nix-command flakes' shell \
            nixpkgs#wineWow64Packages.stable \
            nixpkgs#winetricks \
            nixpkgs#wget \
            nixpkgs#cabextract \
            nixpkgs#icoutils \
            nixpkgs#desktop-file-utils \
            nixpkgs#gnutls \
            nixpkgs#librsvg \
            nixpkgs#imagemagick \
            --command bash -lc "bash $(printf '%q' "$script_path") --in-nix-shell${extra}"
    fi

    log_error "Impossible de construire un environnement Wine sur NixOS."
    echo ""
    echo "Ajoutez par exemple dans configuration.nix :"
    echo "  environment.systemPackages = with pkgs; ["
    echo "    wineWow64Packages.stable"
    echo "    winetricks wget cabextract icoutils desktop-file-utils imagemagick"
    echo "  ];"
    echo "puis : sudo nixos-rebuild switch"
    echo "et relancez ce script."
    exit 1
}

ensure_dependencies() {
    ensure_privilege_helper
    discover_wine_paths

    if ! wine_is_available; then
        log_warning "Wine n'est pas installé (ou hors PATH)."
        install_dependencies
        discover_wine_paths
    else
        local wine_ver
        wine_ver="$(get_wine_version)"

        log_success "Wine détecté : version $wine_ver  ($WINE_BIN)"

        if version_lt "$wine_ver" "$MIN_WINE_VERSION"; then
            log_warning "Wine $wine_ver est inférieur à la version recommandée $MIN_WINE_VERSION."
            echo "Index Éducation indique Wine $MIN_WINE_VERSION minimum pour éviter certains problèmes, notamment libcef.dll."
            echo ""
            if [ "$ASSUME_YES" = "0" ]; then
                read -rp "Voulez-vous tenter une mise à jour via le gestionnaire de paquets ? [O/n] : " answer
                case "$answer" in
                    n|N|non|Non|NON)
                        log_warning "Poursuite sans mise à jour de Wine."
                        ;;
                    *)
                        install_dependencies
                        discover_wine_paths
                        ;;
                esac
            else
                log_warning "Mise à jour de Wine en cours..."
                install_dependencies
                discover_wine_paths
            fi
        fi
    fi

    if ! wine_is_available; then
        log_error "Wine reste introuvable après l'installation des dépendances."
        print_wine_diagnostics
        echo "Sous Ubuntu / Kubuntu 26.04, vérifiez :"
        echo "  ls /opt/wine-stable/bin/wine /opt/wine-stable/bin/wineboot"
        echo "  export PATH=\"/opt/wine-stable/bin:\$PATH\""
        exit 1
    fi

    local missing=()

    check_command wget || missing+=("wget")
    check_command cabextract || missing+=("cabextract")
    check_command winetricks || missing+=("winetricks")

    if ! check_command magick && ! check_command convert && ! check_command ffmpeg; then
        missing+=("imagemagick")
    fi

    if [ "${#missing[@]}" -gt 0 ]; then
        log_warning "Dépendances manquantes : ${missing[*]}"
        install_dependencies
        discover_wine_paths
    fi

    if ! check_command winetricks; then
        install_winetricks_standalone || true
    fi
}

# ==============================================================================
# Choix version Pronote
# ==============================================================================

process_custom_url() {
    PRONOTE_URL="${PRONOTE_URL_FROM_OPTION}"

    if [[ "$PRONOTE_URL" =~ win32 ]]; then
        PRONOTE_ARCH="32"
    elif [[ "$PRONOTE_URL" =~ win64 ]]; then
        PRONOTE_ARCH="64"
    else
        log_warning "Impossible de déterminer l'architecture depuis l'URL. Utilisation de 64 bits par défaut."
        PRONOTE_ARCH="64"
    fi

    if [[ "$PRONOTE_URL" =~ (20[0-9]{2})\.([0-9]+\.[0-9]+) ]]; then
        PRONOTE_YEAR="${BASH_REMATCH[1]}"
        PRONOTE_VERSION="${BASH_REMATCH[0]}"
    else
        log_warning "Impossible d'extraire la version depuis l'URL. Utilisation des valeurs par défaut."
        PRONOTE_YEAR="$DEFAULT_YEAR"
        PRONOTE_VERSION="$DEFAULT_VERSION"
    fi

    log_success "URL personnalisée : $PRONOTE_URL"
}

get_pronote_url() {
    if [ -n "${PRONOTE_URL_FROM_OPTION:-}" ]; then
        process_custom_url
        return
    fi

    if [ -n "${PRONOTE_ARCH_FROM_OPTION:-}" ]; then
        PRONOTE_ARCH="$PRONOTE_ARCH_FROM_OPTION"
        if [ "$PRONOTE_ARCH" = "32" ]; then
            PRONOTE_URL="$URL_32"
        else
            PRONOTE_URL="$URL_64"
        fi
        log_success "Version sélectionnée : Pronote $PRONOTE_VERSION - ${PRONOTE_ARCH} bits"
        return
    fi

    echo ""
    box_title "Choix de la version Pronote" 46
    echo ""
    echo "Les deux architectures peuvent être installées simultanément :"
    echo "chacune utilise son propre préfixe Wine et son propre désinstallateur."
    echo ""
    echo "1) 64 bits - recommandé (toutes distributions)"
    echo "2) 32 bits - utile en cas de souci d'affichage ou de compatibilité"
    echo ""
    echo "Vous pouvez aussi coller une URL personnalisée d'installateur."
    echo ""

    local user_choice
    user_choice="$(ask_user "Choix [1/2 ou URL] [Entrée=1] : " "1")"

    case "$user_choice" in
        2)
            PRONOTE_URL="$URL_32"
            PRONOTE_ARCH="32"
            ;;
        http://*|https://*)
            PRONOTE_URL="$user_choice"
            if [[ "$PRONOTE_URL" =~ win32 ]]; then
                PRONOTE_ARCH="32"
            else
                PRONOTE_ARCH="64"
            fi
            ;;
        *)
            PRONOTE_URL="$URL_64"
            PRONOTE_ARCH="64"
            ;;
    esac

    if [[ "$PRONOTE_URL" =~ (20[0-9]{2})\.([0-9]+\.[0-9]+) ]]; then
        PRONOTE_YEAR="${BASH_REMATCH[1]}"
        PRONOTE_VERSION="${BASH_REMATCH[0]}"
    else
        PRONOTE_YEAR="$DEFAULT_YEAR"
        PRONOTE_VERSION="$DEFAULT_VERSION"
    fi

    log_success "Version sélectionnée : Pronote $PRONOTE_VERSION - ${PRONOTE_ARCH} bits"
}

# ==============================================================================
# Configuration Wine
# ==============================================================================

force_windows_version() {
    if [ -z "${WINE_BIN:-}" ]; then
        discover_wine_paths
    fi
    if [ -z "${WINE_BIN:-}" ]; then
        return 0
    fi

    local cur_build product release wine_ver
    if [ "$WIN_VERSION" = "win10" ]; then
        cur_build="19045"
        product="Windows 10 Pro"
        release="2009"
        wine_ver="win10"
    else
        cur_build="22631"
        product="Windows 11 Pro"
        release="23H2"
        wine_ver="win11"
    fi

    log_info "Forçage de la version Windows ($product) dans les deux vues de registre (32/64 bits)..."

    local key="HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion"
    local view

    for view in 32 64; do
        run_wine_bin reg add "$key" /v CurrentVersion            /t REG_SZ    /d "10.0"        /f /reg:$view >/dev/null 2>&1 || true
        run_wine_bin reg add "$key" /v CurrentBuild              /t REG_SZ    /d "$cur_build"  /f /reg:$view >/dev/null 2>&1 || true
        run_wine_bin reg add "$key" /v CurrentBuildNumber        /t REG_SZ    /d "$cur_build"  /f /reg:$view >/dev/null 2>&1 || true
        run_wine_bin reg add "$key" /v CurrentMajorVersionNumber /t REG_DWORD /d 10            /f /reg:$view >/dev/null 2>&1 || true
        run_wine_bin reg add "$key" /v CurrentMinorVersionNumber /t REG_DWORD /d 0             /f /reg:$view >/dev/null 2>&1 || true
        run_wine_bin reg add "$key" /v ProductName               /t REG_SZ    /d "$product"    /f /reg:$view >/dev/null 2>&1 || true
        run_wine_bin reg add "$key" /v ReleaseId                 /t REG_SZ    /d "$release"    /f /reg:$view >/dev/null 2>&1 || true
        run_wine_bin reg add "HKCU\\Software\\Wine" /v Version   /t REG_SZ    /d "$wine_ver"   /f /reg:$view >/dev/null 2>&1 || true
    done

    run_wineserver_tool -w >/dev/null 2>&1 || true
}

configure_wine() {
    echo ""
    box_title "Configuration de Wine" 46
    echo ""

    discover_wine_paths
    set_wineprefix

    if [ -z "$WINE_BIN" ]; then
        log_error "Wine est introuvable au moment de créer le préfixe."
        print_wine_diagnostics
        exit 1
    fi

    # Évite les pop-ups Gecko/Mono pendant l'init du préfixe.
    export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree,mshtml=}"

    local prefix_arch
    prefix_arch="$(detect_prefix_arch)"

    if [ "$prefix_arch" = "none" ]; then
        log_info "Création d'un nouveau préfixe Wine : $WINEPREFIX"
        choose_winearch_for_new_prefix

        if ! run_quiet "Initialisation du préfixe Wine" run_wineboot_tool --init; then
            log_warning "Premier essai d'initialisation en échec. Recalcul du PATH Wine..."
            discover_wine_paths
            print_wine_diagnostics
            if ! run_quiet "Nouvel essai d'initialisation du préfixe Wine" run_wineboot_tool --init; then
                log_error "Impossible d'initialiser le préfixe Wine."
                echo "Sous Kubuntu / Ubuntu 26.04, ajoutez WineHQ au PATH puis relancez :"
                echo "  export PATH=\"/opt/wine-stable/bin:\$PATH\""
                echo "  hash -r"
                echo "  wine --version && wineboot --init"
                exit 1
            fi
        fi
    else
        log_info "Préfixe Wine existant conservé : $WINEPREFIX"
        log_info "Architecture détectée du préfixe : ${prefix_arch} bits"

        if [ "$prefix_arch" = "32" ] && [ "$PRONOTE_ARCH" = "64" ]; then
            echo ""
            log_warning "Le préfixe ciblé est en 32 bits alors que Pronote 64 bits est demandé."
            echo ""
            echo "Solutions possibles :"
            echo "  1) Installer Pronote 32 bits dans ce préfixe."
            echo "  2) Supprimer ou renommer le préfixe, puis relancer ce script."
            echo ""
            local answer
            answer="$(ask_user "Basculer automatiquement vers l'installateur Pronote 32 bits ? [O/n] : " "O")"

            case "$answer" in
                n|N|non|Non|NON)
                    log_error "Installation interrompue pour éviter une erreur d'architecture."
                    echo ""
                    echo "Vous pouvez par exemple faire :"
                    echo "  rm -rf \"$WINEPREFIX\""
                    echo "puis relancer le script."
                    exit 1
                    ;;
                *)
                    PRONOTE_URL="$URL_32"
                    PRONOTE_ARCH="32"
                    log_warning "Installation basculée vers Pronote 32 bits."
                    set_wineprefix
                    ;;
            esac
        fi

        run_quiet "Mise à jour du préfixe Wine" run_wineboot_tool --init || true
    fi

    if [ "$WIN_VERSION" = "win10" ]; then
        log_info "Configuration de la version Windows vue par Wine : Windows 10"
    else
        log_info "Configuration de la version Windows vue par Wine : Windows 11"
    fi

    run_quiet "Configuration Windows" run_winecfg_tool /v "$WIN_VERSION" || true

    force_windows_version

    local winetricks_cmd=""
    if check_command winetricks; then
        winetricks_cmd="$(command -v winetricks)"
    else
        log_warning "winetricks est introuvable. Certains composants ne seront pas installés."
    fi

    if [ -n "$winetricks_cmd" ]; then
        log_info "Installation des composants Windows utiles à Pronote."
        export WINE="${WINE_BIN:-wine}"
        if [ -n "$WINESERVER_BIN" ]; then
            export WINESERVER="$WINESERVER_BIN"
        fi

        if ! run_quiet "Installation des polices Microsoft" "$winetricks_cmd" -q corefonts; then
            log_warning "Installation partielle ou impossible de corefonts. Ce n'est pas forcément bloquant."
        fi

        if ! run_quiet "Installation de windowscodecs" "$winetricks_cmd" -q windowscodecs; then
            log_warning "windowscodecs non installé ou partiellement installé. Ce n'est pas forcément bloquant."
        fi
    fi

    force_windows_version
}

# ==============================================================================
# Téléchargement avec fallback (tele3 -> tele2 -> tele1)
# ==============================================================================

download_with_fallback() {
    local output="$1"
    shift
    local url

    for url in "$@"; do
        log_info "Tentative de téléchargement : $url"
        rm -f "$output" 2>/dev/null || true

        if wget --progress=bar:force:noscroll --tries=2 --timeout=30 "$url" -O "$output" 2>&1; then
            log_success "Téléchargement réussi depuis : $url"
            return 0
        else
            log_warning "Échec depuis $url. Essai du serveur suivant..."
            rm -f "$output" 2>/dev/null || true
        fi
    done

    log_error "Tous les serveurs ont échoué pour le téléchargement."
    return 1
}

verify_installer() {
    local file="$1"

    if [ ! -s "$file" ]; then
        log_error "Le fichier d'installation est vide ou introuvable."
        return 1
    fi

    if command -v file >/dev/null 2>&1; then
        if ! file "$file" | grep -qiE "PE32|MS-DOS executable|executable"; then
            log_error "Le fichier téléchargé ne ressemble pas à un exécutable Windows."
            log_error "URL peut être corrompue ou serveur compromis."
            return 1
        fi
    fi

    return 0
}

# ==============================================================================
# Installation Pronote
# ==============================================================================

install_pronote() {
    echo ""
    box_title "Installation de Pronote Client" 46
    echo ""

    local installer="$TMP_DIR/InstallPronote-${PRONOTE_YEAR}-${PRONOTE_ARCH}.exe"

    log_info "Téléchargement de l'installateur Pronote ${PRONOTE_ARCH} bits..."
    echo "URL cible : $PRONOTE_URL"
    echo ""

    local -a urls=()

    if [ -n "${PRONOTE_URL_FROM_OPTION:-}" ]; then
        urls=("$PRONOTE_URL")
    else
        local base_url
        if [ "$PRONOTE_ARCH" = "32" ]; then
            base_url="$URL_32"
        else
            base_url="$URL_64"
        fi

        urls=(
            "$base_url"
            "${base_url/tele3/tele2}"
            "${base_url/tele3/tele1}"
        )
    fi

    download_with_fallback "$installer" "${urls[@]}" || exit 1

    verify_installer "$installer" || exit 1

    echo ""
    log_warning "Une fenêtre d'installation Windows va s'ouvrir."
    echo ""
    echo "Conseils pendant l'installation :"
    echo "  • Décochez si possible : « Créer un raccourci sur le bureau »."
    echo "  • Décochez si possible : « Lancer Pronote après installation »."
    echo "  • Laissez l'installation se terminer normalement."
    echo ""
    echo "Remarque : une fois l'assistant fermé, l'installation peut encore"
    echo "travailler quelques secondes en arrière-plan (enregistrement de"
    echo "services). Le message affiché vous préviendra automatiquement."
    echo ""

    if [ "$ASSUME_YES" = "0" ]; then
        read -rp "Appuyez sur Entrée pour lancer l'installateur..."
    else
        echo "(mode automatique : poursuite sans attente)"
    fi

    RUN_QUIET_ACTIVITY_DIR="$WINEPREFIX/drive_c"
    RUN_QUIET_FINALIZE_MSG="Installation Pronote : finalisation en cours, veuillez patienter quelques secondes..."

    run_quiet "Installation Pronote en cours" run_wine_bin "$installer"

    RUN_QUIET_ACTIVITY_DIR=""
    RUN_QUIET_FINALIZE_MSG=""

    rm -f "$installer"
}

# ==============================================================================
# Icône et raccourcis
# ==============================================================================

icon_has_any_raster_size() {
    local name="$1"
    local size

    for size in "${ICON_SIZES[@]}"; do
        [ -f "$ICON_BASE_DIR/${size}x${size}/apps/${name}.png" ] && return 0
    done

    return 1
}

is_image_file() {
    local f="$1"
    [ -s "$f" ] || return 1

    if check_command file; then
        file -b "$f" | grep -qiE 'JPEG|JFIF|PNG|WebP|bitmap|raster|image data|PC bitmap'
        return $?
    fi

    local magic
    magic="$(od -An -tx1 -N4 "$f" 2>/dev/null | tr -d ' \n')"
    case "$magic" in
        ffd8ffe0|ffd8ffe1|ffd8ffe2|ffd8ffdb|ffd8ffee) return 0 ;;
        89504e47) return 0 ;;
    esac

    [ "${magic:0:4}" = "ffd8" ]
}

find_image_converter() {
    if check_command magick; then echo "magick"; return 0; fi
    if check_command convert; then echo "convert"; return 0; fi
    if check_command ffmpeg; then echo "ffmpeg"; return 0; fi
    if check_command gm; then echo "gm"; return 0; fi
    if check_command python3 && python3 -c "from PIL import Image" >/dev/null 2>&1; then
        echo "pillow"
        return 0
    fi
    echo ""
    return 1
}

convert_one_png() {
    local src="$1"
    local dest="$2"
    local size="$3"
    local converter="$4"

    case "$converter" in
        magick)  magick "$src" -resize "${size}x${size}" "$dest" 2>/dev/null ;;
        convert) convert "$src" -resize "${size}x${size}" "$dest" 2>/dev/null ;;
        ffmpeg)  ffmpeg -y -loglevel error -i "$src" -vf "scale=${size}:${size}" "$dest" >/dev/null 2>&1 ;;
        gm)      gm convert "$src" -resize "${size}x${size}" "$dest" 2>/dev/null ;;
        pillow)
            python3 - "$src" "$dest" "$size" << 'PY'
import sys
from PIL import Image
src, dest, size = sys.argv[1], sys.argv[2], int(sys.argv[3])
img = Image.open(src)
img = img.convert("RGBA")
try:
    resample = Image.Resampling.LANCZOS
except AttributeError:
    resample = Image.LANCZOS
img = img.resize((size, size), resample)
img.save(dest, "PNG")
PY
            ;;
        *) return 1 ;;
    esac
}

convert_image_to_pngs() {
    local src="$1"
    local icon_name="$2"
    local converter
    converter="$(find_image_converter || true)"

    if [ -z "$converter" ]; then
        log_warning "Aucun convertisseur d'image trouvé (ImageMagick, ffmpeg ou Pillow)."
        return 1
    fi

    local size target_dir target_file
    local installed=0

    for size in "${ICON_SIZES[@]}"; do
        target_dir="$ICON_BASE_DIR/${size}x${size}/apps"
        target_file="$target_dir/${icon_name}.png"
        mkdir -p "$target_dir"
        rm -f "$target_file"

        if convert_one_png "$src" "$target_file" "$size" "$converter" \
            && [ -s "$target_file" ]; then
            installed=1
        else
            rm -f "$target_file"
        fi
    done

    [ "$installed" -eq 1 ]
}

extract_icon_from_exe() {
    local exe_path="$1"
    local icon_name="$2"

    if ! check_command wrestool || ! check_command icotool; then
        return 1
    fi

    if [ -z "$exe_path" ] || [ ! -f "$exe_path" ]; then
        return 1
    fi

    local tmp_dir
    tmp_dir="$(mktemp -d /tmp/pronote-icon-XXXXXX)"

    (
        cd "$tmp_dir" || exit 0
        wrestool -x -t14 "$exe_path" -o group.ico 2>/dev/null \
            || wrestool -x -t3 "$exe_path" -o group.ico 2>/dev/null || true
        [ -s group.ico ] && icotool -x group.ico 2>/dev/null || true
    )

    local f base size target_dir installed=0

    for f in "$tmp_dir"/*.png; do
        [ -e "$f" ] || continue
        base="$(basename "$f")"

        if [[ "$base" =~ _([0-9]+)x[0-9]+x[0-9]+\.png$ ]]; then
            size="${BASH_REMATCH[1]}"
        else
            continue
        fi

        local target_size
        for target_size in "${ICON_SIZES[@]}"; do
            if [ "$size" -eq "$target_size" ]; then
                target_dir="$ICON_BASE_DIR/${target_size}x${target_size}/apps"
                mkdir -p "$target_dir"
                cp -f "$f" "$target_dir/${icon_name}.png"
                installed=1
            fi
        done
    done

    rm -rf "$tmp_dir"

    [ "$installed" -eq 1 ]
}

rasterize_svg_to_pngs() {
    local svg_file="$1"
    local icon_name="$2"
    local renderer=""

    if check_command rsvg-convert; then
        renderer="rsvg-convert"
    elif check_command inkscape; then
        renderer="inkscape"
    elif check_command magick; then
        renderer="magick"
    elif check_command convert; then
        renderer="convert"
    else
        return 0
    fi

    local size target_dir target_file

    for size in "${ICON_SIZES[@]}"; do
        target_dir="$ICON_BASE_DIR/${size}x${size}/apps"
        target_file="$target_dir/${icon_name}.png"

        [ -f "$target_file" ] && continue

        mkdir -p "$target_dir"

        case "$renderer" in
            rsvg-convert)
                rsvg-convert -w "$size" -h "$size" "$svg_file" -o "$target_file" 2>/dev/null || true
                ;;
            inkscape)
                inkscape "$svg_file" --export-type=png --export-width="$size" \
                    --export-height="$size" --export-filename="$target_file" >/dev/null 2>&1 || true
                ;;
            magick)
                magick -background none -resize "${size}x${size}" "$svg_file" "$target_file" 2>/dev/null || true
                ;;
            convert)
                convert -background none -resize "${size}x${size}" "$svg_file" "$target_file" 2>/dev/null || true
                ;;
        esac

        [ -s "$target_file" ] || rm -f "$target_file"
    done
}

refresh_icon_caches() {
    gtk-update-icon-cache -f -t "$ICON_BASE_DIR" 2>/dev/null || true
    command -v update-icon-caches >/dev/null 2>&1 && update-icon-caches "$ICON_BASE_DIR" 2>/dev/null || true

    rm -f "$HOME/.cache/icon-cache.kcache" 2>/dev/null || true
    kbuildsycoca6 --noincremental 2>/dev/null || true
    kbuildsycoca5 --noincremental 2>/dev/null || true

    touch "$ICON_BASE_DIR" 2>/dev/null || true
    command -v xdg-desktop-menu >/dev/null 2>&1 && xdg-desktop-menu forceupdate 2>/dev/null || true
}

install_pixmap_and_xdg_icon() {
    local icon_name="$1"
    local size png

    mkdir -p "$PIXMAP_DIR"

    for size in 256 128 64 48; do
        png="$ICON_BASE_DIR/${size}x${size}/apps/${icon_name}.png"
        if [ -s "$png" ]; then
            cp -f "$png" "$PIXMAP_DIR/${icon_name}.png"
            break
        fi
    done

    if check_command xdg-icon-resource; then
        for size in "${ICON_SIZES[@]}"; do
            png="$ICON_BASE_DIR/${size}x${size}/apps/${icon_name}.png"
            if [ -s "$png" ]; then
                xdg-icon-resource install --novendor --size "$size" "$png" "$icon_name" 2>/dev/null || true
            fi
        done
    fi
}

resolve_icon_path() {
    local icon_name="$1"
    local size candidate

    for size in 256 128 64 48 32 24 22 16; do
        candidate="$ICON_BASE_DIR/${size}x${size}/apps/${icon_name}.png"
        if [ -s "$candidate" ]; then
            printf '%s' "$candidate"
            return 0
        fi
    done

    candidate="$PIXMAP_DIR/${icon_name}.png"
    if [ -s "$candidate" ]; then
        printf '%s' "$candidate"
        return 0
    fi

    candidate="$ICON_DIR/${icon_name}.svg"
    if [ -s "$candidate" ]; then
        printf '%s' "$candidate"
        return 0
    fi

    printf '%s' "$icon_name"
}

fetch_and_install_icon() {
    local exe_path="$1"
    local icon_name="pronote-${PRONOTE_YEAR}"
    local svg_target="$ICON_DIR/${icon_name}.svg"
    local jpg_tmp="$TMP_DIR/pronote-icon-source"
    local got_raster=0
    local svg_ok=0

    mkdir -p "$ICON_DIR" "$PIXMAP_DIR"

    log_info "Téléchargement de l'icône Pronote par défaut..."

    if wget -q --timeout=20 --tries=3 -L \
            --user-agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 PronoteInstaller/4.6" \
            "$PRONOTE_ICON_URL" -O "$jpg_tmp" \
        && is_image_file "$jpg_tmp"; then
        if convert_image_to_pngs "$jpg_tmp" "$icon_name"; then
            got_raster=1
            log_success "Icône PNG installée depuis l'image par défaut."
        else
            log_warning "L'image a été téléchargée, mais la conversion en PNG a échoué."
        fi
    else
        rm -f "$jpg_tmp"
        log_warning "Icône par défaut indisponible ou fichier invalide."
    fi

    if [ "$got_raster" -eq 0 ]; then
        log_info "Tentative d'extraction de l'icône embarquée dans le programme..."
        if extract_icon_from_exe "$exe_path" "$icon_name"; then
            got_raster=1
            log_success "Icône extraite directement du programme Pronote."
        else
            log_warning "Extraction depuis l'exécutable impossible ou icoutils absent."
        fi
    fi

    if [ "$got_raster" -eq 0 ]; then
        log_warning "Aucune icône récupérée : création d'une icône de secours minimaliste."
        cat > "$svg_target" << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  <rect width="256" height="256" rx="42" fill="#2f80ed"/>
  <circle cx="128" cy="128" r="78" fill="#ffffff" opacity="0.95"/>
  <text x="128" y="145" font-size="54" text-anchor="middle" font-family="Arial, sans-serif" font-weight="bold" fill="#2f80ed">PN</text>
</svg>
EOF
        svg_ok=1
    fi

    if [ "$svg_ok" -eq 1 ] && [ -f "$svg_target" ]; then
        rasterize_svg_to_pngs "$svg_target" "$icon_name"
    fi

    install_pixmap_and_xdg_icon "$icon_name"
    refresh_icon_caches

    echo "$icon_name"
}

find_pronote_exe() {
    local -a files=()

    while IFS= read -r -d '' f; do
        if [[ "$f" == *"$PRONOTE_YEAR"* ]]; then
            files+=("$f")
        fi
    done < <(find "$WINEPREFIX/drive_c" -type f \
        \( -iname "Client PRONOTE*.exe" -o -iname "PRONOTE*.exe" -o -iname "*Pronote*.exe" \) \
        -print0 2>/dev/null || true)

    if [ ${#files[@]} -eq 0 ]; then
        while IFS= read -r -d '' f; do
            files+=("$f")
        done < <(find "$WINEPREFIX/drive_c" -type f \
            \( -iname "Client PRONOTE*.exe" -o -iname "PRONOTE*.exe" -o -iname "*Pronote*.exe" \) \
            -print0 2>/dev/null || true)
    fi

    echo "${files[0]:-}"
}

# ==============================================================================
# Ajout de ~/.local/bin au PATH
# ==============================================================================

ensure_path_in_shell_rc() {
    local shell_name
    shell_name="$(basename "${SHELL:-/bin/bash}")"

    local rc_file=""
    local path_line=""

    case "$shell_name" in
        zsh)
            rc_file="$HOME/.zshrc"
            path_line="export PATH=\"$BIN_DIR:\$PATH\""
            ;;
        fish)
            rc_file="$HOME/.config/fish/config.fish"
            path_line="set -gx PATH \$PATH $BIN_DIR"
            ;;
        *)
            rc_file="$HOME/.bashrc"
            path_line="export PATH=\"$BIN_DIR:\$PATH\""
            ;;
    esac

    local files_to_patch=("$rc_file")

    if [ "$shell_name" != "fish" ]; then
        files_to_patch+=("$HOME/.profile")
    fi

    local f
    for f in "${files_to_patch[@]}"; do
        if [ -f "$f" ] && grep -qF "$BIN_DIR" "$f" 2>/dev/null; then
            log_info "Le dossier '$BIN_DIR' est déjà configuré dans $f."
            continue
        fi

        mkdir -p "$(dirname "$f")"
        touch "$f"

        {
            echo ""
            echo "# >>> Ajouté par le script d'installation Pronote >>>"
            echo "# Commandes : pronote-${PRONOTE_YEAR}, pronote-desinstaller-32, pronote-desinstaller-64"
            echo "$path_line"
            echo "# <<< Ajouté par le script d'installation Pronote <<<"
        } >> "$f"

        log_success "Le dossier '$BIN_DIR' a été ajouté au PATH dans $f."
    done

    case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *) export PATH="$BIN_DIR:$PATH" ;;
    esac
    hash -r 2>/dev/null || true
}

# ==============================================================================
# Raccourci bureau universel
# ==============================================================================

create_desktop_shortcut() {
    local desktop_file_source="$1"
    local -a desktop_dirs=()
    local d

    if check_command xdg-user-dir; then
        d="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
        if [ -n "$d" ] && [ -d "$d" ]; then
            desktop_dirs+=("$d")
        fi
    fi

    for d in "$HOME/Bureau" "$HOME/Desktop"; do
        [ -d "$d" ] || continue
        local already=0
        local existing
        for existing in "${desktop_dirs[@]:-}"; do
            [ "$existing" = "$d" ] && already=1
        done
        [ "$already" -eq 0 ] && desktop_dirs+=("$d")
    done

    if [ "${#desktop_dirs[@]}" -eq 0 ]; then
        log_info "Aucun dossier Bureau/Desktop détecté : raccourci bureau non créé."
        return 0
    fi

    local target
    for d in "${desktop_dirs[@]}"; do
        target="$d/pronote-${PRONOTE_YEAR}-${PRONOTE_ARCH}.desktop"
        cp -f "$desktop_file_source" "$target"
        chmod +x "$target"

        if check_command gio; then
            gio set "$target" metadata::trusted true 2>/dev/null || true
        fi

        log_success "Raccourci bureau créé : $target"
    done
}

# ==============================================================================
# Création des lanceurs et des raccourcis
# ==============================================================================

create_launchers() {
    echo ""
    box_title "Creation des raccourcis Linux" 46
    echo ""

    mkdir -p "$BIN_DIR" "$APP_DIR" "$ICON_DIR" "$PIXMAP_DIR"
    discover_wine_paths

    local real_exe
    real_exe="$(find_pronote_exe)"

    if [ -z "$real_exe" ]; then
        log_warning "Exécutable Pronote non trouvé automatiquement."
        log_warning "Un chemin générique sera utilisé."
        real_exe="$WINEPREFIX/drive_c/Program Files/Index Education/PRONOTE ${PRONOTE_YEAR}/Client PRONOTE.exe"
    fi

    log_info "Exécutable utilisé : $real_exe"

    local icon_name
    icon_name="$(fetch_and_install_icon "$real_exe")"
    local icon_file
    icon_file="$(resolve_icon_path "$icon_name")"
    log_info "Icône utilisée : $icon_file"

    local launcher="$BIN_DIR/pronote-${PRONOTE_YEAR}-${PRONOTE_ARCH}"
    local launcher_log_dir="$HOME/.local/share/pronote-${PRONOTE_YEAR}-${PRONOTE_ARCH}"
    local wine_for_launcher="${WINE_BIN:-wine}"
    local wineserver_for_launcher="${WINESERVER_BIN:-}"
    local wine_dir_for_launcher=""
    wine_dir_for_launcher="$(dirname "$wine_for_launcher")"

    mkdir -p "$launcher_log_dir"

    cat > "$launcher" << EOF
#!/usr/bin/env bash
# Lanceur Pronote ${PRONOTE_YEAR} (${PRONOTE_ARCH} bits) - généré automatiquement

export WINEPREFIX="$WINEPREFIX"
export WINEDEBUG="-nls"
export PATH="$wine_dir_for_launcher:\$PATH"
export WINE="$wine_for_launcher"
$(if [ -n "$wineserver_for_launcher" ]; then echo "export WINESERVER=\"$wineserver_for_launcher\""; fi)

LOG_DIR="$launcher_log_dir"
LOG_FILE="\$LOG_DIR/pronote.log"

mkdir -p "\$LOG_DIR"

if [ -f "\$LOG_FILE" ] && [ "\$(wc -c < "\$LOG_FILE" 2>/dev/null || echo 0)" -gt 10485760 ]; then
    mv "\$LOG_FILE" "\$LOG_FILE.1" 2>/dev/null || true
fi

CACHE_DIRS=(
    "\$WINEPREFIX/drive_c/ProgramData/IndexEducation/PRONOTE/CLIENT"
    "\$WINEPREFIX/drive_c/users/\$USER/AppData/Local/IndexEducation/PRONOTE/CLIENT"
)

for CACHE_DIR in "\${CACHE_DIRS[@]}"; do
    if [ -d "\$CACHE_DIR" ]; then
        find "\$CACHE_DIR" -type d -name "Cache" -exec rm -rf {} + 2>/dev/null || true
    fi
done

if [ "\${PRONOTE_DEBUG:-0}" = "1" ]; then
    exec "$wine_for_launcher" "$real_exe" "\$@"
else
    exec "$wine_for_launcher" "$real_exe" "\$@" >> "\$LOG_FILE" 2>&1
fi
EOF

    chmod +x "$launcher"
    ln -sf "$launcher" "$BIN_DIR/pronote-${PRONOTE_YEAR}"
    log_success "Lanceur créé : $launcher"
    log_info "Alias générique : $BIN_DIR/pronote-${PRONOTE_YEAR}"

    local desktop_file="$APP_DIR/pronote-${PRONOTE_YEAR}-${PRONOTE_ARCH}.desktop"

    cat > "$desktop_file" << EOF
[Desktop Entry]
Name=Pronote Client ${PRONOTE_YEAR} (${PRONOTE_ARCH} bits)
GenericName=Client Pronote
Comment=Client Pronote ${PRONOTE_YEAR} ${PRONOTE_ARCH} bits via Wine
Exec=$launcher
Terminal=false
Type=Application
Icon=$icon_file
Categories=Education;Office;
StartupNotify=true
Keywords=pronote;education;ecole;college;lycee;
EOF

    chmod +x "$desktop_file"
    log_success "Raccourci menu créé : $desktop_file"

    update-desktop-database "$APP_DIR" 2>/dev/null || true
    refresh_icon_caches

    if [ -d "$APP_DIR/wine/Programs" ]; then
        find "$APP_DIR/wine/Programs" -maxdepth 1 \
            \( -iname "PRONOTE*" -o -iname "Index Education*" \) \
            -exec rm -rf {} + 2>/dev/null || true
    fi

    ensure_path_in_shell_rc

    create_desktop_shortcut "$desktop_file"

    create_uninstaller "$desktop_file" "$launcher" "$icon_file" "$icon_name"
    create_uninstaller_dispatcher
}

# ==============================================================================
# Désinstallateur (un par architecture)
# ==============================================================================

create_uninstaller() {
    local desktop_file="$1"
    local launcher="$2"
    local icon_file="$3"
    local icon_name="$4"
    local uninstaller="$BIN_DIR/pronote-desinstaller-${PRONOTE_ARCH}"
    local wine_for_uninstaller="${WINE_BIN:-wine}"
    local wineserver_for_uninstaller="${WINESERVER_BIN:-wineserver}"

    local q_wineprefix q_desktop_file q_launcher q_icon_file q_app_dir q_icon_base_dir q_icon_name q_pixmap_dir q_bin_dir q_wine q_wineserver
    printf -v q_wineprefix    '%q' "$WINEPREFIX"
    printf -v q_desktop_file  '%q' "$desktop_file"
    printf -v q_launcher      '%q' "$launcher"
    printf -v q_icon_file     '%q' "$icon_file"
    printf -v q_app_dir       '%q' "$APP_DIR"
    printf -v q_icon_base_dir '%q' "$ICON_BASE_DIR"
    printf -v q_icon_name     '%q' "$icon_name"
    printf -v q_pixmap_dir    '%q' "$PIXMAP_DIR"
    printf -v q_bin_dir       '%q' "$BIN_DIR"
    printf -v q_wine          '%q' "$wine_for_uninstaller"
    printf -v q_wineserver    '%q' "$wineserver_for_uninstaller"

    cat > "$uninstaller" << EOF
#!/usr/bin/env bash
# Désinstallateur Pronote ${PRONOTE_YEAR} (${PRONOTE_ARCH} bits) - généré automatiquement

set -u

WINEPREFIX=$q_wineprefix
DESKTOP_FILE=$q_desktop_file
LAUNCHER=$q_launcher
ICON_FILE=$q_icon_file
ICON_NAME=$q_icon_name
APP_DIR=$q_app_dir
ICON_BASE_DIR=$q_icon_base_dir
PIXMAP_DIR=$q_pixmap_dir
BIN_DIR=$q_bin_dir
WINE_BIN=$q_wine
WINESERVER_BIN=$q_wineserver
PRONOTE_ARCH="${PRONOTE_ARCH}"
LOG_DIR="\$HOME/.local/share/pronote-installer"
LOG_FILE="\$LOG_DIR/desinstallation-${PRONOTE_YEAR}-${PRONOTE_ARCH}-\$(date +%Y%m%d-%H%M%S).log"
WINEDEBUG_QUIET="-all"
SHOW_WINE_LOGS="0"
RUN_QUIET_ACTIVITY_DIR=""
RUN_QUIET_FINALIZE_MSG=""

export WINEPREFIX
export WINE="\$WINE_BIN"
export WINESERVER="\$WINESERVER_BIN"
export PATH="\$(dirname "\$WINE_BIN"):\$PATH"

GREEN='\\033[0;32m'
YELLOW='\\033[1;33m'
RED='\\033[0;31m'
BLUE='\\033[0;34m'
NC='\\033[0m'

log_info()    { echo -e "\${BLUE}ℹ️  \$*\${NC}" >&2; }
log_success() { echo -e "\${GREEN}✅ \$*\${NC}" >&2; }
log_warning() { echo -e "\${YELLOW}⚠️  \$*\${NC}" >&2; }
log_error()   { echo -e "\${RED}❌ \$*\${NC}" >&2; }

repeat_char() {
    local char="\$1"
    local count="\$2"
    local out=""
    local i

    for ((i = 0; i < count; i++)); do
        out+="\$char"
    done

    printf "%s" "\$out"
}

box_title() {
    local title="\$1"
    local width="\${2:-46}"
    local inner=\$((width - 2))

    printf "╔"
    repeat_char "═" "\$width"
    printf "╗\\n"

    printf "║ %-*s ║\\n" "\$inner" "\$title"

    printf "╚"
    repeat_char "═" "\$width"
    printf "╝\\n"
}

progress_pulse() {
    local label="\$1"
    local pid="\$2"
    local activity_dir="\${3:-}"
    local finalize_msg="\${4:-Finalisation en cours, veuillez patienter quelques secondes...}"

    local width=24
    local block=7
    local pos=0
    local direction=1
    local start_time=\$SECONDS

    local check_activity=0
    [ -n "\$activity_dir" ] && check_activity=1

    local last_size=-1
    local stable_count=0
    local finalized=0
    local sample_tick=0
    local current_label="\$label"

    if [ ! -t 1 ]; then
        while kill -0 "\$pid" 2>/dev/null; do
            sleep 1
        done
        return
    fi

    while kill -0 "\$pid" 2>/dev/null; do
        local bar=""
        local i
        local elapsed=\$((SECONDS - start_time))
        local min=\$((elapsed / 60))
        local sec=\$((elapsed % 60))

        if [ "\$check_activity" -eq 1 ] && [ "\$finalized" -eq 0 ]; then
            sample_tick=\$((sample_tick + 1))

            if (( sample_tick >= 8 )); then
                sample_tick=0
                local cur_size
                cur_size="\$(du -sk "\$activity_dir" 2>/dev/null | cut -f1)"
                cur_size="\${cur_size:-0}"

                if [ "\$cur_size" = "\$last_size" ]; then
                    stable_count=\$((stable_count + 1))
                else
                    stable_count=0
                fi
                last_size="\$cur_size"

                if (( stable_count >= 3 && elapsed >= 5 )); then
                    finalized=1
                    current_label="\$finalize_msg"
                fi
            fi
        fi

        for ((i = 0; i < width; i++)); do
            if (( i >= pos && i < pos + block )); then
                bar+="█"
            else
                bar+=" "
            fi
        done

        printf "\\r\\033[K%s [%s] %02d:%02d" "\$current_label" "\$bar" "\$min" "\$sec"

        pos=\$((pos + direction))

        if (( pos <= 0 )); then
            pos=0
            direction=1
        elif (( pos + block >= width )); then
            pos=\$((width - block))
            direction=-1
        fi

        sleep 0.12
    done

    printf "\\r\\033[K"
}

run_quiet() {
    local label="\$1"
    shift

    if [ "\$SHOW_WINE_LOGS" = "1" ]; then
        log_info "\$label"
        "\$@"
        return \$?
    fi

    mkdir -p "\$LOG_DIR"

    (
        export WINEDEBUG="\$WINEDEBUG_QUIET"
        "\$@"
    ) >>"\$LOG_FILE" 2>&1 &

    local pid=\$!
    progress_pulse "\$label" "\$pid" "\$RUN_QUIET_ACTIVITY_DIR" "\$RUN_QUIET_FINALIZE_MSG"

    wait "\$pid"
    local status=\$?

    if [ "\$status" -eq 0 ]; then
        log_success "\$label : terminé"
    else
        log_warning "\$label : terminé avec un code retour \$status"
        echo "Journal technique : \$LOG_FILE"
    fi

    return "\$status"
}

clear
box_title "Desinstallation de Pronote ${PRONOTE_YEAR} (${PRONOTE_ARCH} bits)" 46
echo ""

echo "Ce script va ouvrir l'outil Wine « Ajout/Suppression de programmes »."
echo ""
echo "Avant de commencer, assurez-vous que Pronote est fermé."
echo "Le script va aussi tenter de fermer automatiquement les processus Pronote/Wine"
echo "du préfixe suivant :"
echo "  \$WINEPREFIX"
echo ""
log_warning "Si d'autres applications Wine utilisent ce même préfixe, elles peuvent être fermées."
echo ""

read -rp "Continuer ? [O/n] : " CONTINUE
case "\$CONTINUE" in
    n|N|non|Non|NON)
        echo "Désinstallation annulée."
        exit 0
        ;;
esac

echo ""
echo "Par défaut, les messages techniques de Wine seront masqués."
read -rp "Afficher les messages techniques de Wine ? [o/N] : " DEBUG_CHOICE

case "\$DEBUG_CHOICE" in
    o|O|oui|Oui|OUI|y|Y|yes|YES)
        SHOW_WINE_LOGS="1"
        log_warning "Mode expert activé."
        ;;
    *)
        SHOW_WINE_LOGS="0"
        log_info "Mode silencieux activé."
        echo "Journal technique : \$LOG_FILE"
        ;;
esac

echo ""
log_info "Fermeture préventive des processus Pronote/Wine du préfixe..."

"\$WINE_BIN" taskkill /F /IM "Client PRONOTE.exe" >/dev/null 2>&1 || true
"\$WINE_BIN" taskkill /F /IM "PRONOTE.exe" >/dev/null 2>&1 || true
"\$WINE_BIN" taskkill /F /IM "IECefSubProcess.exe" >/dev/null 2>&1 || true

"\$WINESERVER_BIN" -k >/dev/null 2>&1 || true
sleep 1

echo ""
echo "Dans la fenêtre qui va s'ouvrir :"
echo ""
echo "  1. Sélectionnez « INDEX EDUCATION - Client PRONOTE ${PRONOTE_YEAR} » ou l'entrée Pronote équivalente."
echo "  2. Cliquez sur « Modifier/Supprimer »."
echo "  3. Suivez l'assistant de désinstallation jusqu'à son terme."
echo "  4. Remarque : l'assistant peut sembler avoir disparu prématurément ; le bouton « Modifier/Supprimer »"
echo "     apparait alors en grisé (non sélectionnable), même si Pronote est toujours visible dans la liste."
echo "     C'est normal : il suffit de cliquer sur « OK » pour fermer/terminer proprement."
echo ""
echo "Ensuite, relancez la commande pronote-desinstaller-${PRONOTE_ARCH} pour supprimer le service de mise à jour associé, présent"
echo "dans la même liste et nommé exactement :"
echo ""
echo "     « Mise à jour automatique - Index Education - »"
echo ""
echo "Sélectionnez-le puis cliquez à nouveau sur « Modifier/Supprimer »"
echo "(la remarque 4 ci-dessus s'applique aussi à cette étape)."
echo ""
echo "Quand tout est terminé, fermez la fenêtre « Ajout/Suppression de programmes »."
echo ""

read -rp "Appuyez sur Entrée pour ouvrir le désinstallateur Wine..."

RUN_QUIET_ACTIVITY_DIR="\$WINEPREFIX/drive_c"
RUN_QUIET_FINALIZE_MSG="Désinstallation : finalisation en cours, veuillez patienter quelques secondes..."

run_quiet "Desinstallation via Wine" "\$WINE_BIN" uninstaller || true

RUN_QUIET_ACTIVITY_DIR=""
RUN_QUIET_FINALIZE_MSG=""

echo ""
log_info "Nettoyage des raccourcis Linux..."

rm -f "\$DESKTOP_FILE" 2>/dev/null || true
rm -f "\$LAUNCHER" 2>/dev/null || true

GENERIC_LAUNCHER="\$BIN_DIR/pronote-${PRONOTE_YEAR}"
if [ -L "\$GENERIC_LAUNCHER" ] && [ "\$(readlink -f "\$GENERIC_LAUNCHER")" = "\$(readlink -f "\$LAUNCHER" 2>/dev/null)" ]; then
    rm -f "\$GENERIC_LAUNCHER" 2>/dev/null || true
fi

OTHER_DESKTOP_COUNT=\$(find "\$APP_DIR" -maxdepth 1 -name "pronote-${PRONOTE_YEAR}-*.desktop" 2>/dev/null | wc -l)

if [ "\$OTHER_DESKTOP_COUNT" -eq 0 ]; then
    rm -f "\$ICON_FILE" 2>/dev/null || true
    rm -f "\$PIXMAP_DIR/\${ICON_NAME}.png" 2>/dev/null || true
    rm -f "\$ICON_BASE_DIR/scalable/apps/\${ICON_NAME}.svg" 2>/dev/null || true

    for SIZE in 16 22 24 32 48 64 128 256; do
        rm -f "\$ICON_BASE_DIR/\${SIZE}x\${SIZE}/apps/\${ICON_NAME}.png" 2>/dev/null || true
    done
else
    log_info "Une autre version de Pronote est encore installée : l'icône est conservée."
fi

DESKTOP_TARGETS=()
if command -v xdg-user-dir >/dev/null 2>&1; then
    XDG_DESK="\$(xdg-user-dir DESKTOP 2>/dev/null || true)"
    [ -n "\$XDG_DESK" ] && DESKTOP_TARGETS+=("\$XDG_DESK")
fi
DESKTOP_TARGETS+=("\$HOME/Bureau" "\$HOME/Desktop")

for DDIR in "\${DESKTOP_TARGETS[@]}"; do
    [ -d "\$DDIR" ] || continue
    rm -f "\$DDIR/pronote-${PRONOTE_YEAR}-${PRONOTE_ARCH}.desktop" 2>/dev/null || true
    rm -f "\$DDIR/pronote-${PRONOTE_YEAR}.desktop" 2>/dev/null || true
done

if [ -d "\$APP_DIR/wine/Programs" ]; then
    find "\$APP_DIR/wine/Programs" -maxdepth 1 \
        \( -iname "PRONOTE*" -o -iname "Index Education*" \) \
        -exec rm -rf {} + 2>/dev/null || true
fi

update-desktop-database "\$APP_DIR" 2>/dev/null || true
gtk-update-icon-cache -f -t "\$ICON_BASE_DIR" 2>/dev/null || true
rm -f "\$HOME/.cache/icon-cache.kcache" 2>/dev/null || true
kbuildsycoca6 --noincremental 2>/dev/null || true
kbuildsycoca5 --noincremental 2>/dev/null || true

echo ""
log_success "Désinstallation terminée."
echo ""
echo "Vous pouvez maintenant fermer la fenêtre « Ajout/Suppression de programmes »"
echo "si elle est encore ouverte."
echo ""
echo "Remarque : le préfixe Wine n'a pas été supprimé :"
echo "  \$WINEPREFIX"
echo ""
echo "Pour supprimer entièrement ce préfixe Wine, uniquement si vous êtes sûr"
echo "qu'il ne contient pas d'autres logiciels utiles :"
echo "  rm -rf \"\$WINEPREFIX\""
echo ""
EOF

    chmod +x "$uninstaller"
    log_success "Désinstallateur créé : $uninstaller"

    ln -sf "$uninstaller" "$BIN_DIR/pronote-desinstaller-${PRONOTE_YEAR}-${PRONOTE_ARCH}"
}

create_uninstaller_dispatcher() {
    local dispatcher="$BIN_DIR/pronote-desinstaller"
    local q_bin_dir
    printf -v q_bin_dir '%q' "$BIN_DIR"

    cat > "$dispatcher" << EOF
#!/usr/bin/env bash
# Sélecteur de désinstallateur Pronote - généré automatiquement
set -u

BIN_DIR=$q_bin_dir

U32="\$BIN_DIR/pronote-desinstaller-32"
U64="\$BIN_DIR/pronote-desinstaller-64"

HAS32=0
HAS64=0
[ -x "\$U32" ] && HAS32=1
[ -x "\$U64" ] && HAS64=1

if [ "\$HAS32" -eq 0 ] && [ "\$HAS64" -eq 0 ]; then
    echo "Aucun désinstallateur Pronote trouvé dans \$BIN_DIR."
    exit 1
fi

if [ "\$#" -ge 1 ]; then
    case "\$1" in
        32) exec "\$U32" ;;
        64) exec "\$U64" ;;
    esac
fi

if [ "\$HAS32" -eq 1 ] && [ "\$HAS64" -eq 0 ]; then
    exec "\$U32"
fi

if [ "\$HAS64" -eq 1 ] && [ "\$HAS32" -eq 0 ]; then
    exec "\$U64"
fi

echo "Deux versions de Pronote sont installées."
echo ""
echo "  1) Désinstaller la version 64 bits  (pronote-desinstaller-64)"
echo "  2) Désinstaller la version 32 bits  (pronote-desinstaller-32)"
echo ""
read -rp "Votre choix [1/2] [Entrée=1] : " CHOICE

case "\${CHOICE:-1}" in
    2) exec "\$U32" ;;
    *) exec "\$U64" ;;
esac
EOF

    chmod +x "$dispatcher"
    log_success "Sélecteur de désinstallation créé : $dispatcher"
}

# ==============================================================================
# Aide / problèmes connus
# ==============================================================================

show_troubleshooting() {
    echo ""
    box_title "Problemes connus et solutions" 62
    echo ""
    echo "1. Erreur libcef.dll au démarrage, surtout avec deux écrans :"
    echo "   → Lancez : WINEPREFIX=\"$WINEPREFIX\" winecfg"
    echo "   → Onglet « Affichage » > cochez « Émuler un bureau virtuel » (ex. 1920x1080)."
    echo ""
    echo "2. Crash IECefSubProcess.exe :"
    echo "   → Essayez d'augmenter la résolution du bureau virtuel dans winecfg."
    echo ""
    echo "3. Pronote ne se lance qu'une seule fois :"
    echo "   → Le lanceur nettoie automatiquement certains caches au démarrage."
    echo "   → Si le problème persiste, relancez la session Linux."
    echo ""
    echo "4. Raccourci bureau non cliquable sous GNOME/Nautilus (icône avec cadenas) :"
    echo "   → Clic droit sur l'icône > « Autoriser le lancement »."
    echo ""
    echo "5. Diagnostic au lancement de Pronote :"
    echo "   → PRONOTE_DEBUG=1 pronote-${PRONOTE_YEAR}-${PRONOTE_ARCH}"
    echo ""
    echo "6. Une commande pronote-* semble « ne rien faire » (fréquent sur Mint XFCE) :"
    echo "   → Le PATH du terminal courant n'est pas encore à jour."
    echo "   → Faites simplement :  source ~/.bashrc && hash -r"
    echo "   → Ou ouvrez un nouveau terminal / reconnectez-vous."
    echo "   → En dernier recours, chemin complet :"
    echo "     $BIN_DIR/pronote-desinstaller-${PRONOTE_ARCH}"
    echo ""
    echo "7. « WINEARCH is set to win32 but this is not supported in wow64 mode » :"
    echo "   → Wine 10+/11 n'accepte plus les préfixes win32 purs."
    echo "   → Relancez ce script v4.6 : Pronote 32 bits ira dans un préfixe WoW64 dédié."
    echo ""
}

# ==============================================================================
# Programme principal
# ==============================================================================

main() {
    mkdir -p "$LOG_DIR"
    ensure_privilege_helper || true

    PRONOTE_URL_FROM_OPTION=""
    PRONOTE_ARCH_FROM_OPTION=""

    if [ ! -t 0 ]; then
        ASSUME_YES="1"
        SHOW_WINE_LOGS="0"
        log_info "Entrée non interactive détectée : mode silencieux activé."
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                usage
                exit 0
                ;;
            --yes)
                ASSUME_YES="1"
                shift
                ;;
            --arch)
                if [ -z "${2:-}" ]; then
                    log_error "--arch nécessite une valeur (32 ou 64)."
                    exit 1
                fi
                if [[ "$2" != "32" && "$2" != "64" ]]; then
                    log_error "Architecture invalide : $2 (attendu 32 ou 64)."
                    exit 1
                fi
                PRONOTE_ARCH_FROM_OPTION="$2"
                shift 2
                ;;
            --url)
                if [ -z "${2:-}" ]; then
                    log_error "--url nécessite une URL."
                    exit 1
                fi
                PRONOTE_URL_FROM_OPTION="$2"
                shift 2
                ;;
            --uninstall)
                UNINSTALL_ONLY="1"
                if [[ "${2:-}" == "32" || "${2:-}" == "64" ]]; then
                    UNINSTALL_ARCH="$2"
                    shift
                fi
                shift
                ;;
            --in-nix-shell)
                IN_NIX_SHELL="1"
                shift
                ;;
            *)
                log_error "Option inconnue : $1"
                usage
                exit 1
                ;;
        esac
    done

    if [ "$UNINSTALL_ONLY" = "1" ]; then
        local uninstaller=""

        if [ -n "$UNINSTALL_ARCH" ]; then
            uninstaller="$BIN_DIR/pronote-desinstaller-${UNINSTALL_ARCH}"
        else
            uninstaller="$BIN_DIR/pronote-desinstaller"
        fi

        if [ ! -x "$uninstaller" ]; then
            for candidate in \
                "$BIN_DIR/pronote-desinstaller-64" \
                "$BIN_DIR/pronote-desinstaller-32" \
                "$BIN_DIR/pronote-desinstaller-${DEFAULT_YEAR}" \
                "$BIN_DIR/pronote-desinstaller"; do
                if [ -x "$candidate" ]; then
                    uninstaller="$candidate"
                    break
                fi
            done
        fi

        if [ -x "$uninstaller" ]; then
            exec "$uninstaller"
        else
            log_error "Désinstallateur introuvable. Avez-vous déjà installé Pronote avec ce script ?"
            exit 1
        fi
    fi

    detect_distro

    if [ "$IN_NIX_SHELL" = "1" ]; then
        DISTRO_FAMILY="nixos-done"
        log_success "Environnement NixOS (ou dérivé) actif."
    fi

    log_info "Distribution détectée : $DISTRO_NAME ($DISTRO_FAMILY)"
    log_info "Installateur Pronote Linux v4.6"

    set_target_windows_version

    ask_wine_output_mode
    ensure_dependencies

    check_latest_version

    if [ -n "$PRONOTE_URL_FROM_OPTION" ]; then
        process_custom_url
    else
        get_pronote_url
    fi

    set_wineprefix
    configure_wine
    install_pronote
    create_launchers

    log_info "Nettoyage des fichiers temporaires..."
    rm -rf "$TMP_DIR" 2>/dev/null || true

    echo ""
    echo -e "${GREEN}"
    box_title "Installation terminee avec succes" 62
    echo -e "${NC}"

    log_success "Version installée : Pronote $PRONOTE_VERSION - ${PRONOTE_ARCH} bits"
    echo ""
    echo "Pour lancer Pronote :"
    echo "  • Menu Applications > Éducation > Pronote Client $PRONOTE_YEAR (${PRONOTE_ARCH} bits)"
    echo "  • Ou en terminal : pronote-${PRONOTE_YEAR}-${PRONOTE_ARCH}   (alias : pronote-$PRONOTE_YEAR)"
    echo "  • Ou double-clic sur le raccourci Bureau (si un dossier Bureau a été détecté)"
    echo ""
    echo "Pour désinstaller :"
    echo "  • Version 64 bits : ~/.local/bin/pronote-desinstaller-64"
    echo "  • Version 32 bits : ~/.local/bin/pronote-desinstaller-32"
    echo "  • Ou simplement   : ~/.local/bin/pronote-desinstaller (propose le choix si les deux sont installées)"
    echo ""
    echo "Astuce : les versions 32 et 64 bits peuvent être installées en même temps ;"
    echo "chacune a son propre préfixe Wine et son propre désinstallateur."
    echo ""
    echo "Emplacements :"
    echo "  • Préfixe Wine : $WINEPREFIX"
    echo "  • Lanceur : $BIN_DIR/pronote-${PRONOTE_YEAR}-${PRONOTE_ARCH}"
    echo "  • Raccourci menu : $APP_DIR/pronote-${PRONOTE_YEAR}-${PRONOTE_ARCH}.desktop"
    echo "  • Journal d'installation : $LOG_FILE"
    echo ""

    case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *)
            log_warning "$BIN_DIR n'est pas présent dans le PATH actuel."
            echo "Dans ce terminal, faites :"
            echo "  source ~/.bashrc && hash -r"
            ;;
    esac

    show_troubleshooting

    log_success "Bonne utilisation de Pronote !"
    echo ""
}

main "$@"
