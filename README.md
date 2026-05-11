# Docker迁移一键通

一条命令完成 Linux 服务器 Docker 容器迁移。老机器生成迁移包下载链接，新机器输入链接自动恢复，支持全量迁移，也支持按编号单选/多选容器迁移。

## 一条命令运行

老机器和新机器都执行同一条命令：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yeah1z1/docker-migrate-oneclick/main/docker-migrate.sh)
```

运行后出现中文菜单：

```text
1) 老机器：备份并生成下载链接
2) 新机器：输入链接下载并恢复
3) 只备份到本地文件
4) 从本地迁移包恢复
5) 退出
```

## 典型流程

老机器执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yeah1z1/docker-migrate-oneclick/main/docker-migrate.sh)
```

选择 `1) 老机器：备份并生成下载链接`，然后选择全部容器或按编号选择容器。脚本会输出一个迁移包链接。

新机器执行同一条命令：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yeah1z1/docker-migrate-oneclick/main/docker-migrate.sh)
```

选择 `2) 新机器：输入链接下载并恢复`，粘贴老机器生成的链接即可。

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
