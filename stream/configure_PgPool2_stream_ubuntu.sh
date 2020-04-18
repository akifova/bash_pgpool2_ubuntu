#!/bin/bash

scriptPath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
lastPostgreSqlVersion=12
pgPool2Version="4.1.1-2.pgdg18.04+1"
pgPoolRepo="deb http://apt.postgresql.org/pub/repos/apt/ bionic-pgdg main"
pgPoolRepoKey="https://www.postgresql.org/media/keys/ACCC4CF8.asc"
postgreSqlArchiveDir=/var/lib/postgresql/archivedir/

declare -a msg
declare -a extFiles
extFiles[0]=${scriptPath}/pgpool_remote_start.sh
extFiles[1]=${scriptPath}/recovery_1st_stage.sh
extFiles[2]=${scriptPath}/follow_master.sh
extFiles[3]=${scriptPath}/failover.sh

activeServerIp=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1')
readHostName=$(hostname)
inputPgPoolParameters=0
inputPostgreParameters=0
inputServerParameters=0

main()
{
    clear
    showBanner
    setLanguage
    clear
    showBanner

    while :
    do
    	printf "\n\n\n\n===============================================\n"
    	pm 22 "q"
    	read  menuSelect

		case $menuSelect in
			0)
				checkPostgreSQL
				checkPgPool2
				;;
			1)
				postgreSqlConfigParams 1
				;;
			2)
				pgPoolConfigParams 1
				;;
			3)
				installLoadBalancer
				;;
			4)
			    clearInstallation
			    ;;
			5)
				exit
				;;
		esac
    done
}

clearInstallation()
{
    sudo apt-get remove --purge -y pgpool2
    sudo apt-get remove --purge -y postgresql-*
    sudo -u root -H sh -c "rm ~/.pgpoolkey"
    sudo rm /var/lib/postgresql/.pgpass
    sudo rm /etc/pgpool2/follow_master.sh
    sudo rm /etc/pgpool2/failover.sh
    sudo rm ${postgreSqlDataDir}/pgpool_remote_start
    sudo rm ${postgreSqlDataDir}/recovery_1st_stage
    sudo rm -R /etc/postgresql
    sudo rm -R /etc/pgpool2/
}

installLoadBalancer()
{
    clear
    checkToolkits
    checkPostgreSQL
    checkPgPool2

    if [ ${installPostgreSql} == 1 ]
    then
        checkPostgreSqlRepository
        sudo apt-get install -y postgresql-12 postgresql-client-12 postgresql-server-dev-12
        sudo mkdir ${postgreSqlArchiveDir}
        sudo chown postgres:postgres -R ${postgreSqlArchiveDir}
    fi

    if [ ${installPgPool2} == 1 ]
    then
        checkPostgreSqlRepository
        sudo apt-get install -y pgpool2=4.1.1-2.pgdg18.04+1
        pm 47 "i"
        sudo adduser pgpool
    fi

    enablePortsOnFirewall
    sudo systemctl start postgresql
    sudo systemctl start pgpool2.service

    createUsersOnPostgreSQL
    installPgPoolRecovery
    updatePostgreSqlLocations 1
    postgreSqlConfigParams 2
    postgreSqlAuthenticationConfig
    pgPoolConfigParams 2
    externalFiles 1
    passwords
    setSSHKeys
    apt-get update
    pm 28 "d"
    echo "sudo -u root -H sh -c 'ssh-copy-id -i ~/.ssh/id_rsa_pgpool.pub postgres@${firstServerIp}'"
    echo "sudo -u root -H sh -c 'ssh-copy-id -i ~/.ssh/id_rsa_pgpool.pub postgres@${secondServerIp}'"
    echo "sudo -u root -H sh -c 'ssh-copy-id -i ~/.ssh/id_rsa_pgpool.pub postgres@${thirdServerIp}'"
    echo "sudo -u postgres -H sh -c 'ssh-copy-id -i ~/.ssh/id_rsa_pgpool.pub postgres@${firstServerIp}'"
    echo "sudo -u postgres -H sh -c 'ssh-copy-id -i ~/.ssh/id_rsa_pgpool.pub postgres@${secondServerIp}'"
    echo "sudo -u postgres -H sh -c 'ssh-copy-id -i ~/.ssh/id_rsa_pgpool.pub postgres@${thirdServerIp}'"

    echo "sudo -u postgres -i"
    echo "mkdir -p ~/.ssh"
    echo "cd ~/.ssh"
    echo "ssh-keygen -t rsa -f ~/.ssh/id_rsa_pgpool"
    echo "sudo ssh-copy-id -i ~/.ssh/id_rsa_pgpool.pub postgres@${firstServerIp}"
    echo "sudo ssh-copy-id -i ~/.ssh/id_rsa_pgpool.pub postgres@${secondServerIp}"
    echo "sudo ssh-copy-id -i ~/.ssh/id_rsa_pgpool.pub postgres@${thirdServerIp}"
    echo "chmod 600 ~/.ssh/*"
    echo "chmod 700 ~/.ssh"


    sudo systemctl restart postgresql
    sudo systemctl restart pgpool2.service

    pm 40 "i"
    pm 41 "i"

    exit
}

