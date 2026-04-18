#!/bin/bash

# Color theme: gray, orange, blue, teal, green, lavender, rose, gold, slate, cyan
# Preview colors with: bash scripts/color-preview.sh
COLOR="blue"

# Color codes
C_RESET='\033[0m'
C_GRAY='\033[38;5;245m'  # explicit gray for default text
C_BAR_EMPTY='\033[38;5;238m'
case "$COLOR" in
    orange)   C_ACCENT='\033[38;5;173m' ;;
    blue)     C_ACCENT='\033[38;5;74m' ;;
    teal)     C_ACCENT='\033[38;5;66m' ;;
    green)    C_ACCENT='\033[38;5;71m' ;;
    lavender) C_ACCENT='\033[38;5;139m' ;;
    rose)     C_ACCENT='\033[38;5;132m' ;;
    gold)     C_ACCENT='\033[38;5;136m' ;;
    slate)    C_ACCENT='\033[38;5;60m' ;;
    cyan)     C_ACCENT='\033[38;5;37m' ;;
    *)        C_ACCENT="$C_GRAY" ;;  # gray: all same color
esac

input=$(cat)

# Extract model, directory, and cwd
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "?"')
cwd=$(echo "$input" | jq -r '.cwd // empty')
dir=$(basename "$cwd" 2>/dev/null || echo "?")

