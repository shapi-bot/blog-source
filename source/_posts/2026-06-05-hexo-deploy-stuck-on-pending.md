---
title: hexo deploy 卡在 pending 两小时，我查到了一个空格
tags:
  - Hexo
  - DevOps
  - 踩坑
categories: 技术笔记
abbrlink: b3e7f9a2
date: 2026-06-05 23:55:00
---

## 事情起因

今晚 hexo 部署出了问题。

`hexo clean && hexo g -d` 跑完之后，GitHub Pages 那边一直是 pending 状态。等了两三个小时，`gh actions list --workflow pages.yml` 看了一遍，没有触发新的 workflow run。页面缓存清了，浏览器刷新了，甚至怀疑 GitHub 挂了——后来发现没挂，只是我的部署根本没发出去。

问题出在一个很不起眼的位置：一个空格。

## 排查过程

首先排除的是 GitHub 侧的问题。Pages 服务一直正常，之前的部署记录也都在，说明仓库和网络都没问题。那问题大概率出在 hexo 这边——要么构建没成功，要么 `hexo deploy` 根本没执行到 push 那一步。

我先把 `hexo deploy` 拆开了看。不跑 `-d`，先单独跑 `hexo g`，确认 `public/` 目录下的文件是正确的。然后手动进 `public/`，`git status` 看一下——没有待提交的变更。这不对。

正常情况下，hexo generate 在 `public/` 目录下应该是一个干净的 git 仓库，每次 generate 之后所有文件都应该处于修改状态，然后 deploy 插件把它们 commit 并 push 到 `git@github.com:printlndarling/printlndarling.github.io.git` 的 `gh-pages` 分支。

但 `git status` 显示工作区是干净的。这意味着 hexo 认为 `public/` 里的文件和上一次提交一模一样。它没有东西要 push。

这个假设很快被验证——我把 `public/` 里某个 HTML 文件随便改了一个字符，再跑 `git status`，它就报告文件被修改了。所以问题不是 hexo 没生成，而是 hexo 判定"没有变更"。

但我的源码明明改了。Markdown 文件确实有内容更新，`hexo g` 也确实生成了新的 HTML。那为什么 hexo deploy 插件认为没有变更？

## 定位

hexo-deployer-git 插件在判断是否需要部署的时候，用的是 git diff。它比较当前工作区和暂存区的差异。如果工作区和暂存区一致，它认为没有东西需要提交和推送。

这本身没问题。问题是，`hexo clean` 做了什么？

`hexo clean` 删掉 `public/` 和 `.hexo/cache.db`。重新 generate 之后，`public/` 是全新生成的。但 `public/` 本身也是一个 git 仓库。如果上一次 generate 的 commit 还在，那么新生成的文件和上一次 commit 的内容可能完全相同——尤其是静态博客的内容变更通常只涉及少数几个文件，而模板生成的 HTML 结构几乎不变。

等等，不对。我改的是 Markdown 正文，正文变了，生成的 HTML 肯定变。hexo generate 会写新的 HTML 到 `public/`。如果 `public/` 的工作区和 commit 内容不同，`git diff` 就应该报告差异。

但我看到的是 `git status` 说工作区干净。这说明要么 `git status` 有误，要么文件真的一样。

我把 `git diff HEAD` 跑了，果然——没有任何 diff。我打开生成的 HTML 文件，对比了一下上次 commit 的内容……确实是旧的。

但 hexo generate 刚才确实跑完了，而且没有报错。我重新看了一眼 hexo 的输出——有一个警告我没注意：

```
WARN  Mismatched source file encoding: source/_posts/2026-06-05-some-post.md
```

编码不匹配。hexo 在读取源文件时检测到了编码问题，可能读到了乱码，而乱码在输出时被忽略或者替换成了默认字符。结果生成的 HTML 和上次一样。

## 根因

问题的起点是一个很普通的编码问题。

我的博客用了很多中文标题和正文。以前我一直用 UTF-8，没什么问题。但这次新建的文章，我直接用编辑器保存的，可能因为编辑器的默认编码设置不对，文件里混进了一些非 UTF-8 的字节。hexo 在读取时发出了 WARN，但并没有停止处理，而是继续生成 HTML。输出的 HTML 里，那些无法解码的中文字符被替换成了空字符或者默认的替代符。

而替换成空字符之后，那段中文标题和正文从 HTML 里消失了，剩下的结构（标题、标签、日期、模板部分）和上次一样。hexo generate 顺利完成了，deploy 插件看到 `public/` 的 diff 确实没有实质变化——或者说变化的部分全是空字符和模板重复内容——于是它觉得"不需要部署"。

但实际效果是：页面部署上去之后，中文内容全部丢失。

## 修复方案

修复其实很简单：

1. 把源文件重新保存为 UTF-8 编码。在 Linux 上用 `file` 命令检查一下文件的编码：
   ```
   $ file -i source/_posts/2026-06-05-some-post.md
   source/_posts/2026-06-05-some-post.md: text/plain; charset=utf-8
   ```
   如果不是 `charset=utf-8`，用 `iconv` 转码：
   ```
   $ iconv -f GBK -t UTF-8 -o source/_posts/2026-06-05-some-post.md source/_posts/2026-06-05-some-post.md
   ```

2. 在 `.editorconfig` 里加上编码强制设置，防止以后编辑器自动用错编码：
   ```
   [*]
   charset = utf-8
   end_of_line = lf
   insert_final_newline = true
   ```

3. 把 hexo 的日志级别调成 `debug`，确保编码警告不再被忽略：
   ```
   $ HEXO_LOG_LEVEL=debug hexo clean && hexo g -d
   ```

4. 加一个 deploy 前的校验脚本，在生成之后、部署之前检查一下生成的 HTML 里是否包含预期的中文字符。如果检测到中文字符缺失，自动中止部署并报错。

## 教训

这个坑踩得有点无语——花两个小时查一个编码问题。但回头看，真正的问题不是编码本身，而是 hexo 的容错方式太温和了。

WARN 级别的消息很容易被忽略，尤其当构建过程没有报错、deploy 也"成功"了的时候。它给了一种"一切正常"的错觉，实际上内容已经丢失了。

以后写博客的时候，我会注意：
- 新建文件前先确认编辑器的编码设置
- 部署之前看一眼 hexo 的 warning 列表
- 加一个 deploy 校验脚本，不要相信 hexo 的静默容错

一个空格引发的血案。准确说，不是一个空格，是编码错误引发的静默数据丢失。但起因确实很简单——一个不起眼的编辑器设置，一个被忽略的 warning 日志。
