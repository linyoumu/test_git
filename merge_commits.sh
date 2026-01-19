#!/bin/bash

#===============================================================================
# Git 提交合并自动化脚本 (增强版)
# 功能：自动合并最近 N 个提交并强制推送
# 版本：v2.0
# 作者：优化版
#===============================================================================

set -o errexit   # 遇到错误立即退出
set -o pipefail  # 管道中任何命令失败都算失败
set -o nounset   # 使用未定义变量时报错

#===============================================================================
# 配置项
#===============================================================================

# 默认配置
DEFAULT_COMMIT_MSG="合并提交：整理代码历史"
DEFAULT_BRANCH_NAME="main"
DEFAULT_COMMIT_COUNT=3
DEFAULT_LOG_FILE="./git-squash.log"

# 从配置文件读取（如果存在）
CONFIG_FILE=".git-squash.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# 使用配置或默认值
COMMIT_MSG="${COMMIT_MSG:-$DEFAULT_COMMIT_MSG}"
BRANCH_NAME="${BRANCH_NAME:-$DEFAULT_BRANCH_NAME}"
COMMIT_COUNT="${COMMIT_COUNT:-$DEFAULT_COMMIT_COUNT}"
LOG_FILE="${LOG_FILE:-$DEFAULT_LOG_FILE}"

#===============================================================================
# 颜色定义
#===============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

#===============================================================================
# 工具函数
#===============================================================================

# 日志函数
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# 信息输出函数
info() {
    echo -e "${CYAN}ℹ️  $@${NC}"
    log "INFO" "$@"
}

success() {
    echo -e "${GREEN}✅ $@${NC}"
    log "SUCCESS" "$@"
}

warning() {
    echo -e "${YELLOW}⚠️  $@${NC}"
    log "WARNING" "$@"
}

error() {
    echo -e "${RED}❌ $@${NC}" >&2
    log "ERROR" "$@"
}

# 错误退出函数
die() {
    error "$@"
    exit 1
}

# 确认函数
confirm() {
    local prompt="${1:-确定继续？}"
    local default="${2:-n}"
    
    if [ "$default" = "y" ]; then
        prompt="$prompt (Y/n): "
    else
        prompt="$prompt (y/N): "
    fi
    
    read -p "$(echo -e ${YELLOW}$prompt${NC})" response
    response=${response:-$default}
    
    [[ "$response" =~ ^[Yy]$ ]]
}

# 显示帮助
show_help() {
    cat << EOF
${CYAN}Git 提交合并自动化脚本 v2.1${NC}

${YELLOW}用法：${NC}
    $0 [选项]

${YELLOW}选项：${NC}
    -h, --help              显示此帮助信息
    -d, --dry-run           干运行模式（仅显示将要执行的操作）
    -c, --count N           要合并的提交数量（默认：$DEFAULT_COMMIT_COUNT）
    -b, --branch NAME       目标分支名称（默认：$DEFAULT_BRANCH_NAME）
    -m, --message MSG       合并后的提交信息
    -f, --force             跳过所有确认提示
    -v, --verbose           详细输出模式
    --auto-resolve STRATEGY 自动解决冲突（ours=保留本地, theirs=保留远程）
    --create-config         创建配置文件示例

${YELLOW}示例：${NC}
    # 基本用法
    $0

    # 合并 5 个提交
    $0 -c 5

    # 干运行查看效果
    $0 -d

    # 自定义提交信息
    $0 -m "feat: 添加新功能"

    # 强制执行（谨慎使用）
    $0 -f
    
    # 自动解决冲突（保留本地版本）
    $0 --auto-resolve ours

${YELLOW}配置文件：${NC}
    脚本会自动读取当前目录下的 ${GREEN}.git-squash.conf${NC} 文件
    使用 ${GREEN}--create-config${NC} 生成配置文件示例

${RED}⚠️  警告：${NC}
    此脚本会重写 Git 历史并强制推送！
    仅适用于个人开发分支，不要在共享分支上使用！
EOF
}

# 创建配置文件
create_config() {
    cat > "$CONFIG_FILE" << 'EOF'
# Git Squash 配置文件
# 取消注释并修改以下配置项

# COMMIT_MSG="修复问题 + 代码优化"
# BRANCH_NAME="feature/my-branch"
# COMMIT_COUNT=3
# LOG_FILE="./git-squash.log"
EOF
    success "配置文件已创建：$CONFIG_FILE"
    info "请编辑此文件后重新运行脚本"
    exit 0
}

# 检测操作系统
detect_os() {
    case "$OSTYPE" in
        darwin*)  echo "macos" ;;
        linux*)   echo "linux" ;;
        msys*|cygwin*|mingw*) echo "windows" ;;
        *)        echo "unknown" ;;
    esac
}

