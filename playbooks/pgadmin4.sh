#!/usr/bin/env bash
#Time    :   2025/06/11 10:29:12
#Author  :   ansible-pg

# Setup pgadmin4 client on web browser

# checking params and help tips
paramsLimit=2
[[ $# -lt $paramsLimit ]] && {
    cat<<EOF
usage of $0:
limit not less $paramsLimit params: [email: optional, default: admin@domain.com] [password: optional, default: admin]
EOF
    exit 1
}

email=$1
password=$2

# set default params
email=${email:-admin@domain.com}
password=${password:-admin}

cat<<EOF
[TIPS] The default binary paths set in the container are as follows:

DEFAULT_BINARY_PATHS = {
    'pg-17': '/usr/local/pgsql-17',
    'pg-16': '/usr/local/pgsql-16',
    'pg-15': '/usr/local/pgsql-15',
    'pg-14': '/usr/local/pgsql-14',
    'pg-13': '/usr/local/pgsql-13'
}

EOF

containerName="pgadmin4"
echo "[INFO] The container name is $containerName"
dataDir="/srv/pgadmin4"
sudo mkdir -p $dataDir
echo "[INFO] The data directory is $dataDir"

# create pgadmin user with nologin option, if not exist, UID/GID is 5050
echo "[INFO] Create pgadmin user with nologin option..."
id pgadmin > /dev/null
if [[ $? -ne 0 ]]; then
    echo "[INFO] The pgadmin user is not exist, create it..."
    sudo useradd -M -s /sbin/nologin -U -u 5050 pgadmin
    echo "[INFO] The pgadmin user is created"
else
    echo "[INFO] The pgadmin user is exist"
fi

# change dataDir owner to pgadmin user
echo "[INFO] Change dataDir owner to pgadmin user..."
sudo chown -R pgadmin:pgadmin $dataDir
echo "[INFO] The dataDir owner is changed"
# check docker is installed
which docker > /dev/null
if [[ $? -ne 0 ]]; then
    echo "[ERROR] The docker is not installed"
    exit 1
fi

# check docker image dpage/pgadmin4 is exist
sudo docker image ls | grep dpage/pgadmin4 > /dev/null
if [[ $? -ne 0 ]]; then
    echo "[ERROR] The docker image dpage/pgadmin4 is not exist"
    exit 1
fi

# update pgadmin4 container
echo "[INFO] Update pgadmin4 container..."
sudo docker pull dpage/pgadmin4 && echo "[INFO] The pgadmin4 container is updated"

# steup pgadmin4 container
echo "[INFO] Setup pgadmin4 container..."
echo "[INFO] Click web address: http://127.0.0.1:80"
echo "[INFO] The default email is $email"
echo "[INFO] The default password is $password"
sudo docker run \
    -d \
    --net host \
    --name $containerName \
    -e PGADMIN_DEFAULT_EMAIL=$email \
    -e PGADMIN_DEFAULT_PASSWORD=$password \
    -v $dataDir:/var/lib/pgadmin \
    dpage/pgadmin4 && echo "[INFO] The pgadmin4 container is setup ok"