createUsersOnPostgreSQL()
{
    pm 33 "i"
    postgreSQLPassword=''
    askPassword 11 postgreSQLPassword
    sudo -u postgres psql postgres -c "SET password_encryption = 'scram-sha-256'"
    sudo -u postgres psql postgres -c "CREATE ROLE pgpool WITH LOGIN;"
    sudo -u postgres psql postgres -c "CREATE ROLE repl WITH REPLICATION LOGIN;"
    sudo -u postgres psql postgres -c "ALTER USER pgpool PASSWORD '${postgreSQLPassword}'"
    sudo -u postgres psql postgres -c "ALTER USER repl PASSWORD '${postgreSQLPassword}'"
    sudo -u postgres psql postgres -c "ALTER USER postgres PASSWORD '${postgreSQLPassword}'"
    sudo -u postgres psql postgres -c "GRANT pg_monitor TO pgpool;"

    pm 11 "a"
    sudo passwd postgres
}

passwords()
{
    pm 38 "i"
    sudo -u root -H sh -c "echo 'SaRPaRDa-CimBom_Java' > ~/.pgpoolkey"
    sudo -u root -H sh -c "sudo chmod 600 ~/.pgpoolkey"
    #pm 48 "a"
    #sudo -u root -H sh -c "pg_enc -m -k /root/.pgpoolkey -u pgpool -p"
    #pm 49 "a"
    #sudo -u root -H sh -c "pg_enc -m -k /root/.pgpoolkey -u postgres -p"
    #sudo -u root -H sh -c "cat /etc/pgpool2/pool_passwd"

    echo 'pgpool      ALL=(ALL) NOPASSWD:ALL' | sudo EDITOR='tee -a' visudo
    echo 'postgres    ALL=(ALL) NOPASSWD:ALL' | sudo EDITOR='tee -a' visudo

    echo " " | sudo tee /var/lib/postgresql/.pgpass
    sudo echo ${firstServerIp}:5432:replication:repl:${postgreSQLPassword} >> /var/lib/postgresql/.pgpass
    sudo echo ${secondServerIp}:5432:replication:repl:${postgreSQLPassword} >> /var/lib/postgresql/.pgpass
    sudo echo ${thirdServerIp}:5432:replication:repl:${postgreSQLPassword} >> /var/lib/postgresql/.pgpass
    sudo echo ${firstServerIp}:5432:postgres:postgres:${postgreSQLPassword} >> /var/lib/postgresql/.pgpass
    sudo echo ${secondServerIp}:5432:postgres:postgres:${postgreSQLPassword} >> /var/lib/postgresql/.pgpass
    sudo echo ${thirdServerIp}:5432:postgres:postgres:${postgreSQLPassword} >> /var/lib/postgresql/.pgpass

    sudo chmod 600  /var/lib/postgresql/.pgpass

    sudo echo "host    all         pgpool           0.0.0.0/0          scram-sha-256" >> /etc/pgpool2/pool_hba.conf
    sudo echo "host    all         postgres         0.0.0.0/0          scram-sha-256" >> /etc/pgpool2/pool_hba.conf
    sudo echo "host    all         all              samenet            scram-sha-256" >> /etc/pgpool2/pool_hba.conf
    sudo echo "host    replication all              samenet            scram-sha-256" >> /etc/pgpool2/pool_hba.conf

    sudo -u root -H sh -c "echo 'localhost:9898:pgpool:pgpool' > ~/.pcppass"
    sudo -u root -H sh -c "chmod 600 ~/.pcppass"

    echo " " | sudo tee /etc/pgpool2/pcp.conf
    sudo echo 'pgpool:'`pg_md5 ${postgreSQLPassword}` >> /etc/pgpool2/pcp.conf
    sudo pg_md5 -m -u postgres ${postgreSQLPassword}
    sudo pg_md5 -m -u pgpool ${postgreSQLPassword}
}

setSSHKeys()
{
    pm 39 "i"
    sed -ir "s|^[#]*\s*PubkeyAuthentication.*|PubkeyAuthentication yes|" /etc/ssh/sshd_config
    sed -ir "s|^[#]*\s*PasswordAuthentication.*|PasswordAuthentication yes|" /etc/ssh/sshd_config

    sudo -u root -H sh -c "mkdir -p ~/.ssh"
    sudo -u postgres -H sh -c "mkdir -p ~/.ssh"
    sudo -u root -H sh -c "ssh-keygen -t rsa -f ~/.ssh/id_rsa_pgpool"
    sudo -u postgres -H sh -c "ssh-keygen -t rsa -f ~/.ssh/id_rsa_pgpool"
    #sudo -u root -H sh -c "ssh-copy-id -i ~/.ssh/id_rsa_pgpool.pub postgres@${firstServerIp}"
    #sudo -u root -H sh -c "ssh-copy-id -i ~/.ssh/id_rsa_pgpool.pub postgres@${secondServerIp}"
    #sudo -u root -H sh -c "ssh-copy-id -i ~/.ssh/id_rsa_pgpool.pub postgres@${thirdServerIp}"

    sudo -u root -H sh -c "chmod 600 ~/.ssh/*"
    sudo -u root -H sh -c "chmod 700 ~/.ssh"
    sudo -u postgres -H sh -c "chmod 600 ~/.ssh/*"
    sudo -u postgres -H sh -c "chmod 700 ~/.ssh"
}