# 获取适配的 sed 命令
get_sed_cmd() {
    local os=$(detect_os)
    if [ "$os" = "macos" ]; then
        echo "sed -i ''"
    else
        echo "sed -i"
    fi
}

#===============================================================================
# 预检查函数
#===============================================================================

# 检查是否在 Git 仓库中
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        die "当前目录不是 Git 仓库"
    fi
}

# 检查工作区状态
check_working_tree() {
    if [ -n "$(git status --porcelain)" ]; then
        warning "工作区有未提交的更改"
        git status --short
        
        if ! confirm "是否继续？这些更改会被暂存"; then
            die "操作已取消"
        fi
        return 1  # 表示有未提交更改
    fi
    return 0  # 工作区干净
}

# 检查当前分支
check_branch() {
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    if [ "$current_branch" != "$BRANCH_NAME" ]; then
        error "当前分支：$current_branch"
        error "目标分支：$BRANCH_NAME"
        
        if confirm "是否切换到 $BRANCH_NAME 分支"; then
            git checkout "$BRANCH_NAME" || die "切换分支失败"
        else
            die "分支不匹配，操作已取消"
        fi
    fi
}

# 检查提交数量
check_commit_count() {
    local total_commits=$(git rev-list --count HEAD)
    
    if [ $total_commits -lt $COMMIT_COUNT ]; then
        die "分支只有 $total_commits 个提交，无法合并 $COMMIT_COUNT 个"
    fi
    
    if [ $total_commits -eq $COMMIT_COUNT ]; then
        warning "将合并所有提交（$total_commits 个），这会影响初始提交"
        if ! confirm "确定继续"; then
            die "操作已取消"
        fi
    fi
}

# 检查远程分支状态
check_remote_status() {
    info "检查远程分支状态..."
    
    # 获取远程最新状态
    git fetch origin "$BRANCH_NAME" 2>/dev/null || warning "无法获取远程分支信息"
    
    # 检查本地和远程的差异
    local local_commit=$(git rev-parse HEAD)
    local remote_commit=$(git rev-parse "origin/$BRANCH_NAME" 2>/dev/null || echo "")
    
    if [ -n "$remote_commit" ] && [ "$local_commit" != "$remote_commit" ]; then
        local ahead=$(git rev-list --count origin/$BRANCH_NAME..HEAD)
        local behind=$(git rev-list --count HEAD..origin/$BRANCH_NAME)
        
        warning "本地分支领先远程 $ahead 个提交，落后 $behind 个提交"
        
        if [ $behind -gt 0 ]; then
            error "远程分支有新提交！强制推送会覆盖这些提交"
            if ! confirm "确定要强制推送吗"; then
                die "操作已取消"
            fi
        fi
    fi
}

# 显示将要合并的提交
show_commits_to_squash() {
    info "将要合并以下 $COMMIT_COUNT 个提交："
    echo ""
    git log --oneline -n $COMMIT_COUNT --color=always
    echo ""
}

#===============================================================================
# 主要操作函数
#===============================================================================

# 储藏未提交的更改
stash_changes() {
    info "储藏未提交的更改..."
    
    local stash_before=$(git stash list | wc -l | tr -d ' ')
    git stash push -m "auto-stash-$(date +%Y%m%d-%H%M%S)" > /dev/null 2>&1
    local stash_after=$(git stash list | wc -l | tr -d ' ')
    
    if [ $stash_after -gt $stash_before ]; then
        success "已储藏 $((stash_after - stash_before)) 个更改"
        return 0  # 有储藏
    fi
    
    return 1  # 无储藏
}

# 恢复储藏
restore_stash() {
    if [ "${STASHED:-0}" -eq 1 ]; then
        info "恢复储藏的更改..."
        git stash pop > /dev/null 2>&1 && success "已恢复储藏" || warning "恢复储藏失败"
    fi
}

# 检查是否有冲突
check_conflicts() {
    git diff --name-only --diff-filter=U 2>/dev/null
}

# 列出冲突文件
list_conflicts() {
    local conflicts=$(check_conflicts)
    
    if [ -n "$conflicts" ]; then
        error "检测到以下文件存在冲突："
        echo ""
        while IFS= read -r file; do
            echo -e "  ${RED}⚠️  $file${NC}"
        done <<< "$conflicts"
        echo ""
        return 0
    fi
    
    return 1
}

