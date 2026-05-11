# Docker迁移一键通

一条命令完成 Linux 服务器 Docker 容器迁移。老机器生成迁移包下载链接，新机器输入链接自动恢复，支持全量迁移，也支持按编号单选/多选容器迁移。

## 一条命令运行

老机器和新机器都执行同一条命令：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yeah1z1/docker-migrate-oneclick/main/docker-migrate.sh)
```

运行后出现中文菜单：

```text
1) 打开可视化网页控制台
2) 老机器：备份并生成下载链接
3) 新机器：输入链接下载并恢复
4) 只备份到本地文件
5) 从本地迁移包恢复
6) 退出
```

## 可视化网页

推荐直接用 Docker 镜像启动网页控制台，端口固定为 `5555`：

```bash
docker run -d \
  --name docker-migrate-cn \
  --restart unless-stopped \
  -p 5555:5555 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /tmp/docker-migrate-cn:/tmp/docker-migrate-cn \
  -v /:/host \
  -e HOST_ROOT=/host \
  ghcr.io/yeah1z1/docker-migrate-oneclick:latest
```

查看访问地址和 token：

```bash
docker logs docker-migrate-cn
```

也可以不使用镜像，老机器直接运行脚本启动网页控制台：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yeah1z1/docker-migrate-oneclick/main/docker-migrate.sh) --web
```

脚本会输出类似下面的访问地址：

```text
本机访问：http://127.0.0.1:5555/?token=xxxx
局域网访问：http://OLD_SERVER_IP:5555/?token=xxxx
```

在网页里可以：

- 查看所有 Docker 容器、镜像、端口、数据卷、挂载目录、网络
- 勾选要迁移的容器
- 选择是否在备份前临时停止运行容器
- 一键生成迁移包下载链接
- 在新机器网页里粘贴迁移包链接并恢复

网页地址会带一次性 `token`，不要把网页控制台暴露到公网。

如果想让日志里直接显示正确的访问地址，可以额外加 `-e PUBLIC_HOST=你的服务器IP`。如果不填，也可以直接访问 `http://服务器IP:5555`。如果你不想让工具容器拥有宿主机根目录写权限，只在老机器备份时可以把 `-v /:/host` 改成 `-v /:/host:ro`。新机器恢复 bind mount 数据时需要写权限。

## 典型流程

老机器执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yeah1z1/docker-migrate-oneclick/main/docker-migrate.sh)
```

选择 `1) 打开可视化网页控制台`，在网页勾选要迁移的容器并生成迁移包链接。

新机器执行同一条命令：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yeah1z1/docker-migrate-oneclick/main/docker-migrate.sh)
```

可以选择 `1) 打开可视化网页控制台`，在网页里粘贴老机器生成的链接恢复；也可以选择 `3) 新机器：输入链接下载并恢复`。

## 非交互用法

全量备份并生成下载链接：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yeah1z1/docker-migrate-oneclick/main/docker-migrate.sh) --backup-link --all
```

指定容器迁移：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yeah1z1/docker-migrate-oneclick/main/docker-migrate.sh) --backup-link --containers nginx,redis
```

新机器直接下载恢复：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yeah1z1/docker-migrate-oneclick/main/docker-migrate.sh) --restore http://OLD_SERVER_IP:8088/docker_migrate_xxx.tar.gz
```

只备份到本地文件：

```bash
bash docker-migrate.sh --backup-local --all
```

启动网页控制台并指定端口：

```bash
WEB_PORT=5555 bash <(curl -fsSL https://raw.githubusercontent.com/yeah1z1/docker-migrate-oneclick/main/docker-migrate.sh) --web
```

## 会迁移什么

- Docker 镜像
- 容器配置
- 命名数据卷 volume
- bind mount 宿主机目录数据
- 自定义 Docker 网络
- 常见容器参数：环境变量、标签、端口映射、挂载、重启策略、用户、工作目录、特权模式等

## 系统要求

- Linux
- Docker Engine
- `bash`
- `curl`
- `jq`
- `tar`
- `gzip`
- `python3`

脚本会尝试自动安装缺少的常用依赖；Docker Engine 需要你提前安装并启动。

## 自定义端口

老机器分享迁移包默认使用 `8088` 端口：

```bash
PORT=9000 bash <(curl -fsSL https://raw.githubusercontent.com/yeah1z1/docker-migrate-oneclick/main/docker-migrate.sh)
```

网页控制台默认使用 `5555` 端口：

```bash
WEB_PORT=5555 bash <(curl -fsSL https://raw.githubusercontent.com/yeah1z1/docker-migrate-oneclick/main/docker-migrate.sh) --web
```

## Docker Compose

也可以用 Compose 启动：

```bash
curl -fsSL https://raw.githubusercontent.com/yeah1z1/docker-migrate-oneclick/main/compose.yml -o compose.yml
docker compose up -d
docker logs docker-migrate-cn
```

## 安装为本地命令

```bash
git clone https://github.com/yeah1z1/docker-migrate-oneclick.git
cd docker-migrate-oneclick
sudo ./install.sh
docker-migrate-cn
```

## 注意事项

- 数据库容器建议先做业务级备份，迁移时选择临时停止容器可以降低数据不一致风险。
- bind mount 会按原宿主机绝对路径恢复，新机器路径规划要提前确认。
- 目标机器已有同名容器时会删除后重建；已有 volume 会覆盖写入数据。
- 特殊网络插件、特殊存储驱动、宿主机防火墙、系统服务、crontab、Docker daemon 配置不在迁移范围内。

## 开源协议

MIT