installPgPoolRecovery()
{
    pm 34 "i"
    sudo mkdir pgpool2_source
    cd pgpool2_source
    wget http://www.pgpool.net/download.php?f=pgpool-II-4.1.1.tar.gz
    tar xvzf download.php\?f\=pgpool-II-4.1.1.tar.gz
    cd pgpool-II-4.1.1/src/sql/pgpool-recovery/
    make
    make install
    cd ../../../../
    sudo -u postgres psql template1 -c "CREATE EXTENSION pgpool_recovery"
}

checkToolkits()
{
    pm 45 "i"
    if ! [[ -x "$(command -v ssh)" ]]; then
        sudo apt-get install -y ssh
    fi

    if ! [[ -x "$(command -v arping)" ]]; then
        sudo sudo apt-get install -y iputils-arping
    fi

    if ! [[ -x "$(command -v make)" ]]; then
        sudo sudo apt-get install -y make
    fi

    if ! [[ -x "$(command -v gcc)" ]]; then
        sudo sudo apt-get install -y gcc
    fi

    sudo apt install -y firewalld
}

#$1 == 1 copy files to true location
externalFiles()
{
    pm 37 "i"
    local isAllFileExists=1
    for file in "${extFiles[@]}"; do
        if [[ -f ${file} ]]
        then
            sed -ir "s|^[#]*\s*PGHOME=.*|PGHOME=${postgreSqlBinDir}|" ${file}
            sed -ir "s|^[#]*\s*ARCHIVEDIR=.*|ARCHIVEDIR=${postgreSqlArchiveDir}|" ${file}
        else
            pm 26 "d" ${file}
            isAllFileExists=0
        fi
    done

    if [[ ${isAllFileExists} == 0 ]]; then
        exit
    fi

    if [ $1 == 1 ]
    then
        yes | cp ${extFiles[0]} ${postgreSqlDataDir}/pgpool_remote_start
        yes | cp ${extFiles[1]} ${postgreSqlDataDir}/recovery_1st_stage
        yes | cp ${extFiles[2]} /etc/pgpool2/follow_master.sh
        yes | cp ${extFiles[3]} /etc/pgpool2/failover.sh
    fi
}

