---
title: tmux 工作区配置：从裸奔到顺手的三件事
tags:
  - tmux
  - 工具折腾
  - SSH
  - 日常
categories:
  - 技术
abbrlink: 9488b6e9
---

上周在 VPS 上做项目调试，每次 SSH 上去就面对一个光秃秃的终端：窗口关了连接断开，长任务直接挂掉。这已经是今年第三次出现这种情况了。

决定把 tmux 配起来。不是第一次装了，但每次都是裸奔启动——没有状态栏、没有窗口命名、没有自动恢复。上次装的时候花了两天配 dotfiles，这次决定做减法：只搞三件事，够用的就行。

## 第一件事：session 管理

tmux 的核心概念是 session，每个 session 可以挂起再重新附加。裸用 tmux 的人最吃亏的就是这个——开一个 session 然后直接在里面干活，session 丢了就得重来。

配置方式：

```bash
# ~/.tmux.conf
set -g default-session-name 'main'
set -g renumber-windows on
```

实际操作中我发现最有用的是 `tmux new -s <name>` 和 `tmux attach -t <name>` 这两个组合。比如远程服务器上有三个工作区——开发、监控、备份——各开一个 session：

```bash
tmux new -s dev
tmux new -s monitor
tmux new -s backup
```

以后直接 `tmux attach -t dev` 就能回到上次离开的地方。session 命名要起得有意义，我踩过一个坑：起名为 `1` 和 `I` 在视觉上太接近，附加的时候搞混过两次，最后花了十分钟查哪个 session 里有什么。

## 第二件事：窗口拆分和导航

tmux 的窗口（window）和 pane 的概念类似 IDE 的 tab 和分割。裸奔的时候用 `Ctrl-b %` 和 `Ctrl-b "` 手动分割，但每次打开 tmux 都是空白的一格，效率低。

我的做法是在配置里加上快捷键映射，让分割逻辑和常用编辑器一致：

```bash
# 横向分割
bind | split-window -h -c "#{pane_current_path}"
# 纵向分割
bind - split-window -v -c "#{pane_current_path}"
# 切换 pane 用 vim 风格
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R
```

`-c "#{pane_current_path}"` 这个参数很重要——新建的 pane 自动继承当前工作目录。我之前一直没加这个，每次分割完都要 `cd` 一次，折腾了快一年。

还有一个容易忽略的细节：tmux 窗口的编号是 0-9，不是从 1 开始。第一次用的时候我找了半天第一个窗口在哪。

## 第三件事：持久化和自动恢复

tmux 本身在 session 断开后会自动保留，但如果服务器重启就没了。真正的持久化需要配合 `tmux-resurrect` 插件。

安装方式很简单：

```bash
git clone https://github.com/tmux-plugins/tmux-resurrect ~/.tmux/plugins/reshurrect
~/.tmux/plugins/reshurrect/bin/resurrect_restore.sh
```

然后在 `.tmux.conf` 里加载：

```bash
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-resurrect'
init_string="run '~/.tmux/plugins/tpm/tpm'"
```

这里踩了个坑：`init_string` 的设置位置很关键。如果放在 `tmux-resurrect` 的配置之后，插件初始化顺序会错，导致 resurrect 没有正确加载快捷键。正确的做法是把所有 `set -g @plugin` 集中写在文件末尾之前，`init_string` 写在最后一个 plugin 之后。

resurrect 默认保存的内容包括：每个 pane 的工作目录、每个 window 的布局、每个 pane 中运行的命令。恢复的时候基本能做到无缝衔接。不过它不保存全局变量和环境配置——如果你在 session 里设置了 `export FOO=bar`，断开后这个变量就没了。解决方案是在 `.bashrc` 里写好环境变量，别依赖 session 级别的设置。

## 额外：状态栏要不要搞？

裸奔 tmux 的人很容易一头扎进主题配置里。我试过 powerline 风格的状态栏、带 git 分支显示的、有 cpu 和内存占用显示的。折腾了一个下午之后发现：

- 带 git 分支显示的插件在仓库里显示不错，但在非 git 目录会卡一下
- 内存/CPU 显示在跑大任务时有用，但日常开发基本不看
- 最实用的信息是：当前窗口编号、有没有未保存的变更、session 名称

所以我只保留了一个极简状态栏：

```bash
set -g status on
set -g status-style "bg=#1e1e2e,fg=#cdd6f4"
set -g status-left-length 40
set -g status-left '[#S] #W '
set -g status-right ''
set -g window-status-format ' #I:#W '
set -g window-status-current-format ' #I:#W '
```

这就是 `[session] window` 加上编号。够用了。

## 总结

三件事加半小时搞定了：

1. session 命名规范——给每个工作区一个有意义的名字，别用数字。
2. 窗口分割继承工作目录——加一个 `-c "#{pane_current_path}"`，省事巨大。
3. resurrect 插件——服务器重启不心疼，快捷键别放错位置。

tmux 的文档写得很好，man page 比网上 80% 的教程都清楚。花十分钟读一遍，比看十个配置教程省事。唯一的坑是 vim 风格导航的 `bind h/j/k/l`——第一次用的时候手指会下意识按到空格和分号上，大概两天就习惯了。

最后说一句：工具配置的最大陷阱是"再优化一下"。配到够用就停，把时间留给真正需要解决的问题。我的 tmux 配置从上周改到现在没有任何变化，这就是最好的状态。
