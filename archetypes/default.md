+++
date = '{{ .Date }}'
draft = true
title = '{{ replace .File.ContentBaseName "-" " " | title }}'

# ↓ 下面都是可选项，用到时取消注释
# description = '一句话摘要，会显示在列表页和搜索结果里'
# author = '博主'
# tags = ['标签1', '标签2']
# categories = ['分类名']

# 文章目录
# ShowToc = true
# TocOpen = false

# 这篇文章单独关掉某些显示项
# ShowReadingTime = false
# ShowShareButtons = false
# ShowPostNavLinks = false
# hideMeta = false

# 封面图（图片放 dev/static/images/ 下，写 /images/xxx.png）
# [cover]
#   image = '/images/封面.png'
#   caption = '图片说明'
#   alt = '图片替代文字'
+++
