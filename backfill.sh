#!/bin/bash
# chainweb-data db sync script
check=$(curl -SsL -k -m 15 https://172.15.0.1:30004/chainweb/0.0/mainnet01/cut | jq .height)
if [[ "$check" == "" ]]; then
  until [[ "$check" != "" ]] ; do
    check=$(curl -SsL -k -m 15 https://172.15.0.1:30004/chainweb/0.0/mainnet01/cut | jq .height)
    echo -e "Waiting for KDA node..."
    sleep 300
  done
fi

if [[ -f /tmp/backfill ]]; then
    echo -e "Running fill as gaps..."
    chainweb-data fill --service-host=172.15.0.1 --p2p-host=172.15.0.1 --service-port=30005 --p2p-port=30004 --dbuser=postgres --dbpass=postgres --dbname=postgres
    echo -e "Restarting chainweb-data..."
    kill -9 $(ps aux | grep 'chainweb-data server --port 8888' | awk '{ print $2 }' | head -n1)
    exit
fi

x=0
backfill_count=0

until [[ "$x" == 1 ]] ; do

  if [[ -f /usr/local/bin/chainweb-data ]]; then
   # give time postgres to run
    if [[ "$backfill_count" == 0 ]]; then
      sleep 600
    else
      sleep 10
    fi
  else
    # Allow time to build chainweb-data binary and for postgres to run
    sleep 1000
  fi

  server_check=$(ps aux | grep idle | wc -l)

  if [[ "$server_check" == 2 ]]; then

    date_timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "Fill started at $date_timestamp"
    chainweb-data fill --service-host=172.15.0.1 --p2p-host=172.15.0.1 --service-port=30005 --p2p-port=30004 --dbuser=postgres --dbpass=postgres --dbname=postgres +RTS -N
    sleep 10
    progress_check=$(cat $(ls /var/log/supervisor | grep chainweb-backfill-stdout | awk {'print "/var/log/supervisor/"$1'} ) | tail -n1 | egrep 'Progress' | egrep -o -E '[0-9]+\.[0-9]+' | egrep -o -E '[0-9]+' | head -n1 )
    date_timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    backfill_count=$((backfill_count+1))

     if [[ "$progress_check" != "" ]]; then
      echo -e "Fill progress: $progress_check %, stopped at $date_timestamp, counter: $backfill_count"
     else
      echo -e "Fill stopped at $date_timestamp, counter: $backfill_count"
     fi

     if [[ "$progress_check" -ge 99 ]]; then
       x=1
       echo -e "Fill Complited!" >> /tmp/backfill
       echo -e "Restarting chainweb-data..."
       kill -9 $(ps aux | grep 'chainweb-data server --port 8888' | awk '{ print $2 }' | head -n1)
       if [[ ! -f /tmp/crone ]]; then
         sleep 120
         echo -e "Added crone job for fill as gaps..."
         (crontab -l -u "$USER" 2>/dev/null; echo "30 22 * * *  /bin/bash /gaps.sh > /tmp/fill_output.log 2>&1") | crontab -
         echo -e "Cron job added!" >> /tmp/crone
       else
         echo -e "Cron job already exist..."
       fi
       exit
     fi

     if [[ "$progress_check" == "" && "$backfill_count" == 2 ]] ; then
        x=1
        echo -e "Fill Complited!" >> /tmp/backfill
        echo -e "Restarting chainweb-data..."
        kill -9 $(ps aux | grep 'chainweb-data server --port 8888' | awk '{ print $2 }' | head -n1)
        if [[ ! -f /tmp/crone ]]; then
          sleep 120
          echo -e "Added crone job for fill as gaps..."
          (crontab -l -u "$USER" 2>/dev/null; echo "30 22 * * *  /bin/bash /gaps.sh > /tmp/fill_output.log 2>&1") | crontab -
          echo -e "Crone job added!" >> /tmp/crone
         else
          echo -e "Crone job already exist..."
        fi
        exit
      fi
  fi
done
