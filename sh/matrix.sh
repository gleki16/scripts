if [ "$1" = "in" ]; then
	sudo pacman -S --noconfirm matrix-synapse postgresql python-psycopg2

	# 不升级数据库
	sudo sed -i '/#IgnorePkg/s/#//' /etc/pacman.conf
	if ! grep -q 'postgresql' /etc/pacman.conf
		sudo sed -i '/IgnorePkg   =/s/IgnorePkg   =/& postgresql postgresql-libs/' /etc/pacman.conf
	fi

	# 初始化数据库
	sudo -u postgres initdb --locale=en_US.UTF-8 -E UTF8 -D /var/lib/postgres/data
	sudo systemctl enable postgresql

	exit 0
fi

echo "设定数据库的用户口令："
sudo -u postgres createuser --pwprompt synapse
sudo -u postgres createdb --encoding=UTF8 --locale=C --template=template0 --owner=synapse synapse

# 生成配置文件
read -p "输入服务器的域名：" domain_name

sudo -u synapse python -m synapse.app.homeserver \
	--server-name ${domain_name} \
	--config-path /etc/synapse/homeserver.yaml \
	--generate-config \
	--report-stats=yes

cat << EOF
修改 /etc/synapse/homeserver.yaml 配置

找到：
database:
  name: sqlite3
  args:
    database: /opt/synapse/homeserver.db

修改为：
database:
  name: psycopg2
  args:
    user: synapse
    password: 你刚才设定的密码
    database: synapse
    host: localhost
    cp_min: 5
    cp_max: 10

要启用注册，可以设置 enable_registration 到 True

最后设定自启动：
sudo systemctl enable --now synapse
EOF
