---
title: "你好，世界"
date: 2026-11-24T10:00:00+08:00
draft: false
# author 不写就跟随 params.toml 里的全局作者
description: "第一篇示例文章，演示 PaperMod 的常用写法，可以直接删掉或改成你自己的内容。"
summary: "一篇可直接拿来改的写作模板：标题、列表、引用、代码块、表格、图片、新建文章，覆盖日常会用到的全部写法。"
tags: ["Hugo", "教程"]
categories: ["随笔"]
# 下面这些显示项不写就跟随 params.toml 的全局设置；
# 想只针对这一篇调整时再取消注释
# ShowToc: true
# TocOpen: false
# ShowReadingTime: false
# ShowShareButtons: false
---

这是博客的第一篇文章，同时也是一个写作模板：下面这些写法在 PaperMod 里都能直接用。

## 一、写标题

用 `##` 写二级标题、`###` 写三级标题，它们会自动出现在右侧目录（TOC）里。
TOC 的层级范围在 `hugo.toml` 的 `[markup.tableOfContents]` 里调整。

### 小标题示例

普通段落直接写就好。**加粗**、*斜体*、`行内代码`、[链接](https://gohugo.io/) 都是标准 Markdown 语法。

## 二、列表和引用

无序列表：

- 第一项
- 第二项
  - 嵌套项

有序列表：

1. 先改 `config/_default/params.toml`
2. 再跑 `hugo server`
3. 最后部署

引用块：

> 写博客最重要的不是工具，而是持续记录。

## 三、代码块

代码块右上角会自动出现「复制」按钮（由 `ShowCodeCopyButtons` 控制）：

```go
package main

import "fmt"

func main() {
    fmt.Println("Hello, Hugo!")
}
```

## 四、表格

| 配置项 | 作用 | 修改位置 |
| --- | --- | --- |
| `title` | 站名 | `hugo.toml` |
| `defaultTheme` | 默认配色 | `params.toml` |
| `ShowToc` | 是否显示目录 | `params.toml` |

## 五、图片

把图片放进 `dev/static/images/`，然后用标准 Markdown 引用：

```markdown
![图片说明](/images/文件名.png)
```

## 六、新建文章

在 `dev` 目录执行：

```bash
hugo new content posts/文章名.md
```

会自动套用 `archetypes/default.md` 的模板，并把 `draft` 设为 `true`。
写完把 `draft` 改成 `false`，或者用 `hugo server -D` 预览草稿。

---

这篇文章留着当参考，随时可以删除：删掉 `content/posts/hello-world.md` 即可。
