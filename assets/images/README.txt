把你的头像图片放在这个文件夹里（dev\assets\images\）。

支持 png / jpg / webp / gif。

放好之后告诉我文件名，例如 avatar.png，
我会在 params.toml 里改成：

    [profileMode]
      imageUrl = 'images/avatar.png'
      imageWidth = 150
      imageHeight = 150

建议图片是正方形，至少 300×300，这样清晰度够。