#$1==1 Echo Parameter List
#$1==2 Set Parameters
pgPoolConfigParams()
{
    pm 36 "i"
	if [[ $inputServerParameters == 0 ]]
	then
		setServerInformation
	fi

	if [[ $inputPgPoolParameters == 0 ]]
	then	
    	declare -A pgPoolConfigParams
    	pgPoolConfigParams[listen_addresses]="'*'"
    	pgPoolConfigParams[sr_check_user]="'pgpool'"
    	pgPoolConfigParams[sr_check_password]="''"
    	pgPoolConfigParams[health_check_period]=5
    	pgPoolConfigParams[health_check_timeout]=30
    	pgPoolConfigParams[health_check_user]="'pgpool'"
    	pgPoolConfigParams[health_check_password]="''"
    	pgPoolConfigParams[health_check_max_retries]=3

    	pgPoolConfigParams[backend_port0]=5432
    	pgPoolConfigParams[backend_weight0]=1
    	pgPoolConfigParams[backend_data_directory0]="'$postgreSqlDataDir'"
    	pgPoolConfigParams[backend_flag0]="'ALLOW_TO_FAILOVER'"

    	pgPoolConfigParams[backend_port1]=5432
    	pgPoolConfigParams[backend_weight1]=1
    	pgPoolConfigParams[backend_data_directory1]="'$postgreSqlDataDir'"
    	pgPoolConfigParams[backend_flag1]="'ALLOW_TO_FAILOVER'"

    	pgPoolConfigParams[backend_port2]=5432
    	pgPoolConfigParams[backend_weight2]=1
    	pgPoolConfigParams[backend_data_directory2]="'$postgreSqlDataDir'"
    	pgPoolConfigParams[backend_flag2]="'ALLOW_TO_FAILOVER'"

    	pgPoolConfigParams[failover_command]="'/etc/pgpool2/failover.sh% d% h% p% D% m% H% M% P% r% R% N% S'"
    	pgPoolConfigParams[follow_master_command]="'/etc/pgpool2/follow_master.sh %d %h %p %D %m %H %M %P %r %R'"

    	pgPoolConfigParams[use_watchdog]=on
    	pgPoolConfigParams[other_pgpool_port0]=9999
    	pgPoolConfigParams[other_wd_port0]=9000
    	pgPoolConfigParams[other_pgpool_port1]=9999
    	pgPoolConfigParams[other_wd_port1]=9000
    	pgPoolConfigParams[heartbeat_destination_port0]=9694
    	pgPoolConfigParams[heartbeat_device0]="''"
    	pgPoolConfigParams[heartbeat_destination_port1]=9694
    	pgPoolConfigParams[heartbeat_device1]="''"
    	pgPoolConfigParams[delegate_IP]="'$watchDogVirtualIp'"
    	pgPoolConfigParams[if_cmd_path]="'/sbin'"
    	pgPoolConfigParams[arping_path]="'/usr/bin'"
        pgPoolConfigParams[enable_pool_hba]=on
        pgPoolConfigParams[recovery_user]="'postgres'"
        pgPoolConfigParams[recovery_password]="''"
        pgPoolConfigParams[recovery_1st_stage_command]="'recovery_1st_stage'"
        pgPoolConfigParams[backend_hostname0]="'${firstServerIp}'"
        pgPoolConfigParams[backend_hostname1]="'${secondServerIp}'"
        pgPoolConfigParams[backend_hostname2]="'${thirdServerIp}'"
        pgPoolConfigParams[backend_application_name0]="'${firstServerIp}'"
        pgPoolConfigParams[backend_application_name1]="'${secondServerIp}'"
        pgPoolConfigParams[backend_application_name2]="'${thirdServerIp}'"
        pgPoolConfigParams[wd_port]=9000

        if [[ ${thisServerNode} == 1 ]]
        then
            pgPoolConfigParams[wd_hostname]="'${firstServerIp}'"
            pgPoolConfigParams[other_pgpool_hostname0]="'${secondServerIp}'"
            pgPoolConfigParams[other_pgpool_hostname1]="'${thirdServerIp}'"
            pgPoolConfigParams[heartbeat_destination0]="'${secondServerIp}'"
            pgPoolConfigParams[heartbeat_destination1]="'${thirdServerIp}'"
            pgPoolConfigParams[if_up_cmd]="'/usr/bin/sudo /sbin/ip addr add \$_IP_$/24 dev ${firstServerEth} label ${firstServerEth}:0'"
            pgPoolConfigParams[if_down_cmd]="'/usr/bin/sudo /sbin/ip addr del \$_IP_$/24 dev ${firstServerEth}'"
            pgPoolConfigParams[arping_cmd]="'/usr/bin/sudo /usr/bin/arping -U \$_IP_$ -w 1 -I ${firstServerEth}'"
        fi

        if [[ ${thisServerNode} == 2 ]]
        then
            pgPoolConfigParams[wd_hostname]="'${secondServerIp}'"
            pgPoolConfigParams[other_pgpool_hostname0]="'${firstServerIp}'"
            pgPoolConfigParams[other_pgpool_hostname1]="'${thirdServerIp}'"
            pgPoolConfigParams[heartbeat_destination0]="'${firstServerIp}'"
            pgPoolConfigParams[heartbeat_destination1]="'${thirdServerIp}'"
            pgPoolConfigParams[if_up_cmd]="'/usr/bin/sudo /sbin/ip addr add \$_IP_$/24 dev ${secondServerEth} label ${secondServerEth}:0'"
            pgPoolConfigParams[if_down_cmd]="'/usr/bin/sudo /sbin/ip addr del \$_IP_$/24 dev ${secondServerEth}'"
            pgPoolConfigParams[arping_cmd]="'/usr/bin/sudo /usr/bin/arping -U \$_IP_$ -w 1 -I ${secondServerEth}'"
        fi

        if [[ ${thisServerNode} == 3 ]]
        then
            pgPoolConfigParams[wd_hostname]="'${thirdServerIp}'"
            pgPoolConfigParams[other_pgpool_hostname0]="'${firstServerIp}'"
            pgPoolConfigParams[other_pgpool_hostname1]="'${secondServerIp}'"
            pgPoolConfigParams[heartbeat_destination0]="'${firstServerIp}'"
            pgPoolConfigParams[heartbeat_destination1]="'${secondServerIp}'"
            pgPoolConfigParams[if_up_cmd]="'/usr/bin/sudo /sbin/ip addr add \$_IP_$/24 dev ${thirdServerEth} label ${thirdServerEth}:0'"
            pgPoolConfigParams[if_down_cmd]="'/usr/bin/sudo /sbin/ip addr del \$_IP_$/24 dev ${thirdServerEth}'"
            pgPoolConfigParams[arping_cmd]="'/usr/bin/sudo /usr/bin/arping -U \$_IP_$ -w 1 -I ${thirdServerEth}'"
        fi

        if [[ $1 == 1  ]]
        then
            printf "\n\n================================== /etc/pgpool2/pgpool.conf ====================\n"
            for key in "${!pgPoolConfigParams[@]}"; do echo "$key = ${pgPoolConfigParams[$key]}"; done
            printf "================================== EO  /etc/pgpool2/pgpool.conf ===================="
        fi

        if [[ $1 == 2  ]]
        then
            sudo mv /etc/pgpool2/pgpool.conf /etc/pgpool2/pgpool.conf.old
            sudo cp /usr/share/doc/pgpool2/examples/pgpool.conf.sample-stream.gz /etc/pgpool2/pgpool.conf.gz
            sudo gunzip /etc/pgpool2/pgpool.conf.gz
            for key in "${!pgPoolConfigParams[@]}"; do
                setPropertyFileValue "${key}" "${pgPoolConfigParams[$key]}" /etc/pgpool2/pgpool.conf
                #sed -ir "s|^[#]*\s*$key =.*|$key = ${postgreSqlConfigParams[$key]}|" /etc/pgpool2/pgpool.conf
            done
        fi

    	inputPgPoolParameters=1
	fi
}