# 等待用户解决冲突
wait_for_conflict_resolution() {
    info "请解决上述冲突后继续..."
    echo ""
    echo -e "${YELLOW}解决冲突的步骤：${NC}"
    echo "  1. 编辑冲突文件，删除冲突标记 (<<<<<<<, =======, >>>>>>>)"
    echo "  2. 保存文件"
    echo "  3. 回到此终端，按任意键继续"
    echo ""
    
    # 检测是否在交互式终端
    if [ -t 0 ]; then
        # 交互式环境：等待用户按键
        read -n 1 -s -r -p "$(echo -e ${GREEN}按任意键继续...${NC})"
        echo ""
    else
        # 非交互式环境：轮询检查
        warning "检测到非交互式环境，将自动检查冲突解决状态..."
        local max_wait=300  # 最多等待5分钟
        local wait_interval=5  # 每5秒检查一次
        local elapsed=0
        
        while [ $elapsed -lt $max_wait ]; do
            sleep $wait_interval
            elapsed=$((elapsed + wait_interval))
            
            if ! check_conflicts > /dev/null 2>&1; then
                success "检测到冲突已解决！"
                break
            fi
            
            info "等待冲突解决中... ($elapsed/$max_wait 秒)"
        done
        
        if [ $elapsed -ge $max_wait ]; then
            error "等待超时（${max_wait}秒）"
            if confirm "是否中止 rebase 并回滚"; then
                git rebase --abort
                die "已回滚到原始状态"
            else
                die "操作已取消"
            fi
        fi
    fi
    
    # 检查冲突是否已解决
    if list_conflicts; then
        error "仍有未解决的冲突！"
        
        if confirm "是否继续等待解决"; then
            wait_for_conflict_resolution
        else
            if confirm "是否中止 rebase 并回滚"; then
                git rebase --abort
                die "已回滚到原始状态"
            else
                die "操作已取消"
            fi
        fi
    else
        success "所有冲突已解决！"
        
        # 自动添加已解决的文件
        info "添加已解决的文件..."
        git add -u
        success "文件已添加到暂存区"
    fi
}

# 执行 rebase
perform_rebase() {
    info "开始合并提交..."
    
    local os=$(detect_os)
    local sed_cmd
    
    if [ "$os" = "macos" ]; then
        sed_cmd="sed -i '' -e"
    else
        sed_cmd="sed -i -e"
    fi
    
    # 保存原始 HEAD（用于回滚）
    ORIGINAL_HEAD=$(git rev-parse HEAD)
    
    # 执行非交互式 rebase（跳过编辑器）
    if ! GIT_SEQUENCE_EDITOR="$sed_cmd '2,\$s/^pick/squash/'" GIT_EDITOR=true git rebase -i HEAD~$COMMIT_COUNT; then
        error "Rebase 遇到冲突"
        echo ""
        
        # 列出冲突文件
        if list_conflicts; then
            # 等待用户解决冲突
            wait_for_conflict_resolution
            
            # 继续 rebase
            info "继续执行 rebase..."
            
            # 循环处理可能的多次冲突
            while true; do
                if GIT_EDITOR=true git rebase --continue; then
                    success "Rebase 继续成功"
                    break
                else
                    # 检查是否还有冲突
                    if list_conflicts; then
                        warning "Rebase 过程中出现新的冲突"
                        wait_for_conflict_resolution
                    else
                        # 可能是需要编辑提交信息，跳过
                        warning "Rebase 过程中需要处理提交信息..."
                        if GIT_EDITOR=true git rebase --continue; then
                            success "Rebase 继续成功"
                            break
                        else
                            error "Rebase 继续失败"
                            if confirm "是否中止 rebase 并回滚"; then
                                git rebase --abort
                                die "已回滚到原始状态"
                            else
                                die "操作已取消，请手动处理"
                            fi
                        fi
                    fi
                fi
            done
        else
            error "Rebase 失败，但未检测到冲突文件"
            
            if confirm "是否中止 rebase 并回滚"; then
                git rebase --abort
                die "已回滚到原始状态"
            else
                die "操作已取消，请手动处理"
            fi
        fi
    fi
    
    success "提交合并成功"
}

# 修改提交信息
amend_commit_message() {
    info "更新提交信息..."
    
    if ! git commit --amend -m "$COMMIT_MSG" > /dev/null 2>&1; then
        error "修改提交信息失败"
        return 1
    fi
    
    success "提交信息已更新"
    info "新的提交信息："
    echo -e "${MAGENTA}    $COMMIT_MSG${NC}"
}

# 推送到远程
push_to_remote() {
    info "准备推送到远程分支 origin/$BRANCH_NAME..."
    
    if [ "${FORCE_MODE:-0}" -eq 0 ]; then
        warning "即将执行强制推送（force-with-lease）"
        if ! confirm "确定要推送"; then
            die "推送已取消"
        fi
    fi
    
    if git push origin "$BRANCH_NAME" --force-with-lease; then
        success "推送成功！"
        return 0
    else
        error "推送失败"
        
        warning "可能的原因："
        echo "  1. 网络问题"
        echo "  2. 权限不足"
        echo "  3. 远程分支已被其他人更新"
        echo ""
        
        if confirm "是否回滚到操作前的状态"; then
            git reset --hard "$ORIGINAL_HEAD"
            success "已回滚到原始状态"
        fi
        
        return 1
    fi
}

