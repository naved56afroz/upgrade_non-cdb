#!/bin/bash
#set -x
##############################################################################################################################################
#  Description : Scripts to troubleshoot performance of the database.
#
#  SCRIPT NAME : upgrade_tool_non_cdb_v1.sh
#  Version : 1.0
#  Scripted By : Naved Afroz  email : naved.afroz@oracle.com
#  Phase : Beta Version
#  Other files used in the script :
#
#  flags used : Explicit_Call
#
#
#
#  USAGE : sh upgrade_tool_non_cdb_v1.sh DB_NAME
#  Date  : 21/02/2022
#
#  features  :
#                       v1.1 : precheck from 11g and 12c
#                       v1.2 : Additional checks 
#                       v1.3 : Purge recyclebin and stats collection
#                       v1.4 : 
#                       v1.5 :
#                       v1.6 :
#                       v1.7 :
#                       v1.8 :
#                       v1.9 :
#                       v1.10 :
#                       v1.11 :
#                       v1.12 :
#                       v1.12 :
#                       v1.13 :
#
############################################################################################################################################

send_mail ()
{
cd $LOG_DIR/$dt
sub1=$(echo " ""$db_name"" impact_analysis Log ($db_name) | ")
sub2=$(echo "$varhost" " | ")
sub=$(echo "$sub1" "$sub2" "$dt")
MAIL_RECIPIENTS=naved.afroz@aig.com
CC_List=naved.afroz@aig.com
mailx -s "$sub" -a ACS_UPGRADE_IMPACT_ANALYSIS*.html $MAIL_RECIPIENTS -c $CC_List < $1
}

set_env ()
{
# Local .env
cd /home/oracle
    # Load Environment Variables
    echo $ORACLE_SID
	sid=`echo $ORACLE_SID|tr [a-z] [A-Z]`
if [ "$db_name" ==  "$sid" ]
then
   echo $sid
else
    echo "No $db_name.env file found" 1>&2
    return 1
fi
}

logfile_check ()
{
#Logfile used by preheck
logname=$LOG_DIR/$dt/prechecks_$1.log

if [ -f "$logname" ]
          then
            mv "$logname" "$LOG_DIR"/"$dt"/prechecks"${1}"_"${ts}".log
fi
}

stats_backup_collect ()
{
nohup sqlplus "/ as sysdba" @$SCRIPTS_DIR/stats_backup_collect.sql $1 $2 > $LOG_DIR/stats_backup_collect.sql.err 2>&1 &
echo "Monitor the log $LOG_DIR/stats_backup_collect.sql.err"
}

purge_dba_recyclebin ()
{

nohup sqlplus "/ as sysdba" @$SCRIPTS_DIR/purge_dba_recyclebin.sql $1 $2 > $LOG_DIR/purge_dba_recyclebin.sql.err 2>&1 &
echo "Monitor the log $LOG_DIR/purge_dba_recyclebin.sql.err " 

}

create_grp ()

{
echo "***********************************************************************"
echo        "Creating GRP in $db_name"
echo "***********************************************************************"
sqlplus -S "/ as sysdba" <<EOF
set timing on
set trimspool on
spool $LOG_DIR/create_grp$dt.log
set line 400
col time for a50
col name for a50
select name,time  from v\$restore_point;
select NAME,SCN,TIME,DATABASE_INCARNATION#,GUARANTEE_FLASHBACK_DATABASE,STORAGE_SIZE from v\$restore_point;

CREATE RESTORE POINT BEFORE_PRECHECK_$dt GUARANTEE FLASHBACK DATABASE; 

select name,time  from v\$restore_point;
select NAME,SCN,TIME,DATABASE_INCARNATION#,GUARANTEE_FLASHBACK_DATABASE,STORAGE_SIZE from v\$restore_point;
 
Spool off
EOF
}

preupgrade_fixups ()
{
echo "***********************************************************************"
echo        "Initiating preupgrade fixups in $db_name"
echo "***********************************************************************"
sqlplus -S "/ as sysdba" <<EOF
set timing on
set trimspool on
spool $LOG_DIR/preupgrade_fixups_$dt.log
prompt ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
prompt                 Preupgrade Fixups 
prompt ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
@$LOG_DIR/preupgrade_$dt/preupgrade_fixups.sql
Spool off
EOF
}