#$1==1 Show Parameters
#$1==2 Set Parameters
postgreSqlConfigParams()
{
    pm 35 "i"
	if [[ $inputPostgreParameters == 0 ]]
	then
    	declare -A postgreSqlConfigParams
    	postgreSqlConfigParams[listen_addresses]="'*'"
    	postgreSqlConfigParams[archive_mode]=on
    	postgreSqlConfigParams[archive_command]="'cp \"%p\" \"/var/lib/postgresql/archivedir/%f\"'"
    	postgreSqlConfigParams[max_wal_senders]=10
    	postgreSqlConfigParams[max_replication_slots]=10
    	postgreSqlConfigParams[wal_level]=replica
    	postgreSqlConfigParams[hot_standby]=on
    	postgreSqlConfigParams[wal_log_hints]=on
	fi

	if [[ $1 == 1  ]]
	then
		printf "\n\n================================== /etc/postgresql/postgresql.conf ====================\n"
		for key in "${!postgreSqlConfigParams[@]}"; do echo "$key = ${postgreSqlConfigParams[$key]}"; done
		printf "================================== EO  /etc/postgresql/postgresql.conf  ===================="
	fi

	if [[ $1 == 2  ]]
	then
		for key in "${!postgreSqlConfigParams[@]}"; do
		    setPropertyFileValue "${key}" "${postgreSqlConfigParams[$key]}" ${postgreSqlConfigFile}
		    #sed -ir "s|^[#]*\s*$key =.*|$key = ${postgreSqlConfigParams[$key]}|" ${postgreSqlConfigFile}
		done
	fi

	inputPostgreParameters=1
}

postgreSqlAuthenticationConfig()
{
    echo "# PgPool 2 Connection" | sudo tee -a ${postgreSqlDataDir}/pg_hba.conf
    echo "host    all             all             0.0.0.0/0            md5" | sudo tee -a ${postgreSqlHbaFile}
    echo "host    all             all             samenet              scram-sha-256" | sudo tee -a ${postgreSqlHbaFile}
    echo "host    replication     all             samenet              scram-sha-256" | sudo tee -a ${postgreSqlHbaFile}
}

checkPgPool2()
{
    pm 32 "i"
    if ! [ -x "$(command -v pgpool)" ]; then
        pm 21 "i" $pgPool2Version
        installPgPool2=1
    else
        installPgPool2=0
    fi
}

checkPostgreSQL()
{
    pm 31 "i"
    if ! [[ -x "$(command -v psql)" ]]; then
        pm 14 "i"
        installPostgreSql=1
    else
        installPostgreSql=0
    fi
}

#$1==1 Show Locations
updatePostgreSqlLocations()
{
    pm 43 "i"
    postgreSqlBinDir=$(sudo find / -name pg_ctl | egrep '.*sql/[0-9]{1,2}\/bin\/pg_ctl$' | sed 's/\/bin\/pg_ctl//')
    postgreSqlDataDir=$(pg_lsclusters -h | cut -d " " -f 6)
    postgreSqlVersion=$(sudo -u postgres psql postgres -t -c "SHOW server_version"  | egrep -o '[0-9]{2,}' | head -1)
    postgreSqlConfigFile=$(sudo -u postgres psql postgres -t -c "SHOW config_file")
    postgreSqlHbaFile=$(sudo -u postgres psql postgres -t -c "SHOW hba_file")

    if [ $1 == 1 ]
    then
        pm 19 "i" ${postgreSqlVersion}
        pm 20 "i" ${postgreSqlDataDir}
        pm 23 "i" ${postgreSqlConfigFile}
        pm 24 "i" ${postgreSqlHbaFile}
        pm 27 "i" ${postgreSqlArchiveDir}
        if [[ ${postgreSqlVersion} -lt ${lastPostgreSqlVersion} ]]
        then
           pm 17 "w" ${postgreSqlVersion}
        fi
    fi
}

