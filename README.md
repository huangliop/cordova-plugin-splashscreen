---
title: Splashscreen 插件扩展
description: 在原有插件基础上扩展了启动时加载广告图片的功能。仅支持Android iOS
---

## 原理
    在App启动时，Splashscreen插件会先去检查应用缓存目录下是否存在图片文件，如果有则加载这个图片；如果没有就加载原来设置的启动页
## 广告图片存放位置
    请将需要显示的广告图片放在，缓存下面的 ads/ad.jpg中
    android路径:context.getCacheDir()+"/ads/ad.jpg"
        iOS路径:NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
                NSString *path = [[paths objectAtIndex:0] stringByAppendingString:@"/ads/ad.jpg"];