upgrade ()
{

echo "               validate the command and press y/Y to kick off upgrade "
echo "***********************************************************************"
echo "\$ORACLE_HOME;echo \$ORACLE_SID;date"
echo ""
echo $ORACLE_HOME;echo $ORACLE_SID;date
echo ""
echo "$oracle_home_19c/bin/dbupgrade -n 4 -l $LOG_DIR/upgrade_$dt >> $LOG_DIR/upgrade_$dt/$db_name_nohup_$dt.out"
echo ""
ls -lrt $oracle_home_19c/bin/dbupgrade
echo "***********************************************************************"
read opt_upg
if [ "$opt_upg" ==  "y" ] || [ "$opt_upg" ==  "Y" ]
then
	#stop DB from old home
	shutdown
	#start DB from 19c home
	. /home/oracle/$dbname\_19c.env
	echo $ORACLE_HOME;echo $ORACLE_SID;date;$PATH

	startup 
	echo $ORACLE_HOME;echo $ORACLE_SID;date;$PATH

	nohup $oracle_home_19c/bin/dbupgrade -n 4 -l $LOG_DIR/upgrade_$dt >> $LOG_DIR/upgrade_$dt/$db_name\_nohup_$dt.out &
	echo "upgrade has been triggered monitor the log for upgrade process $LOG_DIR/upgrade_$dt/$db_name _nohup_$dt.out" 
	tail -100f $LOG_DIR/upgrade_$dt/$db_name\_nohup_$dt.out

else
    echo "Review and fix issues and then trigger upgrade" 
    return 1
fi

}

shutdown ()
{
echo $ORACLE_HOME;echo $ORACLE_SID;date
sqlplus -S "/ as sysdba" <<EOF
set timing on
set trimspool on
spool $LOG_DIR/$dt/shutdown_$db_name.txt
prompt ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
prompt                    $db_name: $oracle_home_old
prompt ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
prompt ###########################################################
prompt Initiating shutdown from old home 
prompt ###########################################################
select name,flashback_on from v\$database;
shutdown immediate ;
Spool off
EOF
}

startup ()
{
#. /home/oracle/$dbname\_19c.env
#echo $ORACLE_HOME;echo $ORACLE_SID;date;$PATH
#dbname_19c=$ORACLE_SID\_19c
sqlplus -S "/ as sysdba" <<EOF
set timing on
set trimspool on
spool $LOG_DIR/$dt/startup_19c_$db_name.txt
prompt ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
prompt                    $db_name: $oracle_home_19c
prompt ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
prompt ###########################################################
prompt startup from 19c home
prompt ###########################################################
startup upgrade pfile='$LOG_DIR/init$dbname\_19c.ora' ;
select name,flashback_on from v\$database ;
Spool off
EOF
}

sql_execution_db ()
{
sqlplus -S "/ as sysdba" <<EOF
set timing on
set trimspool on
spool $LOG_DIR/$dt/$db_name.txt
prompt ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
prompt                    $db_name
prompt ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
prompt ###########################################################
prompt Take backup of prameter file - Backup source DB spfile
prompt ###########################################################
create pfile='$LOG_DIR/$dt/init$db_name_bkp_$dt$ts.ora' from spfile;
@$SCRIPTS_DIR/$1 $2 $3 $4
Spool off
EOF
}


health_check ()
{
echo "***********************************************************************"
echo $db_name
echo "***********************************************************************"
sqlplus -S "/ as sysdba" <<EOF
set timing on
set trimspool on
set escchar $
spool $LOG_DIR/$dt/hcheck_$db_name.txt
set escchar OFF
prompt ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
prompt                    $db_name
prompt ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
@$SCRIPTS_DIR/$1
Spool off
EOF
}

impact_analysis ()
{
cd $LOG_DIR/$dt
echo "***********************************************************************"
echo $db_name
echo "***********************************************************************"
sqlplus -S "/ as sysdba" <<EOF
set timing on
set trimspool on
prompt ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
prompt                    impact_analysis_report
prompt ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
@$SCRIPTS_DIR/$1
Spool off
EOF
send_mail $logname
}

db_upgrade_diagnostics ()
{
cd $LOG_DIR/$dt
sqlplus -S "/ as sysdba" <<EOF
set timing on
set trimspool on
prompt ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
prompt                    impact_analysis_report
prompt ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

@$SCRIPTS_DIR/$1 $2 $3
EOF

}

db_preupgrade_diagnostics ()
{


#cat /etc/oratab |grep 19
echo "***********************************************************************"
echo "		Below  19C home will be used for preupgrade analysis"
echo "***********************************************************************"
echo $oracle_home_19c
echo " ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~  "
echo "                     Initiating preupgrade.jar          "
echo "  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ "

#$ORACLE_HOME/jdk/bin/java -jar $ORACLE_HOME19C/rdbms/admin/preupgrade.jar -c "$db_name" FILE TEXT DIR $LOG_DIR_PREUPGRADE
$ORACLE_HOME/jdk/bin/java -jar $oracle_home_19c/rdbms/admin/preupgrade.jar -c "$db_name" FILE TEXT DIR $LOG_DIR_PREUPGRADE
}