checkPostgreSqlRepository()
{
    if ! grep -q "$pgPoolRepo" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
        sudo add-apt-repository "$pgPoolRepo"
        wget --quiet -O - ${pgPoolRepoKey} | sudo apt-key add -
        pm 10 "i"
        sudo apt update
    fi
}

setServerInformation()
{
    ifconfig -a

    while :
    do
        pm 44 "i"
        inputServerParameters=0

        pm 0 "a" "[$activeServerIp]"
        read firstServerIp
        firstServerIp=${firstServerIp:-$activeServerIp}
        pm 1 "a" "[$readHostName]"
        read firstServerHostName
        firstServerHostName=${firstServerHostName:-$readHostName}
        pm 2 "a" "[ens160]"
        read firstServerEth
        firstServerEth=${firstServerEth:-"ens160"}

        pm 3 "a" "[$activeServerIp]"
        read secondServerIp
        secondServerIp=${secondServerIp:-$activeServerIp}
        pm 4 "a" "[$readHostName]"
        read secondServerHostName
        secondServerHostName=${secondServerHostName:-$readHostName}
        pm 5 "a" "[ens160]"
        read secondServerEth
        secondServerEth=${secondServerEth:-"ens160"}

        pm 6 "a" "[$activeServerIp]"
        read thirdServerIp
        thirdServerIp=${thirdServerIp:-$activeServerIp}
        pm 7 "a" "[$readHostName]"
        read thirdServerHostName
        thirdServerHostName=${thirdServerHostName:-$readHostName}
        pm 8 "a" "[ens160]"
        read thirdServerEth
        thirdServerEth=${thirdServerEth:-"ens160"}
        pm 9 "a"
        read watchDogVirtualIp

        local findCount=0
        printf "IP Address: ${activeServerIp}\n"
        if [[ "$activeServerIp" == "${firstServerIp}" ]]
        then
            thisServerNode=1
            printf "\e[96m${firstServerIp}   ${firstServerHostName}   ${firstServerEth}\e[39m\e[49m\n"
            findCount=$((findCount+1))
        else
            printf "${firstServerIp}   ${firstServerHostName}   ${firstServerEth}\n"
        fi

        if [[ "$activeServerIp" == "${secondServerIp}" ]]
        then
            thisServerNode=2
            printf "\e[96m${secondServerIp}   ${secondServerHostName}   ${secondServerEth}\e[39m\e[49m\n"
            findCount=$((findCount+1))
        else
            printf "${secondServerIp}   ${secondServerHostName}   ${secondServerEth}\n"
        fi

        if [[ "$activeServerIp" == "$thirdServerIp" ]]
        then
            thisServerNode=3
            printf "\e[96m${thirdServerIp}   ${thirdServerHostName}   ${thirdServerEth}\e[39m\e[49m\n"
            findCount=$((findCount+1))
        else
            printf "${thirdServerIp}   ${thirdServerHostName}   ${thirdServerEth}\n"
        fi

        echo "Count:  $findCount"
        if [[ "$findCount" == 1 ]]
        then
            break;
        else
            pm 50 "w"
        fi
    done
    inputServerParameters=1
}

enablePortsOnFirewall()
{
    sudo firewall-cmd --permanent --zone=public --add-service=postgresql
    sudo firewall-cmd --permanent --zone=public --add-port=9999/tcp --add-port=9898/tcp --add-port=9000/tcp  --add-port=9694/udp
    sudo firewall-cmd --reload
}

#1 key
#2 value
#3 file name
setPropertyFileValue()
{
    if ! grep -R "^[#]*\s*${1} =.*" ${3} > /dev/null; then
        echo "${1} = ${2}" >> ${3}
    else
        sed -ir "s|^[#]*\s*${1} =.*|${1} = ${2}|" ${3}
    fi
}

#$1 msg index
#$2 Message Type: (i)nfo, (w)arning, (d)anger, (a)sk
#$3 Message arguments
#Example:
#pm 0 "i"
#pm 17 "d" "14"
#pm x "w" '"A" "B"'
pm()
{
    case $2 in
        ["i"] | ["info"])
            local color="\e[96m"
            ;;
        ["w"] | ["warning"])
            local color="\e[93m"
            ;;
        ["d"] | ["danger"])
            local color="\e[41m"
            ;;
        ["a"] | ["ask"])
        	local color="\e[34m"
        	;;
        *)
            local color="\e[39m"
            ;;
    esac

    printf "$color""${msg[$1]}\e[39m\e[49m\n" $3
}

#$1 Message index
#$2 Password Variable
#Example:
#postgreSQLPassword=''
#askPassword 11 postgreSQLPassword
askPassword()
{
    while :
    do
        read -sp "${msg[$1]}"$'\n' pwd
        read -sp "${msg[12]}"$'\n' pwd2
        if [[ "$pwd" == "$pwd2" ]]; then
            eval $2="$pwd"
            break;
        else
           pm 13 "w"
        fi
    done
}

