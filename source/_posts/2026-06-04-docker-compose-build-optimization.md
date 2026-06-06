---
title: Docker Compose 构建优化：从 2GB 到 80MB 的折腾
tags:
  - Docker
  - DevOps
  - 踩坑
categories: 技术笔记
abbrlink: c4f82e91
date: 2026-06-04 23:55:00
---

## 事情起因

这两天在本地搭一个测试环境，一个 Go 服务加上 Redis 和 PostgreSQL，用了 Docker Compose 编排。事情本身不复杂，但我发现 `docker compose up -d --build` 之后，`docker images` 一查，光那个 Go 服务的镜像就有 1.8GB。

一个编译好的二进制文件才 50MB，怎么会变成 1.8GB？这就有点说不过去了。

## 第一阶段：最朴素的 Dockerfile

最开始写的 Dockerfile 大概是这样的：

```dockerfile
FROM golang:1.22
WORKDIR /app
COPY . .
RUN go build -o server .
EXPOSE 8080
CMD ["./server"]
```

很直观，没什么花活。build 成功，容器能跑，看起来一切正常。但镜像体积确实太大了。

拆开来看 `golang:1.22` 这个基础镜像本身就接近 1.2GB。它里面塞满了编译器、标准库、各种开发工具。而我们的容器里只需要最终编译出来的那个二进制文件，根本不需要 Go 编译环境。

这一步踩的坑其实挺常见的——忘了 Docker 的镜像是分层叠加的。每一层都会被保留在镜像里。`COPY . .` 会把整个项目目录（包括 `vendor/`、测试数据、甚至 `.git`）全部塞进镜像里。

## 第二阶段：多阶段构建

多阶段构建是解决这个问题的标准方案。思路很简单：第一阶段用完整的 Go 镜像编译，第二阶段把编译产物复制到一个极小的运行时镜像里。

```dockerfile
# Build stage
FROM golang:1.22 AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o server .

# Runtime stage
FROM alpine:3.19
WORKDIR /app
COPY --from=builder /app/server .
EXPOSE 8080
CMD ["./server"]
```

这个改法有几个要点：

1. `go mod download` 放在 `COPY . .` 之前。这是利用 Docker 的层缓存机制——`go.mod` 和 `go.sum` 变动频率低，单独 COPY 可以让依赖下载阶段被缓存，只有源码变动时才重新编译。
2. `CGO_ENABLED=0` 让 Go 编译器输出纯静态二进制，不依赖目标系统的 glibc 等 C 库。这样才能在 Alpine 这种用 musl libc 的系统上跑。
3. `-ldflags="-s -w"` 去掉调试符号和 DWARF 信息，二进制文件直接缩小 30% 左右。

效果如何？镜像从 1.8GB 掉到了 150MB 左右。降了一个数量级，看起来不错。

但 150MB 对于一个只需要跑一个二进制文件的容器来说，还是太胖了。Alpine 本身虽然小，但 `apk` 包管理器、musl libc、基础工具链加起来也有几十 MB。而且 Alpine 用的 musl libc 和 glibc 在一些边缘场景下会有兼容性问题——比如某些 C 扩展的 Go 库在 musl 上可能行为不一致。

## 第三阶段：Distroless

Google 的 distroless 镜像是一个没有操作系统感的镜像。它只有你需要的运行时——比如 Go 应用的 glibc 运行时，Python 应用的 Python 运行时，Java 应用的 JRE。没有 shell，没有包管理器，没有多余的库。

```dockerfile
FROM golang:1.22 AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o server .

FROM gcr.io/distroless/static-debian12
COPY --from=builder /app/server /server
EXPOSE 8080
CMD ["/server"]
```

`distroless/static-debian12` 里只有 glibc 和 CA 证书。最终镜像大小掉到了 80MB 上下。

不过 distroless 的缺点是排障困难——容器里没有 `/bin/sh`，出问题只能看日志，没法 exec 进去调试。这个取舍要看使用场景。开发环境可以容忍大一点，生产环境追求小和安全性。

## 第四个坑：docker-compose.yml 里的构建缓存

多阶段构建和镜像瘦身都搞定了，但每次改一行代码然后 `docker compose up -d --build`，编译还是要等几十秒。因为 Docker 默认不会持久化构建缓存。

有两个方向可以优化：

**方案一：用 BuildKit 的缓存后端**

```yaml
services:
  server:
    build:
      context: .
      cache-from:
        - type=local,src=/tmp/.buildx-cache
      cache-to:
        - type=local,dest=/tmp/.buildx-cache-new,mode=max
```

然后在构建时开启：

```bash
DOCKER_BUILDKIT=1 docker buildx build --cache-from=type=local,src=/tmp/.buildx-cache --cache-to=type=local,dest=/tmp/.buildx-cache-new -t myserver .
```

`mode=max` 会把所有中间层都缓存下来，而不仅仅是最终层。第一次构建慢，但后续增量编译就快了。

**方案二：用 docker-compose 自带的 cache_from**

在 `docker-compose.yml` 里直接指定：

```yaml
services:
  server:
    build:
      context: .
      cache_from:
        - myserver:latest
```

这样 Docker 会用已有镜像的层作为缓存起点。最简单，不需要额外的缓存目录管理。缺点是缓存质量和 BuildKit 的 `type=local` 方案比不了，但对于日常开发够了。

## 第五个坑：.dockerignore

这一步本来应该最先做的。`.dockerignore` 决定了 `COPY . .` 时哪些文件被排除。没有它的话，`.git` 目录（可能几百 MB）、`node_modules`、编译中间产物、临时文件全都会被塞进镜像，还会拖慢构建速度。

一个基本的 `.dockerignore`：

```
.git
.gitignore
*.md
.dockerignore
Dockerfile
docker-compose.yml
.github/
.vscode/
*.log
coverage/
```

加上这个之后，`COPY . .` 的速度明显快了，镜像层也干净了不少。

## 总结

折腾了一圈下来，这个 Go 服务从 1.8GB 到了 80MB，主要收获是：

1. 多阶段构建是必须的，不要觉得麻烦。它解决的不只是体积问题，还有安全性——最终镜像里没有编译器，攻击面小了很多。
2. 层缓存的顺序很重要。先 COPY 不变的文件，再 COPY 频繁变动的源码，这比一次性 COPY 整个项目效率高得多。
3. `.dockerignore` 是隐形杀手。不加的话，前面的优化效果都会打折扣。
4. BuildKit 缓存不是银弹。它解决了重复编译的问题，但需要额外的管理成本。如果团队里有多个开发者，要把缓存目录纳入 `.gitignore`，否则每个人的缓存互相覆盖反而可能更慢。
5. 镜像大小和调试便利性之间存在 tradeoff。distroless 很小但不好调试，Alpine 稍大但能用 `sh` 进去看东西。根据场景选就好，没有绝对的正确选择。

最后一次构建之后，`docker images` 输出：

```
myserver              latest    4a8f3b2c1d0e   3 minutes ago    82MB
redis                 7-alpine  5e8a7b6c4d3e   2 weeks ago      35MB
postgres              16-alpine d1a2b3c4e5f6   1 month ago      42MB
```

整体看起来顺眼多了。