Precheck_1_2_Weeks_Prior()
{
logfile_check "$db_name"
set_env
{
echo "***********************************************************************"
echo "Database  running on server"
echo "***********************************************************************"
ps -ef|grep pmon


echo "***********************************************************************"
echo "CPU Count"
echo "***********************************************************************"
lscpu

echo "***********************************************************************"
echo "Available Memory"
echo "***********************************************************************"
free -g


echo "***********************************************************************"
echo "patch invenotory from source"
echo "***********************************************************************"
$ORACLE_HOME/OPatch/opatch lspatches

echo "***********************************************************************"
echo "lsnrctl status LISTENER"
echo "***********************************************************************"
ps -ef|grep tns
tnsping $db_name
listener_name=`ps -ef|grep tns |grep -i bagd |awk '{print $9}'|head -1`
lsnrctl status $listener_name

echo "***********************************************************************"
echo "Check timezone version in target 19c home"
echo "***********************************************************************"
ls -lrt $oracle_home_19c/oracore/zoneinfo/*32*

} >> "$logname"

#sql_execution_db db_query.sql "$dbname" "$oracle_base" "$LOG_DIR"


                     echo "***********************************************************************"
                     echo $db_name
                     echo "***********************************************************************"
					 #db_name=$db_name
					 sql_execution_db db_query.sql "$dbname" "$oracle_base_19c"  "$LOG_DIR"					
                                         health_check hcheck.sql
					 impact_analysis ACS_19cUpgrade_Data_collect.sql
                                         db_upgrade_diagnostics dbupgdiag.sql "$LOG_DIR/$dt" "$db_name"
					 db_preupgrade_diagnostics "$db_name" "$LOG_DIR_PREUPGRADE"



show_main_menu
}



directory_exists ()
{


         if [ -d "/u02/shared/app/oracle_acs" ]
            then
                                SCRIPTS_DIR=/u02/shared/app/oracle_acs/scripts/acs_upgrade_tool
								
                               # mkdir -p /u02/shared/app/oracle_acs/upg_tool_logs/"$db_name"_"$dt"
								
                                UPG_TOOL_LOGS=/u02/shared/app/oracle_acs/upg_tool_logs/"$db_name"_"$dt"


                                LOG_DIR=/u02/shared/app/oracle_acs/upgrade19c/upgrade_logs/"$db_name"
                                
								mkdir -p "$LOG_DIR"/"$dt"

                                if [ ! -d "$LOG_DIR"/preupgrade_"$dt" ]
                                        then
                                                mkdir -p "$LOG_DIR"/preupgrade_"$dt"
                                                LOG_DIR_PREUPGRADE="$LOG_DIR"/preupgrade_"$dt"
                                else
                                                LOG_DIR_PREUPGRADE="$LOG_DIR"/preupgrade_"$dt"
                                fi

                                if [ ! -d "$LOG_DIR"/upgrade_"$dt" ]
                                        then
                                                mkdir -p "$LOG_DIR"/upgrade_"$dt"
                                                LOG_DIR_UPGRADE="$LOG_DIR"/upgrade_"$dt"
                                        else
                                                LOG_DIR_UPGRADE="$LOG_DIR"/upgrade_"$dt"
                                fi

                                if [ ! -d /u02/shared/app/oracle_acs/upg_tool_logs/"$db_name"_"$dt" ]
                                        then
                                                mkdir -p /u02/shared/app/oracle_acs/upg_tool_logs/"$db_name"_"$dt"
                                                UPG_TOOL_LOGS=/u02/shared/app/oracle_acs/upg_tool_logs/"$db_name"_"$dt"

                                fi

                                                cd "$UPG_TOOL_LOGS" || exit
                                                cd "$LOG_DIR_UPGRADE" || exit
                                                cd "$LOG_DIR_PREUPGRADE" || exit
                                                 cd "$LOG_DIR" || exit

                        else
                         echo "${bred} cannot detect u02 directory check oracle_acs location exist in u02  ${normal}"
         fi

}


################################## MAIN MENU Function ######################################################
show_main_menu()
{
    NORMAL=$(echo "\033[m")
    MENU=$(echo "\033[36m") #Blue
    NUMBER=$(echo "\033[33m") #yellow
    FGRED=$(echo "\033[41m")
    RED_TEXT=$(echo "\033[31m")
    ENTER_LINE=$(echo "\033[33m")
        #user=`ps -ef|grep  pmon|grep -v +ASM|awk '{print $1}'|head -1`
        user=$(ps -ef|grep  pmon_|grep -v grep|awk '{print $1}'|head -1)
echo -e "${MENU}                                                            ${bgred}[UPGT]${NORMAL}                        ${NORMAL}"
echo -e "${MENU}                                                  ${bgred}DATABASE UPGRADE TOOL${NORMAL}                   ${NORMAL}"
echo ""
echo -e "${MENU}********************************************************************* MENU *******************************************${NORMAL}"
echo -e "${MENU}**${NUMBER} 1)${MENU} Precheck for 11g to 19c 1 week prior         ${NORMAL}"
echo -e "${MENU}**${NUMBER} 2)${MENU} Precheck for 12c to 19c 1 week prior         ${NORMAL}"
echo -e "${MENU}**${NUMBER} 3)${MENU} Precheck  1 day prior         ${NORMAL}"
echo -e "${MENU}**${NUMBER} 4)${MENU} Upgrade from 11g/12c to 19c      ${NORMAL}"
echo -e "${MENU}**${NUMBER} 5)${MENU} Post upgrade checks     ${NORMAL}"
echo -e "${MENU}**${NUMBER} 0)${MENU} EXIT ${NORMAL}"
echo -e "${MENU}**********************************************************************************************************************${NORMAL}"
echo -e "${ENTER_LINE}Please select an upgrade method ..enter a menu option and enter OR  ${RED_TEXT} just Press enter to exit. ${NORMAL}"
read -r opt
        main_menu_options
}
function option_picked() {
    COLOR='\033[01;31m' # bold red
    RESET='\033[00;00m' # normal white
    MESSAGE=${*:-"${RESET}Error: No message passed"}
    echo -e "${COLOR}${MESSAGE}${RESET}"
}


################################## Menu MENU Option ######################################################
main_menu_options ()
        {
                if [[ $opt = "" ]]; then
                         exit;
                else
                        case $opt in
                                1) clear;
                                        option_picked "Option 1 Picked  --> Precheck for 11g to 19c 1 week prior ";
                                        echo ""
                                        Explicit_Call=$opt
					Precheck_1_2_Weeks_Prior					                                        
#show_main_menu
                                        ;;
                                2) clear;
                                        option_picked "Option 2 Picked  --> Precheck for 12c to 19c 1 week prior ";
                                        echo ""
                                        Explicit_Call=$opt
					Precheck_1_2_Weeks_Prior                                        
#show_main_menu
                                        ;;
                                3) clear;
                                        option_picked "Option 3 Picked  -->  Precheck  1 day prior ";
                                        echo ""
                                        Explicit_Call=$opt
					#Precheck_1_day_Prior
                                        show_sub_menu
                                        ;;
				4) clear;
                                        option_picked "Option 4 Picked  --> Upgrade from 11g/12c to 19c ";
                                        echo ""
                                        Explicit_Call=$opt
                                        upgrade
					show_main_menu
                                        ;;
				5) clear;
                                       option_picked "Option 5 Picked  --> Post upgrade checks";
                                        echo ""
                                        Explicit_Call=$opt
                                        show_main_menu
                                        ;;

                                0) exit ;;
                                '\n') exit;
                                        ;;
                                *) clear;
                                        option_picked "Pick an option from the menu";
                                        show_main_menu;
                                        ;;
                        esac
                fi
}

################################## SUB MENU Function ######################################################
show_sub_menu()
{
    NORMAL=$(echo "\033[m")
    MENU=$(echo "\033[36m") #Blue
    NUMBER=$(echo "\033[33m") #yellow
    FGRED=$(echo "\033[41m")
    RED_TEXT=$(echo "\033[31m")
    ENTER_LINE=$(echo "\033[33m")
        #user=`ps -ef|grep  pmon|grep -v +ASM|awk '{print $1}'|head -1`
        user=$(ps -ef|grep  pmon_|grep -v grep|grep -v +ASM |awk '{print $1}'|head -1)
echo -e "${MENU}                                                             ${bgred}[UPGT]${NORMAL}                        ${NORMAL}"
echo -e "${MENU}                                                     ${bgred}DATABASE UPGRADE TOOL${NORMAL}                   ${NORMAL}"
echo -e "${MENU}                                                   ${bgred}PRE UPGRADE TASKS N-1 DAY${NORMAL}                   ${NORMAL}"
echo ""
echo -e "${MENU}********************************************************************* MENU *******************************************${NORMAL}"
echo -e "${MENU}**${NUMBER} 1)${MENU} Purge Recycle BIN          ${NORMAL}"
echo -e "${MENU}**${NUMBER} 2)${MENU} Collect Dictionary and Fixed object stats          ${NORMAL}"
echo -e "${MENU}**${NUMBER} 3)${MENU} Turn Flashback on        ${NORMAL}"
echo -e "${MENU}**${NUMBER} 4)${MENU} Create Garunteed Restore Point          ${NORMAL}"
echo -e "${MENU}**${NUMBER} 5)${MENU} Run Preupgrade Fixups     ${NORMAL}"
echo -e "${MENU}**${NUMBER} 0)${MENU} EXIT ${NORMAL}"
echo -e "${MENU}**********************************************************************************************************************${NORMAL}"
echo -e "${ENTER_LINE}Please select an upgrade method ..enter a menu option and enter OR  ${RED_TEXT} just Press enter to exit. ${NORMAL}"
echo -e "${ENTER_LINE}  ${RED_TEXT} select 0 and enter to jump to main menu. ${NORMAL}"

read -r opt
        sub_menu_options
}
function option_picked() {
    COLOR='\033[01;31m' # bold red
    RESET='\033[00;00m' # normal white
    MESSAGE=${*:-"${RESET}Error: No message passed"}
    echo -e "${COLOR}${MESSAGE}${RESET}"
}

################################## SUB MENU Option ######################################################
sub_menu_options ()
        {
                if [[ $opt = "" ]]; then
                         exit;
                else
                        case $opt in
                                1) clear;
                                        option_picked "Option 1 Picked  --> Purge Recycle BIN   ";
                                       echo ""
                                        #Explicit_Call=1
                                        purge_dba_recyclebin $LOG_DIR $dt
					show_sub_menu
                                        ;;
                                2) clear;
                                        option_picked "Option 2 Picked  --> Collect Dictionary and Fixed object stats   ";
                                        echo ""
                                        #Explicit_Call=1
                                        stats_backup_collect $LOG_DIR $dt
					show_sub_menu
                                        ;;
                                3) clear;
                                        option_picked "Option 3 Picked  --> Turn Flashback on   ";
                                        echo ""
                                        #Explicit_Call=1
                                        echo "Create manually"
					show_sub_menu
                                        ;;
                                4) clear;
                                        option_picked "Option 2 Picked  --> Create Garunteed Restore Point ";
                                        echo ""
                                        #Explicit_Call=1
                                        create_grp  $LOG_DIR $dt 
                                        show_sub_menu
				       ;;
                                5) clear;
                                        option_picked "Option 3 Picked  --> Run Preupgrade Fixups ";
                                        echo ""
                                        #Explicit_Call=1
					preupgrade_fixups                                        
					show_sub_menu                                        
					;;

                                0) clear;
                                        option_picked "Pick an option from the menu";
                                        show_main_menu;
                                        ;;
                                '\n') exit;
                                        ;;
                                *) clear;
                                        option_picked "Pick an option from the menu";
                                        show_sub_menu;
                                        ;;
                        esac
                fi
}

##############################################  MAIN #######################################################################
        normal=$(echo "\033[m")
        blue=$(echo "\033[36m") #Blue
        yellow=$(echo "\033[33m") #yellow
        white=$(echo "\033[00;00m") # normal white
        bred=$(echo "\033[01;31m") # bold red
        lyellow=$(echo "\e[103m") #background light yellow
        black=$(echo "\e[30m") #black
        byellow=$(echo "\e[43m") #background yellow \e[1m
        bnb=$(echo "\e[1m") # bold and bright
        blink=$(echo "\e[5m") # \e[42m
        blink=$(echo "\e[42m") #bgreen
        bdgray=$(echo "\e[100m") # background dark gray
        bgred=$(echo "\e[41m") # background red


                #Flag menu breakup function call
                Explicit_Call=0
                #input database name
                db_name=$1
                user=`ps -ef|grep  pmon_|grep $db_name|awk '{print $1}'|head -1`
                dbname="${db_name,,}"
		oracle_home_19c=`cat /etc/oratab|grep $dbname|grep 19|cut -f2 -d: -s`
		oracle_base_19c=`cat /etc/oratab|grep $dbname|grep 19|cut -f2 -d: -s|sed 's/product.*//'`
		oracle_home_old=`echo $ORACLE_HOME`
		#Today's Date
                dt=$(/bin/date +%d%m%Y)
                ts=$(/bin/date +%H%M%S)
                varhost=$(hostname|cut -d"." -f1)
                #Checking If script Directory Exists
                directory_exists
        clear
                echo -e "${bred} Logged in as $user and running the upgrade assist tool ${normal}"
        show_main_menu
#********************************************END****************************************************************#