setLanguage()
{
    setLanguageTR
    printf "\e[34mScriptin Kullanacağı Dili Seçiniz / Select Language\n0: Türkçe\n1:English\n\e[39m"
    read  lang

	case $lang in
		0)
		    printf "Tr"
			setLanguageTR
			;;
		1)
		    printf "En"
			setLanguageEn
			;;
	esac
}

setLanguageTR()
{
    msg[0]="1nci PgPool Serverin IP Adrresini Giriniz %s"
    msg[1]="1nci PgPool Serverin Makine Adını Giriniz %s"
    msg[2]="1nci PgPool Serverin Ethernet Kart Tanımını Giriniz %s"
    msg[3]="2nci PgPool Serverin IP Adrresini Giriniz %s"
    msg[4]="2nci PgPool Serverin Makine Adını Giriniz %s"
    msg[5]="2nci PgPool Serverin Ethernet Kart Tanımını Giriniz %s"
    msg[6]="3ncü PgPool Serverin IP Adrresini Giriniz %s"
    msg[7]="3ncü PgPool Serverin Makine Adını Giriniz %s"
    msg[8]="3ncü PgPool Serverin Ethernet Kart Tanımını Giriniz %s"
    msg[9]="WatchDog için Sanal Ip Adresini Giriniz %s"
    msg[10]="PgPool2 İçin Repo Eklendi"
    msg[11]="Lütfen postgres Kullanıcısı için Şifre Giriniz"
    msg[12]="Lütfen Şifreyi Tekrar Giriniz"
    msg[13]="Girdiğiniz Şifreler Eşleşmedi, Lütfen Tekrar Deneyiniz."
    msg[14]="PostgreSql Server 12 Kurulacak..."
    msg[15]="PostgreSql Serverin Versiyonu Yükseltilecek"
    msg[16]="Onaylıyor musunuz? (e/h)"
    msg[17]="PostgreSql Versiyonunuz %s. En Yeni Sürüm Olan $lastPostgreSqlVersion Sürümüne Yükseltmeniz Önerilir."
    msg[18]="PostgreSql Server Sürümünüz Diğer Serverlerde de Aynı Olmalıdır."
    msg[19]="PostgreSql Versiyonu: %s"
    msg[20]="PostgreSql Data Klasörü: %s"
    msg[21]="PgPool 2 Kurulacak. Version: %s"
    msg[22]="Yapmak İstediğiniz İşlemi Seçiniz:\n0- Server Durumunu Kontrol Et\n1- PostgreSql Parametrelerini Göster\n2- PgPool 2 Parametrelerini Göster\n3- PgPool 2 ile Load Balanceri Kur\n4- Kurulmuş Sistemi Temizle\n5- Scriptten Çık\nSeçiminiz?  "
    msg[23]="PostgreSql Konfigürasyon Dosyası: %s"
    msg[24]="PostgreSql Kimlik Doğrulama Dosyası: %s"
    msg[25]="PostgreSql Kimlik Doğrulama Dosyası: %s"
    msg[26]="%s İsimli Script Bulunamadı. Kurulum Dosyası ile Birlikte Gelen Script Dosyaları Script ile Aynı Klasörde Olmalı."
    msg[27]="PostgreSql Arşiv Klasörü: %s"
    msg[28]="Bütün serverlerde kurulumu yaptıktan sonra aşağıdaki komutları 3 serverde de çalıştırınız."
    msg[29]="PostgreSqL Server kuruluyor"
    msg[30]="PgPool2 Kuruluyor"
    msg[31]="PostgreSQL Kontrolü"
    msg[32]="PgPool 2 Kontrolü"
    msg[33]="PostgreSQL'de Kullanıcılar Oluşturuluyor"
    msg[34]="pgpool_recovery Kuruluyor"
    msg[35]="PostgreSQL Konfigürasyonu İşleniyor"
    msg[36]="PgPool Konfigürasyonu İşleniyor"
    msg[37]="Script Harici Doslyalar İşleniyor"
    msg[38]="Şifreler ve Erişim Yetkileri Düzenleniyor"
    msg[39]="SSH Keyler İşleniyor"
    msg[40]="PostgreSQL ve PgPool Yeniden Başlatıldı. İlk Çalıştırılan Server Master Olacak."
    msg[41]="Kurulum İşlemler Tamamlandı"
    msg[42]="postgres Kullanıcısı İçin Şifre Tanımlayınız"
    msg[43]="PostgreSQL Lokasyonları Alınıyor."
    msg[44]="3 Server İçin Gerekli Bilgileri Giriniz"
    msg[45]="Yardımcı Programlar Kontrol Ediliyor/Kuruluyor"
    msg[46]="Scriptin Kullanacağı Dili Seçiniz / Select Language\n0: Türkçe\n1:English\n"
    msg[47]="PgPool için Linux Kullanıcısı Oluşturuluyor. "
    msg[48]="pgpool Kullanıcısının Şifresini giriniz."
    msg[49]="postgresql Kullanıcısının Şifresini giriniz."
    msg[50]="Hatalı Bilgi Girdiniz. Lütfen Tanımları Tekrar Giriniz."
}

