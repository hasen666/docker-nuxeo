#!/bin/bash 
set -e

NUXEO_CONF=$NUXEO_HOME/bin/nuxeo.conf
NUXEO_DATA=${NUXEO_DATA:-/var/lib/nuxeo/data}
NUXEO_LOG=${NUXEO_LOG:-/var/log/nuxeo}

# Allow supporting arbitrary user id
if ! whoami &> /dev/null; then
  if [ -w /etc/passwd ]; then
    sed /^nuxeo/d /etc/passwd > /tmp/passwd && cp /tmp/passwd /etc/passwd
    echo "${NUXEO_USER:-nuxeo}:x:$(id -u):0:${NUXEO_USER:-nuxeo} user:${NUXEO_HOME}:/sbin/nologin" >> /etc/passwd
  fi
fi

if [ "$1" = 'nuxeoctl' ]; then
  if [ ! -f $NUXEO_HOME/configured ]; then

    # PostgreSQL conf
    if [ -n "$NUXEO_DB_TYPE" ]; then

      if [ -z "$NUXEO_DB_HOST" ]; then
        echo "You have to setup a NUXEO_DB_HOST if not using default DB type"
        exit 1
      fi
      
      NUXEO_DB_HOST=${NUXEO_DB_HOST}
      NUXEO_DB_NAME=${NUXEO_DB_NAME:-nuxeo}
      NUXEO_DB_USER=${NUXEO_DB_USER:-nuxeo}
      NUXEO_DB_PASSWORD=${NUXEO_DB_PASSWORD:-nuxeo}

    	perl -p -i -e "s/^#?(nuxeo.templates=.*$)/\1,${NUXEO_DB_TYPE}/g" $NUXEO_CONF
    	perl -p -i -e "s/^#?nuxeo.db.host=.*$/nuxeo.db.host=${NUXEO_DB_HOST}/g" $NUXEO_CONF
    	perl -p -i -e "s/^#?nuxeo.db.name=.*$/nuxeo.db.name=${NUXEO_DB_NAME}/g" $NUXEO_CONF
    	perl -p -i -e "s/^#?nuxeo.db.user=.*$/nuxeo.db.user=${NUXEO_DB_USER}/g" $NUXEO_CONF
    	perl -p -i -e "s/^#?nuxeo.db.password=.*$/nuxeo.db.password=${NUXEO_DB_PASSWORD}/g" $NUXEO_CONF
    fi


    if [ -n "$NUXEO_TEMPLATES" ]; then
      perl -p -i -e "s/^#?(nuxeo.templates=.*$)/\1,${NUXEO_TEMPLATES}/g" $NUXEO_CONF
    fi
 
    # nuxeo.url
    if [ -n "$NUXEO_URL" ]; then
      echo "nuxeo.url=$NUXEO_URL" >> $NUXEO_CONF
    fi

    if [ -n "$NUXEO_ES_HOSTS" ]; then
      echo "elasticsearch.addressList=${NUXEO_ES_HOSTS}" >> $NUXEO_CONF
      echo "elasticsearch.clusterName=${NUXEO_ES_CLUSTER_NAME:=elasticsearch}" >> $NUXEO_CONF
      echo "elasticsearch.indexName=${NUXEO_ES_INDEX_NAME:=nuxeo}" >> $NUXEO_CONF
      echo "elasticsearch.indexNumberOfReplicas=${NUXEO_ES_REPLICAS:=1}" >> $NUXEO_CONF
      echo "elasticsearch.indexNumberOfShards=${NUXEO_ES_SHARDS:=5}" >> $NUXEO_CONF
    fi

    if [ "$NUXEO_AUTOMATION_TRACE" = "true" ]; then
      echo "org.nuxeo.automation.trace=true" >> $NUXEO_CONF
    fi

    if [ "$NUXEO_DEV_MODE" = "true" ]; then
      echo "org.nuxeo.dev=true" >> $NUXEO_CONF
    fi

    if [ -n "$NUXEO_REDIS_HOST" ]; then
      echo "nuxeo.redis.enabled=true" >> $NUXEO_CONF
      echo "nuxeo.redis.host=${NUXEO_REDIS_HOST}" >> $NUXEO_CONF
      echo "nuxeo.redis.port=${NUXEO_REDIS_PORT:=6379}" >> $NUXEO_CONF
    fi

    if [ -n "$NUXEO_DDL_MODE" ]; then
      echo "nuxeo.vcs.ddlmode=${NUXEO_DDL_MODE}" >> $NUXEO_CONF
    fi

    if [ -n "$NUXEO_CUSTOM_PARAM" ]; then
      printf "%b\n" "$NUXEO_CUSTOM_PARAM" >> $NUXEO_CONF
    fi
    
    if [ -n "$NUXEO_BINARY_STORE" ]; then
      echo "repository.binary.store=$NUXEO_BINARY_STORE" >> $NUXEO_CONF
    fi

    if [ -n "$NUXEO_TRANSIENT_STORE" ]; then
      #removes transients stores if exists to allow symbolic link creation
      if [ -d $NUXEO_DATA/transientstores ]; then
          rm -rf $NUXEO_DATA/transientstores
      fi
      mkdir -p $NUXEO_DATA/transientstores
      ln -s $NUXEO_TRANSIENT_STORE $NUXEO_DATA/transientstores/default
    fi
    
    cat << EOF >> $NUXEO_CONF
nuxeo.log.dir=$NUXEO_LOG
nuxeo.pid.dir=/var/run/nuxeo
nuxeo.data.dir=$NUXEO_DATA
nuxeo.wizard.done=true
EOF

    if [ -f /nuxeo.conf ]; then
      cat /nuxeo.conf >> $NUXEO_CONF
    fi

    nuxeoctl mp-init

    touch $NUXEO_HOME/configured

  fi


  # instance.clid
  if [ -n "$NUXEO_CLID" ]; then
    # Replace --  by a carriage return
    NUXEO_CLID="${NUXEO_CLID/--/\\n}"
    printf "%b\n" "$NUXEO_CLID" >> $NUXEO_DATA/instance.clid
  fi

  for f in /docker-entrypoint-initnuxeo.d/*; do
    case "$f" in
      *.sh)  echo "$0: running $f"; . "$f" ;;
      *.zip) echo "$0: installing Nuxeo package $f"; nuxeoctl mp-install $f --accept=true ;;
      *.clid) echo "$0: copying clid to $NUXEO_DATA"; cp $f $NUXEO_DATA ;;
      *)     echo "$0: ignoring $f" ;;
    esac
    echo
  done

  ## Executed at each start
  if [ -n "$NUXEO_CLID"  ] && [ ${NUXEO_INSTALL_HOTFIX:='true'} == "true" ]; then
      nuxeoctl mp-hotfix --accept=true
  fi

  # Install packages if exist
  if [ -n "$NUXEO_PACKAGES" ]; then
    nuxeoctl mp-install $NUXEO_PACKAGES --relax=false --accept=true
  fi


  if [ "$2" = "console" ]; then
    exec nuxeoctl console
  else
    exec "$@"
  fi

fi


exec "$@"
