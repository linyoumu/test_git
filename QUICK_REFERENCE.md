# merge_commits.sh 快速参考

## 快速命令

```bash
# 基本用法
./merge_commits.sh                          # 合并最近3个提交
./merge_commits.sh -c 5                     # 合并最近5个提交
./merge_commits.sh -c 3 -m "feat: 整合功能" # 指定提交信息
./merge_commits.sh -d                       # 干运行（预览）
./merge_commits.sh --help                   # 查看帮助
```

## 常用参数

| 参数 | 说明 |
|------|------|
| `-c N` | 合并 N 个提交 |
| `-m "MSG"` | 指定提交信息 |
| `-b BRANCH` | 指定分支 |
| `-d` | 干运行模式 |
| `-f` | 强制模式 |
| `-v` | 详细输出 |

## 工作流程

1. 确认继续 → 2. 输入提交信息 → 3. 执行合并 → 4. 自动推送

## 冲突处理

1. 编辑冲突文件（删除 `<<<<<<<`, `=======`, `>>>>>>>` 标记）
2. 保存文件
3. 按任意键继续（交互式）或等待自动检测（非交互式）

## Conventional Commits 格式

```
<type>: <subject>

类型：
feat:     新功能
fix:      修复
refactor: 重构
perf:     性能优化
docs:     文档
test:     测试
chore:    杂项
```

## 安全检查清单

- [ ] 确认在个人分支（非 main/master）
- [ ] 查看要合并的提交 `git log --oneline -n 5`
- [ ] 创建备份分支 `git branch backup-$(date +%Y%m%d)`
- [ ] 干运行预览 `./merge_commits.sh -d`
- [ ] 执行合并
- [ ] 验证结果 `git log --oneline`

## 紧急回滚

```bash
# 查看历史
git reflog

# 回滚到之前的状态
git reset --hard HEAD@{1}

# 强制推送（如果已推送）
git push --force
```

## 常见问题速查

| 问题 | 解决方法 |
|------|---------|
| 脚本卡住 | 检查是否有冲突待解决，或 `pkill -f merge_commits` |
| Vim 警告 | `rm .git/.COMMIT_EDITMSG.sw*` 然后重试 |
| 冲突太多 | `git rebase --abort` 然后手动处理 |
| 需要撤销 | `git reset --hard <commit>` |

## 配置文件

```bash
# 创建配置
./merge_commits.sh --create-config

# 编辑 .git-squash.conf
COMMIT_MSG="feat: 默认提交信息"
BRANCH_NAME="dev"
COMMIT_COUNT=3
```

---

**详细文档**: 参见 `MERGE_COMMITS_README.md`