# Get git branch, uncommitted file count, and sync status
branch=""
git_status=""
if [[ -n "$cwd" && -d "$cwd" ]]; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
    if [[ -n "$branch" ]]; then
        # Count uncommitted files
        file_count=$(git -C "$cwd" --no-optional-locks status --porcelain -uall 2>/dev/null | wc -l | tr -d ' ')

        # Check sync status with upstream
        sync_status=""
        upstream=$(git -C "$cwd" rev-parse --abbrev-ref @{upstream} 2>/dev/null)
        if [[ -n "$upstream" ]]; then
            # Get last fetch time
            fetch_head="$cwd/.git/FETCH_HEAD"
            fetch_ago=""
            if [[ -f "$fetch_head" ]]; then
                fetch_time=$(stat -f %m "$fetch_head" 2>/dev/null || stat -c %Y "$fetch_head" 2>/dev/null)
                if [[ -n "$fetch_time" ]]; then
                    now=$(date +%s)
                    diff=$((now - fetch_time))
                    if [[ $diff -lt 60 ]]; then
                        fetch_ago="<1m ago"
                    elif [[ $diff -lt 3600 ]]; then
                        fetch_ago="$((diff / 60))m ago"
                    elif [[ $diff -lt 86400 ]]; then
                        fetch_ago="$((diff / 3600))h ago"
                    else
                        fetch_ago="$((diff / 86400))d ago"
                    fi
                fi
            fi

            counts=$(git -C "$cwd" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
            ahead=$(echo "$counts" | cut -f1)
            behind=$(echo "$counts" | cut -f2)
            if [[ "$ahead" -eq 0 && "$behind" -eq 0 ]]; then
                if [[ -n "$fetch_ago" ]]; then
                    sync_status="synced ${fetch_ago}"
                else
                    sync_status="synced"
                fi
            elif [[ "$ahead" -gt 0 && "$behind" -eq 0 ]]; then
                sync_status="${ahead} ahead"
            elif [[ "$ahead" -eq 0 && "$behind" -gt 0 ]]; then
                sync_status="${behind} behind"
            else
                sync_status="${ahead} ahead, ${behind} behind"
            fi
        else
            sync_status="no upstream"
        fi

        # Build git status string
        if [[ "$file_count" -eq 0 ]]; then
            git_status="(0 files uncommitted, ${sync_status})"
        elif [[ "$file_count" -eq 1 ]]; then
            # Show the actual filename when only one file is uncommitted
            single_file=$(git -C "$cwd" --no-optional-locks status --porcelain -uall 2>/dev/null | head -1 | sed 's/^...//')
            git_status="(${single_file} uncommitted, ${sync_status})"
        else
            git_status="(${file_count} files uncommitted, ${sync_status})"
        fi
    fi
fi

# Cloud provider profiles
aws_profile=""
if [[ -n "$AWS_PROFILE" ]]; then
    aws_profile="☁️${AWS_PROFILE}"
fi

# GCP project detection (disabled - uncomment to enable)
# gcp_project=""
# if [[ -n "$CLOUDSDK_CORE_PROJECT" ]]; then
#     gcp_project="🌐${CLOUDSDK_CORE_PROJECT}"
# elif [[ -n "$GOOGLE_CLOUD_PROJECT" ]]; then
#     gcp_project="🌐${GOOGLE_CLOUD_PROJECT}"
# elif command -v gcloud &>/dev/null; then
#     gcp_proj=$(gcloud config get-value project 2>/dev/null)
#     if [[ -n "$gcp_proj" && "$gcp_proj" != "(unset)" ]]; then
#         gcp_project="🌐${gcp_proj}"
#     fi
# fi
gcp_project=""  # placeholder for disabled GCP detection

# Kubernetes context
kube_ctx=""
if command -v kubectl &>/dev/null; then
    k8s_context=$(kubectl config current-context 2>/dev/null)
    if [[ -n "$k8s_context" ]]; then
        kube_ctx="⎈${k8s_context}"
    fi
fi

# Language/tool versions (only if relevant files exist in cwd)
go_ver=""
if [[ -n "$cwd" && -d "$cwd" ]]; then
    if [[ -f "$cwd/go.mod" ]] && command -v go &>/dev/null; then
        go_version=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//')
        [[ -n "$go_version" ]] && go_ver="go${go_version}"
    fi
fi

node_ver=""
if [[ -n "$cwd" && -d "$cwd" ]]; then
    if [[ -f "$cwd/package.json" ]] && command -v node &>/dev/null; then
        node_version=$(node --version 2>/dev/null | sed 's/v//')
        [[ -n "$node_version" ]] && node_ver="node${node_version}"
    fi
fi

python_ver=""
if [[ -n "$cwd" && -d "$cwd" ]]; then
    if [[ -f "$cwd/pyproject.toml" || -f "$cwd/requirements.txt" || -f "$cwd/Pipfile" || -f "$cwd/setup.py" ]]; then
        if command -v python3 &>/dev/null; then
            py_version=$(python3 --version 2>/dev/null | awk '{print $2}')
            [[ -n "$py_version" ]] && python_ver="py${py_version}"
        elif command -v python &>/dev/null; then
            py_version=$(python --version 2>/dev/null | awk '{print $2}')
            [[ -n "$py_version" ]] && python_ver="py${py_version}"
        fi
    fi
fi

tofu_ver=""
if [[ -n "$cwd" && -d "$cwd" ]]; then
    if ls "$cwd"/*.tf &>/dev/null; then
        if command -v tofu &>/dev/null; then
            tofu_version=$(tofu version 2>/dev/null | head -n1 | awk '{print $2}' | sed 's/v//')
            [[ -n "$tofu_version" ]] && tofu_ver="tofu${tofu_version}"
        fi
    fi
fi

# Get transcript path for context calculation and last message feature
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

# Get context window size from JSON (accurate), but calculate tokens from transcript
# (more accurate than total_input_tokens which excludes system prompt/tools/memory)
# See: github.com/anthropics/claude-code/issues/13652
max_context=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
max_k=$((max_context / 1000))

# Calculate context bar from transcript
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
    context_length=$(jq -s '
        map(select(.message.usage and .isSidechain != true and .isApiErrorMessage != true)) |
        last |
        if . then
            (.message.usage.input_tokens // 0) +
            (.message.usage.cache_read_input_tokens // 0) +
            (.message.usage.cache_creation_input_tokens // 0)
        else 0 end
    ' < "$transcript_path")

    # 20k baseline: includes system prompt (~3k), tools (~15k), memory (~300),
    # plus ~2k for git status, env block, XML framing, and other dynamic context
    baseline=20000
    bar_width=10

    if [[ "$context_length" -gt 0 ]]; then
        pct=$((context_length * 100 / max_context))
        pct_prefix=""
    else
        # At conversation start, ~20k baseline is already loaded
        pct=$((baseline * 100 / max_context))
        pct_prefix="~"
    fi

    [[ $pct -gt 100 ]] && pct=100

    bar=""
    for ((i=0; i<bar_width; i++)); do
        bar_start=$((i * 10))
        progress=$((pct - bar_start))
        if [[ $progress -ge 8 ]]; then
            bar+="${C_ACCENT}█${C_RESET}"
        elif [[ $progress -ge 3 ]]; then
            bar+="${C_ACCENT}▄${C_RESET}"
        else
            bar+="${C_BAR_EMPTY}░${C_RESET}"
        fi
    done

    ctx="${bar} ${C_GRAY}${pct_prefix}${pct}% of ${max_k}k tokens"
else
    # Transcript not available yet - show baseline estimate
    baseline=20000
    bar_width=10
    pct=$((baseline * 100 / max_context))
    [[ $pct -gt 100 ]] && pct=100

    bar=""
    for ((i=0; i<bar_width; i++)); do
        bar_start=$((i * 10))
        progress=$((pct - bar_start))
        if [[ $progress -ge 8 ]]; then
            bar+="${C_ACCENT}█${C_RESET}"
        elif [[ $progress -ge 3 ]]; then
            bar+="${C_ACCENT}▄${C_RESET}"
        else
            bar+="${C_BAR_EMPTY}░${C_RESET}"
        fi
    done

    ctx="${bar} ${C_GRAY}~${pct}% of ${max_k}k tokens"
fi

# Build output: Model | Dir | Branch (uncommitted) | Cloud/K8s | Versions | Context
output="${C_ACCENT}${model}${C_GRAY} | 📁 ${dir}"
[[ -n "$branch" ]] && output+=" | 🔀 ${branch} ${git_status}"
[[ -n "$aws_profile" ]] && output+=" | ${aws_profile}"
[[ -n "$gcp_project" ]] && output+=" | ${gcp_project}"
[[ -n "$kube_ctx" ]] && output+=" | ${kube_ctx}"
# Language versions (combine on one line if multiple)
versions=""
[[ -n "$go_ver" ]] && versions+="${go_ver} "
[[ -n "$node_ver" ]] && versions+="${node_ver} "
[[ -n "$python_ver" ]] && versions+="${python_ver} "
# [[ -n "$tofu_ver" ]] && versions+="${tofu_ver} "
versions="${versions% }"  # trim trailing space
[[ -n "$versions" ]] && output+=" | ${versions}"
output+=" | ${ctx}${C_RESET}"

printf '%b\n' "$output"

# Get user's last message (text only, not tool results, skip unhelpful messages)
# if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
#     # Calculate visible length (without ANSI codes) - 10 chars for bar + content
#     plain_output="${model} | 📁${dir}"
#     [[ -n "$branch" ]] && plain_output+=" | 🔀 ${branch} ${git_status}"
#     [[ -n "$aws_profile" ]] && plain_output+=" | ${aws_profile}"
#     [[ -n "$gcp_project" ]] && plain_output+=" | ${gcp_project}"
#     [[ -n "$kube_ctx" ]] && plain_output+=" | ${kube_ctx}"
#     [[ -n "$versions" ]] && plain_output+=" | ${versions}"
#     # plain_output+=" | xxxxxxxxxx ${pct}% of ${max_k}k tokens"
#     # max_len=${#plain_output}
#     # last_user_msg=$(jq -rs '
#     #     # Messages to skip (not useful as context)
#     #     def is_unhelpful:
#     #         startswith("[Request interrupted") or
#     #         startswith("[Request cancelled") or
#     #         . == "";

#     #     [.[] | select(.type == "user") |
#     #      select(.message.content | type == "string" or
#     #             (type == "array" and any(.[]; .type == "text")))] |
#     #     reverse |
#     #     map(.message.content |
#     #         if type == "string" then .
#     #         else [.[] | select(.type == "text") | .text] | join(" ") end |
#     #         gsub("\n"; " ") | gsub("  +"; " ")) |
#     #     map(select(is_unhelpful | not)) |
#     #     first // ""
#     # ' < "$transcript_path" 2>/dev/null)

#     # if [[ -n "$last_user_msg" ]]; then
#     #     if [[ ${#last_user_msg} -gt $max_len ]]; then
#     #         echo "💬 ${last_user_msg:0:$((max_len - 3))}..."
#     #     else
#     #         echo "💬 ${last_user_msg}"
#     #     fi
#     # fi
# fi
