#!/bin/bash

fail() {
    echo "[FAIL]: $@"
    exit 1
}

succ() {
    echo "[OK]: $@"
}

usage() {
    echo "build.sh <name> <ip>"
    exit 1
}

NAME=$1

if [ "$1" == "" ];then
    usage
fi

MASTER_IP=$2

if [ "$2" == "" ];then
    usage
fi

SLAVE_USER=root
SLAVE_PASSWORD=
SLAVE_DATABASE=test


MASTER_PORT=3306
MASTER_USER=replica
MASTER_PASSWORD=repl_slave

MARIADB_IMAGE=mariadb:10.4
ROOT_DIR=/home/slaves
DATA_DIR=$ROOT_DIR/$NAME/data
SERVER_ID=$(date "+%y%m%d%H%M")



echo "Start to build slave. It may take a few minutes..."

if [ ! -d $DATA_DIR ]; then
  mkdir -p $DATA_DIR
fi

sudo docker run --name $NAME --restart=always \
     -v /etc/localtime:/etc/localtime \
     -v $DATA_DIR:/var/lib/mysql \
     -e MYSQL_ROOT_PASSWORD=$SLAVE_PASSWORD \
     -e MYSQL_DATABASE=$SLAVE_DATABASE \
     -d $MARIADB_IMAGE --server-id=$SERVER_ID --log-slave-updates=true --read-only=true > /dev/null 2>&1

[[ $? == 0 ]] && succ "Create database slave" || fail "Create database slave"

sleep 30

echo "Load data to slave..."

sudo docker exec -i $NAME /usr/bin/mysql -u$SLAVE_USER -p$SLAVE_PASSWORD $SLAVE_DATABASE < $ROOT_DIR/$NAME/init.sql > /dev/null 2>&1
[[ $? == 0 ]] && succ "Load data to slave" || fail "Load data to slave"

echo "Slave set to change master..."

sudo docker exec $NAME /usr/bin/mysql -u$SLAVE_USER -p$SLAVE_PASSWORD -AN -e "CHANGE MASTER TO master_host='$MASTER_IP', master_port=$MASTER_PORT, master_user='$MASTER_USER', master_password='$MASTER_PASSWORD', master_use_gtid=current_pos;" > /dev/null 2>&1
[[ $? == 0 ]] && succ "Slave set to change master" || fail "Slave set to change master"

echo "Start slave..."

sudo docker exec $NAME /usr/bin/mysql -u$SLAVE_USER -p$SLAVE_PASSWORD -e "start slave;\G;" > /dev/null 2>&1
[[ $? == 0 ]] && succ "Start slave" || fail "Start slave"

sleep 30

ret=$(sudo docker exec $NAME /usr/bin/mysql -u$SLAVE_USER -p$SLAVE_PASSWORD -e "show slave status \G;" | grep Running | grep Yes | wc -l) > /dev/null 2>&1
[[ $ret -eq 2 ]] && succ "Slave synced with master" || fail "Slave synced with master"