#===============================================================================
# 干运行模式
#===============================================================================

dry_run() {
    info "【干运行模式】仅显示将执行的操作，不会实际修改\n"
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}配置信息：${NC}"
    echo -e "  目标分支：${GREEN}$BRANCH_NAME${NC}"
    echo -e "  合并数量：${GREEN}$COMMIT_COUNT${NC} 个提交"
    echo -e "  提交信息：${GREEN}$COMMIT_MSG${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    show_commits_to_squash
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}将执行的操作：${NC}"
    echo "  1. 检查当前分支"
    echo "  2. 储藏未提交的更改（如果有）"
    echo "  3. 合并最近 $COMMIT_COUNT 个提交"
    echo "  4. 修改提交信息为："
    echo -e "     ${MAGENTA}$COMMIT_MSG${NC}"
    echo "  5. 强制推送到 origin/$BRANCH_NAME"
    echo "  6. 恢复储藏的更改（如果有）"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    success "干运行完成！使用不带 -d 参数运行以实际执行"
}

#===============================================================================
# 主流程
#===============================================================================

main() {
    # 参数解析
    DRY_RUN=0
    FORCE_MODE=0
    VERBOSE=0
    AUTO_RESOLVE=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=1
                shift
                ;;
            -c|--count)
                COMMIT_COUNT="$2"
                shift 2
                ;;
            -b|--branch)
                BRANCH_NAME="$2"
                shift 2
                ;;
            -m|--message)
                COMMIT_MSG="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_MODE=1
                shift
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            --auto-resolve)
                AUTO_RESOLVE="$2"
                if [[ "$AUTO_RESOLVE" != "ours" && "$AUTO_RESOLVE" != "theirs" ]]; then
                    error "无效的冲突解决策略：$AUTO_RESOLVE"
                    error "有效选项：ours, theirs"
                    exit 1
                fi
                shift 2
                ;;
            --create-config)
                create_config
                ;;
            *)
                error "未知选项：$1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 打印标题
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════╗"
    echo "║   Git 提交合并自动化脚本 v2.1             ║"
    echo "╚═══════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # 记录开始
    log "INFO" "========== 脚本开始执行 =========="
    log "INFO" "分支: $BRANCH_NAME, 合并数量: $COMMIT_COUNT"
    
    # 预检查
    check_git_repo
    check_branch
    check_commit_count
    
    # 干运行模式
    if [ $DRY_RUN -eq 1 ]; then
        dry_run
        exit 0
    fi
    
    # 显示将要合并的提交
    show_commits_to_squash
    
    # 最终确认
    if [ $FORCE_MODE -eq 0 ]; then
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED}⚠️  警告：此操作将重写 Git 历史并强制推送！${NC}"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        
        if ! confirm "确定继续执行"; then
            info "操作已取消"
            exit 0
        fi
        
        echo ""
        # 询问是否自定义提交信息
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}📝 合并提交信息${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "当前提交信息：${GREEN}$COMMIT_MSG${NC}"
        echo ""
        
        if confirm "是否使用自定义提交信息" "n"; then
            echo ""
            echo -e "${MAGENTA}💡 提交信息建议格式：${NC}"
            echo -e "  ${GREEN}feat:${NC} 新增功能"
            echo -e "  ${GREEN}fix:${NC} 修复问题"
            echo -e "  ${GREEN}refactor:${NC} 重构代码"
            echo -e "  ${GREEN}docs:${NC} 文档更新"
            echo -e "  ${GREEN}chore:${NC} 杂项工作"
            echo ""
            read -p "$(echo -e ${YELLOW}请输入新的提交信息: ${NC})" custom_msg
            
            if [ -n "$custom_msg" ]; then
                COMMIT_MSG="$custom_msg"
                echo ""
                success "提交信息已更新为：$COMMIT_MSG"
            else
                echo ""
                warning "输入为空，保持原有提交信息"
            fi
        fi
        echo ""
    fi
    
    # 检查工作区并储藏
    STASHED=0
    if ! check_working_tree; then
        stash_changes && STASHED=1
    fi
    
    # 检查远程状态
    check_remote_status
    
    # 执行主要操作
    perform_rebase || die "Rebase 失败"
    amend_commit_message || die "修改提交信息失败"
    push_to_remote || die "推送失败"
    
    # 恢复储藏
    restore_stash
    
    # 完成
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    success "🎉 所有操作完成！"
    success "$COMMIT_COUNT 个提交已成功合并为 1 个"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    log "INFO" "========== 脚本执行成功 =========="
}

# 执行主流程
main "$@"

