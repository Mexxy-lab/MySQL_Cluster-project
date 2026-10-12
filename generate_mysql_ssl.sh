#!/usr/bin/env bash
# auto self generated ssl certs
# auto generated mysql ssl certs
#################  SCRIPT  BELOW ###################
# The keys will be generated in this directory: $MYSQL_REPL_KEY_DIR
MYSQL_REPL_KEY_DIR="./key"
MASTER_SSL_CAPATH="$MYSQL_REPL_KEY_DIR"
MASTER_SSL_CA_CERT="$MYSQL_REPL_KEY_DIR/ca-cert.pem"
MASTER_SSL_CA_KEY="$MYSQL_REPL_KEY_DIR/ca-key.pem"
MASTER_SSL_CLI_CERT="$MYSQL_REPL_KEY_DIR/client-cert.pem"
MASTER_SSL_CLI_KEY="$MYSQL_REPL_KEY_DIR/client-key.pem"
MASTER_SSL_CLI_CERT_REQ="$MYSQL_REPL_KEY_DIR/client-req.pem"
MASTER_SSL_SERV_CERT="$MYSQL_REPL_KEY_DIR/server-cert.pem"
MASTER_SSL_SERV_CERT_REQ="$MYSQL_REPL_KEY_DIR/server-req.pem"
MASTER_SSL_SERV_KEY="$MYSQL_REPL_KEY_DIR/server-key.pem"
commonname="DBA Server"
country="UK"
state="UK"
locality="UK"
organization="Macetron"
organizationalunit="DBA Support"
organizationalunit_serv="DBA Support Server"
organizationalunit_cli="DBA Support Client"
email="dbamail@macetron.com"
password=""

if ! test -d "$MYSQL_REPL_KEY_DIR" ; then
    mkdir -p $MYSQL_REPL_KEY_DIR
fi

if ! test -f "$MASTER_SSL_CA_CERT" || ! test -f "$MASTER_SSL_CA_KEY" ||! test -f "$MASTER_SSL_SERV_KEY"  || ! test -f "$MASTER_SSL_SERV_CERT"; then
    if ! test -f "$MASTER_SSL_CA_KEY"; then
        openssl genrsa 2048 > $MASTER_SSL_CA_KEY
        openssl req -new  -x509 -nodes -days 3600 -key $MASTER_SSL_CA_KEY -out $MASTER_SSL_CA_CERT -passin pass:$password \
            -subj "/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizationalunit/CN=$commonname/emailAddress=$email"
    fi

    if ! test -f "$MASTER_SSL_CA_CERT"; then
        openssl req -new  -x509 -nodes -days 3600 -key $MASTER_SSL_CA_KEY -out $MASTER_SSL_CA_CERT -passin pass:$password \
            -subj "/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizationalunit/CN=$commonname/emailAddress=$email"
    fi

    openssl req -newkey rsa:2048 -days 3600 -nodes -keyout ${MASTER_SSL_SERV_KEY} -out ${MASTER_SSL_SERV_CERT_REQ} -passin pass:$password \
        -subj "/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizationalunit_serv/CN=$commonname/emailAddress=$email"

    openssl rsa -in ${MASTER_SSL_SERV_KEY} -out ${MASTER_SSL_SERV_KEY}

    openssl x509 -req -in ${MASTER_SSL_SERV_CERT_REQ} -days 3600 -CA ${MASTER_SSL_CA_CERT} -CAkey ${MASTER_SSL_CA_KEY} -set_serial 01 -out ${MASTER_SSL_SERV_CERT}

    openssl req -newkey rsa:2048 -days 3600 -nodes -keyout ${MASTER_SSL_CLI_KEY} -out ${MASTER_SSL_CLI_CERT_REQ}  -passin pass:$password \
        -subj "/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizationalunit_cli/CN=$commonname/emailAddress=$email"

    openssl rsa -in ${MASTER_SSL_CLI_KEY} -out ${MASTER_SSL_CLI_KEY}

    openssl x509 -req -in ${MASTER_SSL_CLI_CERT_REQ} -days 3600 -CA ${MASTER_SSL_CA_CERT} -CAkey ${MASTER_SSL_CA_KEY} -set_serial 01 -out ${MASTER_SSL_CLI_CERT}

    openssl verify -CAfile ${MASTER_SSL_CA_CERT} ${MASTER_SSL_SERV_CERT}  ${MASTER_SSL_CLI_CERT}

    echo -e "Key files can be found in: ${MYSQL_REPL_KEY_DIR} \n $MASTER_SSL_SERV_KEY \n $MASTER_SSL_SERV_CERT \n $MASTER_SSL_CA_CERT"
fi

############### END #####################
