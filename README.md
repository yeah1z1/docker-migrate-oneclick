# Docker Migrate OneClick

Linux 服务器之间迁移 Docker 的一键工具。它可以整机迁移，也可以按容器、镜像、卷、网络单选迁移，适合从老机器搬到新机器。

> 当前版本专注 Docker Engine/CLI。Compose 项目会按容器、镜像、卷、网络恢复，但不会自动还原原始 `docker-compose.yml` 文件。

## 功能

- 一条命令从老机器迁移到新机器
- 支持全量迁移：容器、镜像、数据卷、自定义网络
- 支持单选迁移：指定容器、镜像、卷、网络
- 支持交互选择：本机运行时可用编号选择
- 自动打包镜像和 Docker volume 数据
- 恢复容器的常见参数：环境变量、标签、端口、挂载、重启策略、资源限制、网络连接等
- 纯 Python 标准库实现，无第三方 Python 依赖

## 系统要求

老机器和新机器都需要：

- Linux
- Python 3.8+
- Docker Engine，并且当前用户能执行 `docker`
- 迁移模式需要 `ssh` 和 `scp`

如果要迁移 volume 数据，脚本会使用一个辅助镜像打包/解包数据，默认是 `alpine:3.20`。

## 快速开始

在老机器上运行，把所有 Docker 对象迁移到新机器：

```bash
chmod +x ./bin/docker-migrate
./bin/docker-migrate migrate --target root@NEW_SERVER_IP --all --replace --start
```

从第三台控制机发起迁移：

```bash
./bin/docker-migrate migrate \
  --source root@OLD_SERVER_IP \
  --target root@NEW_SERVER_IP \
  --all \
  --replace \
  --start
```

只迁移指定容器，脚本会自动包含这些容器使用的镜像、命名卷和自定义网络：

```bash
./bin/docker-migrate migrate \
  --target root@NEW_SERVER_IP \
  --containers nginx,redis \
  --replace \
  --start
```

交互选择迁移对象：

```bash
./bin/docker-migrate backup --select --output ./backup
./bin/docker-migrate restore --file ./backup/docker-migrate-YYYYMMDD-HHMMSS.tar.gz --replace --start
```

## 常用命令

查看当前机器 Docker 对象：

```bash
./bin/docker-migrate list
./bin/docker-migrate list --format json
```

仅备份，不恢复：

```bash
./bin/docker-migrate backup --all --output ./backup
```

在新机器恢复：

```bash
./bin/docker-migrate restore --file ./docker-migrate-20260511-120000.tar.gz --replace --start
```

迁移指定对象：

```bash
./bin/docker-migrate migrate \
  --target root@NEW_SERVER_IP \
  --containers app,worker \
  --volumes shared_data \
  --images busybox:latest \
  --networks app_net \
  --replace \
  --start
```

迁移前短暂停住选中的运行容器，提升 volume 快照一致性：

```bash
./bin/docker-migrate migrate --target root@NEW_SERVER_IP --all --pause --replace --start
```

## 安装到系统

```bash
sudo ./install.sh
docker-migrate --version
```

也可以不安装，直接运行 `./bin/docker-migrate`。

## 发布到 GitHub

```bash
git init
git add .
git commit -m "Initial docker migration tool"
git branch -M main
git remote add origin git@github.com:YOUR_NAME/docker-migrate-oneclick.git
git push -u origin main
```

发布后可以把快速安装命令写成：

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_NAME/docker-migrate-oneclick/main/bin/docker-migrate -o docker-migrate
chmod +x docker-migrate
./docker-migrate --version
```

## 重要说明

- 数据库类容器建议先做业务级备份，或者使用 `--pause` 降低 volume 数据不一致风险。
- bind mount 的宿主机路径只会恢复挂载配置，不会自动打包宿主机目录数据。manifest 会记录相关警告。
- 如果目标机器已有同名容器或 volume，默认会跳过；使用 `--replace` 才会删除并重建。
- 自定义网络会尽量恢复 driver、IPAM、label、option 等常见配置；特殊网络插件需要目标机器已安装相同插件。
- 脚本不迁移 Docker daemon 配置、镜像仓库登录态、防火墙规则、系统服务文件、crontab 等宿主机级配置。

## 参数速查

```bash
docker-migrate list
docker-migrate backup  --all|--select|--containers app,db [--output ./backup]
docker-migrate restore --file archive.tar.gz [--replace] [--start]
docker-migrate migrate --target user@new --all [--replace] [--start]
docker-migrate migrate --source user@old --target user@new --containers app,db
```

## License

MIT