setLanguageEn()
{
    msg[0]="Enter the IP Address of the 1st PgPool Server %s"
    msg[1]="Enter the Machine Name of the 1st PgPool Server %s"
    msg[2]="Enter the Ethernet Card Description of the 1st PgPool Server %s"
    msg[3]="Enter the IP Address of the 2nd PgPool Server %s"
    msg[4]="Enter the Machine Name of the 2nd PgPool Server %s"
    msg[5]="Enter Ethernet Card Definition of 2nd PgPool Server %s"
    msg[6]="Enter the IP Address of the 3rd PgPool Server %s"
    msg[7]="Enter the Machine Name of the 3rd PgPool Server %s"
    msg[8]="Enter Ethernet Card Definition of 3rd PgPool Server %s"
    msg[9]="Enter the Virtual IP Address for WatchDog %s"
    msg[10]="Repo is  Added For PgPool2"
    msg[11]="Please enter password for postgres user"
    msg[12]="Please enter the password again"
    msg[13]="The passwords you entered did not match, please try again."
    msg[14]="PostgreSql Server 12 will be installed ..."
    msg[15]="PostgreSql Server Version Will Be Upgraded"
    msg[16]="Do you confirm ? (y/n)"
    msg[17]="Your PostgreSql Version %s It is Recommended to Upgrade to the Latest Version, ${lastPostgreSqlVersion}"
    msg[18]="Your PostgreSql Server Version Should Be The Same With Other Servers"
    msg[19]="PostgreSql Version: %s"
    msg[20]="PostgreSql Data Folder: %s"
    msg[21]="PgPool 2 will be installed. Version: %s"
    msg[22]="Select the Operation You Want to Do\n0- Check Server Status\n1- Show PostgreSql Parameters\n2- Show PgPool 2 Parameters\n3- Install Load Balancer with PgPool 2\n4- Clear Installation\n5- Exit Script\nSelection?"
    msg[23]="PostgreSql Configuration File: %s"
    msg[24]="PostgreSql Authentication File: %s"
    msg[25]="PostgreSql Authentication File: %s"
    msg[26]="Script with Name …  Not Found. Script Files Included with the Installation File Should Be in the Same Folder as the Script"
    msg[27]="PostgreSql Archive Folder: %s"
    msg[28]="After installing on all servers, run the following commands on all 3 servers."
    msg[29]="PostgreSqL Server is Installing"
    msg[30]="PgPool2 is Installing"
    msg[31]="PostgreSQL Control"
    msg[32]="PgPool2 Control"
    msg[33]="Creating Users in PostgreSQL"
    msg[34]="Installing pgpool_recovery"
    msg[35]="PostgreSQL Configuration is Processing"
    msg[36]="PgPool Configuration is Processing"
    msg[37]="Script External Files is Processing "
    msg[38]="Editing Passwords and Access Authorization"
    msg[39]="SSH Keys are Processing"
    msg[40]="PostgreSQL and PgPool is Restarted. Server That is the First Run Will Be The Master "
    msg[41]="Installation Process is Completed"
    msg[42]="Define Password For Postgres User"
    msg[43]="Getting PostgreSQL Locations"
    msg[44]="Enter the Required Information for the 3 Servers"
    msg[45]="Utilities is Checking / Installing "
    msg[46]="Select Language"
    msg[47]="Creating Linux User For PgPool"
    msg[48]="Enter pgpool user password"
    msg[49]="Enter postgrsql user password"
}

showBanner()
{
    printf "__          __           _                                 _____                  _                            _____           _   \n"
    printf " \ \        / /          | |                               |  __ \                | |                          / ____|         | | \n"
    printf "  \ \  /\  / /    ___    | |        ___   __   __   ___    | |__) |   ___    ___  | |_    __ _   _ __    ___  | (___     __ _  | | \n"
    printf "   \ \/  \/ /    / _ \   | |       / _ \  \ \ / /  / _ \   |  ___/   / _ \  / __| | __|  / _  | |  __|  / _ \  \___ \   / _  | | | \n"
    printf "    \  /\  /    |  __/   | |____  | (_) |  \ V /  |  __/   | |      | (_) | \__ \ | |_  | (_| | | |    |  __/  ____) | | (_| | | | \n"
    printf "     \/  \/      \___|   |______|  \___/    \_/    \___|   |_|       \___/  |___/  \__|  \__, | |_|     \___| |_____/   \__, | |_| \n"
    printf "                                                                                          __/ |                            | |     \n"
    printf "                                                                                         |___/                             |_|     \n"
}
main


