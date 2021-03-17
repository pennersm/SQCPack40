#!/bin/bash
###########################################################################
# NOKIA AUTOMATION FOR CLOUD CONTROLLER
#--------------------------------------------------------------------------
Script_defname="$0"
Script_version="v-13AUG15"
#
# (C) Nokia 2014 
#
###########################################################################
# Initialization:
	DATETAG="$(date +%m%d%Y_%H%M)" ; MYPID=$$
	UNARCDIR="/tmp/SQC"
	SQC_PROPSARC="${UNARCDIR}/Properties-SQC"
	NQA_PROPSARC="${UNARCDIR}/Properties-NQA"
	MBB_PROPSARC="${UNARCDIR}/Properties-KPI"
	SQC_REPSETS="${UNARCDIR}/repsets.cf"
#
# global part - dont touch unless you know what you do
. $HOME/.bashrc
: ${RUNSECURE:="YES"}
: ${SQC_USER:="$(whoami)"}
: ${SQC_HOME:="${HOME}"}
: ${SQC_ROOT:="${HOME}/CCCTRL"}
: ${RSCMD:="/var/opt/nokia/oss/global/shared/rscmd"}
: ${CONTENT:="/var/opt/nokia/oss/global/shared/rscmd/content3"}
: ${CONFIG:="/var/opt/nokia/oss/global/shared/rscmd/configurations"}
: ${SQC_CONF:="${SQC_ROOT}/nsncc.cf"}
: ${SQC_LOGF:="${SQC_ROOT}/nsncc.log"}
: ${SQC_CUSTOM:="${SQC_ROOT}/nsncc_cust.cf"}
#
: ${RSRUN:="${RSCMD}/bin/rscmd-sqc.sh"}
#
: ${WPERFD:="${SQC_ROOT}/watch_perf"}
: ${RUN3GNQA:="YES"}
: ${RUN2GNQA:="NO"}
: ${COLECTFM:="NO"} 
: ${COLDAYFM:="7"}
#
: ${SQC_MBBCOL:="YES"}
: ${MBB_PROPERTIES:="${CONFIG}/MBB_PBM-v1.properties"}
: ${MBB_PBMSCHEDULE:='00 06 * * *'}
: ${MBBDAYS:="7"} 
: ${MBB_PROPTEMPLATE:="${MBB_PROPSARC}/MBB_PBM-TEMPLATE-v1.properties"}
#
# cleanup directories and timings (in days)
# Mind that $HOME/.bashrc can overwrite retention time if you add the variables locally
: ${PREP_TO_DEL:=12}
: ${DEL_AFTER:=20}
: ${KPI_NQA:="${RSCMD}/export/KPI_NQA"}
: ${KPI_SQC:="${RSCMD}/export/KPI_SQC"}
: ${KPI_benchmark:="${RSCMD}/export/KPI_benchmark"}
: ${DATADUMP_CLEANLOGS:="YES"}
: ${DATADUMP_MAXLOGAGE:="7"}
#
: ${SQC_FMANA:="${RSCMD}/export/SQC_FMANA"} 
: ${KEEPALARMS:=31}
: ${DELALARMS:=45} 

: ${OSSVERSION:="OSS5X"}   # OSS5X xor NA15
: ${CLEANUARC:="YES"} 

: ${OLD_CRONTAB:="${SQC_ROOT}/crontab.previous.sav"}
: ${DBUSER:='pmr'}
: ${DBPASS:="$(polpasmx -${DBUSER})"}
	# syscredacc.sh  -user pmr -type db

	get_db_ip () {
		OSSV=$1; unset PEERS
		case ${OSSV} in
			"OSS5X")
				PEERS="$(host $(/opt/nokia/oss/bin/ldapacmx.pl -sgPkgHost db)|cut -d' ' -f 4)"
			;;
			"NA15")
				PEERS="$(netstat -tnp 2>/dev/null|awk '{print $5}'|grep -m 1 ':1521'|cut -d':' -f 1)"
				if [ -z "${PEERS}" ]; then 
					sqlplus ${DBUSER}/${DBPASS} &>/dev/null &
					sleep 2
					PEERS="$(netstat -tnp 2>/dev/null|awk '{print $5}'|grep -m 1 ':1521'|cut -d':' -f 1)"
				fi;
			;;
		esac
		echo "${PEERS}" 
		}
	: ${DBIP:="$(get_db_ip ${OSSVERSION})"}; export -p DBIP;
	: ${VERBLOG:="NO"}; ERR="NO"

#------------------------------------------------------------------------------	
#
GRPS=( $(id -G $(whoami)) ); IS_SYSOP='NO'
for CCGRP in "${GRPS[@]}" ; do [ "${CCGRP}" = "201" ] && IS_SYSOP='YES'; done
export -p IS_SYSOP
#	
#------------------------------------------------------------------------------
#
sqc_logit () {
	MYCALL=$1
        MYHOST=${GENHOST}
        MYTIME=`date  "+%b %e %H:%M:%S"`
        MYLOG=${SQC_LOGF} ; 

        echo "${MYTIME} ${MYHOST} ${MYCALL}  $2" |tee -a ${MYLOG}

}
#------------------------------------------------------------------------------
sqc_debug_break () {
        sqc_cont () { : ; } ;
        echo "#break $1 ---------------- enter \"sqc_cont\" to resume ------------------"
        unset line
        DBP="#-DEBUG-#"
        while [ "$line" != "sqc_cont" ]
        do
                echo -n $DBP
                read line
                eval $line
        done
}
#-----------------------------------------------------------------------------
####################---------------------------------------##################
#-----------------------------------------------------------------------------
sqc_getcro () {

	CHKLIN="$( echo $*|cut -d'#' -f1)"

	rc=1; CROCNT=0; unset CROLIN
	CROACL="/etc/cron.allow"
	CROALW="$(cat ${CROACL} 2>/dev/null|grep ${SQC_USER} &>/dev/null)$?"
	CROUSE="$( crontab -l &>/dev/null )$?";
	sqc_logit getcro "status check : (crouse=\"${CROUSE}\") (croalw=\"${CROALW}\")"

	if [ "${CROALW}" = "0" ] && [ "${CROUSE}" = "0" ] ; then

		CROCNT="$( crontab -l 2>/dev/null|grep -Fce "${CHKLIN}" )" 
		sqc_logit getcro "line \"${CHKLIN}\" matches \"${CROCNT}\" times in crontab"

		if [ "${CROCNT}" = "0" ] ; then
			rc=0; sqc_logit getcro "line  \"${CHKLIN}\" not found in crontab"
		elif [ "${CROCNT}" = "1" ]; then
			rc=0; sqc_logit getcro "line  \"${CHKLIN}\" match once in crontab"
		else
			rc=2; sqc_logit "ERROR: generic error or multiple matches for line"
		fi

	elif [ "${CROALW}" = "0" ] && [  "${CROUSE}" = "1" ] ; then
		rc=0; sqc_logit getcro "cron allowed but no crontab entries found for \"${SQC_USER}@$(uname -n)\""
	elif [ ! -r ${CROACL} ]; then
                ERROR=$( ls -al ${CROACL} 2>&1 >/dev/null)
                rc=5; sqc_logit "ERROR: There is no ACL file: \"${ERROR}\""
	else
		rc=4; sqc_logit "WARNING: seems you are not allowed to cron \"${SQC_USER}@$(uname -n)\""
	fi

	return $rc
}
##-----------------------------------------------------------------------------
#
sqc_delcro () {
	CROLTD="$*" ; rc=1;
	unset USENTRY; USENTRY="$(sqc_getcro ${CROLTD} &>/dev/null )$?"
       
	#sqc_logit delcro "requested del-entry \"${CROLTD}\""
 
	if [ "${USENTRY}" = "0" ] ; then
		sqc_logit delcro "INFO: can not find the crontab entry you are trying to remove"; rc=0
	elif [[ "${USENTRY}" == [1,2] ]] ; then
		sqc_logit delcro "deleting all matches of crontab entry: \"${CROLTD}\"";
		cat <(grep -v "${CROLTD}" <(crontab -l)) | crontab -        
		rc=0
	else
		sqc_logit delcro "can not match anything to delete, continuing anyway" 
		rc=3
	fi
	return $rc
}	
#
#-----------------------------------------------------------------------------
#
sqc_cleanup() {

	STARTDIR=$(pwd); CLEANDIR="$( echo $* | cut -d' ' -f 3)"
	CLEANPARM=$(sed 's/[\*&]/\\&/g' <<<"$*");
	BACKUPDIR="PREPARED_TO_DELETE" ; ZIPCMD="bzip2 -9"
	
	ACTDIR=$( echo $CLEANPARM |cut -d' ' -f3 )
	KEEPDA=$( echo $CLEANPARM |cut -d' ' -f1 )
	DELEDA=$( echo $CLEANPARM |cut -d' ' -f2 )
	DELPAT=$( echo $CLEANPARM |cut -d' ' -f4 )
	
	if [ -d "${ACTDIR}" ] ; then
		sqc_logit cleanup "cleanup for ${CLEANDIR}: moving after ${KEEPDA} removing after ${DELEDA} days" 
		[ -x "${ACTDIR}"    ] || ( sqc_logit "ERROR: can not access directory for cleanup \"${ACTDIR}\"" ; export ERR="YES" )
		cd ${ACTDIR}; BACKPATH="${ACTDIR}/${BACKUPDIR}"
		[ -x "${BACKPATH}" ] || ( mkdir ${BACKPATH} ; sqc_logit cleanup "had to create directory \"${BACKPATH}\"" )
		[ "$( chmod u+w ${BACKPATH} )$?" ] || ( sqc_logit "ERROR: can not write into directory \"${BACKUPDIR}\""; export ERR="YES" )
	
		find ${ACTDIR}/ -maxdepth 1 -mtime +${KEEPDA} -exec mv {} ${BACKPATH}/ 2>/dev/null \;
		${ZIPCMD} ${BACKPATH}/* 2>/dev/null
		find ${BACKPATH}/ -maxdepth 1 -mtime +${DELEDA} -exec rm -f {} 2>/dev/null \;
		cd ${STARTDIR}
	fi
}
#
#-----------------------------------------------------------------------------
#
sqc_addcro () {

	ORGCMD=$*; # sqc_logit addcro "store ${ORGCMD}"
	RAWTIM="$(echo "$*" |cut -d' ' -f1-5)"
	NEWCMD=$(sed 's/[\*&]/\\&/g' <<<"$*")
	SCHTIM=$(echo ${NEWCMD}|cut -d' ' -f1-5)
	RUNCMD=$(echo ${NEWCMD}|cut -d' ' -f6-)

	if [ "$(echo ${NEWCMD}|cut -d' ' -f1-5|tr -d '* [0-9]\\')" = "" ]; then
		[ "${VERBLOG}" = "YES" ] && sqc_logit addcro "requested cron entry \"${RUNCMD}\" at \"${RAWTIM}\""
	else
		sqc_logit addcro "wrong function invocation sqc_addcro \"$*\" exiting";exit 2
	fi

        USENTRY="$( sqc_getcro "${RUNCMD}" &>/dev/null )$?"; rc=1
		CRONTST="$(crontab -l &>/dev/null)$?"
#	sqc_logit addcro "function getcro return (usentry=\"${USENTRY}\") (crontst=\"${CRONTST}\")"
        if [ "${USENTRY}" = "0" ] && [ "${CRONTST}" = "0" ] ; then
		cat <(crontab -l) <(echo "${ORGCMD}")|crontab -
#                sqc_logit addcro "added new crontab entry for \"${SQC_USER}@$(uname -n)\""
	elif [ "${USENTRY}" = "1" ]  ; then
#		crontab -l | sed "s/.*%$RUNCMD%.*/$NEWCMD"/ | crontab -
		cat <(grep -v "${RUNCMD}" <(crontab -l)) <(echo "${ORGCMD}") | crontab -
#		sqc_logit addcro "replaced crontab for \"${SQC_USER}@$(uname -n)\""
	elif [ "${USENTRY}" = "0" ] && [ "${CRONTST}" = "1" ] ; then
		echo "${ORGCMD}"|crontab -
		sqc_logit addcro "started new crontab and added 1 entry for \"${SQC_USER}@$(uname -n)\""
        else
		sqc_logit addcro "no crontab entry added - check for cf format or same command already scheduled more than once"
        fi
	unset USENTRY;
}
#
#-----------------------------------------------------------------------------
#
sqc_colfm() {

	FMTMPDIR="/tmp"
	TMPPREFX="SQC_FMANA_"
	
	# FOLLOWING MANAGED OBJECT CLASSES SUPORTED:
	MOCNBR[0]="3" ; 	MOCNAM[0]="BSC"
	MOCNBR[1]="811"; 	MOCNAM[1]="RNC"
	MOCNBR[2]="107"; 	MOCNAM[2]="MSS"
	MOCNBR[3]="757"; 	MOCNAM[3]="MGW"
	MOCNBR[4]="463"; 	MOCNAM[4]="SGSN"
	let NMOC=${#MOCNBR[@]}-1

	# in OSS5X you must always obtain a list of all NE in a MOC each named by CO_NAME
	# unfortunately it is allowed to have blanks in CO_NAME like for e.g. 'BSC 0' which
	# requires some long-winded stuff about IFS and storing back and forth the array ...
	sqc_dbnelist() {

		_CO_OC_ID=$1; export -p _CO_OC_ID
		OLD_IFS=$IFS; IFS=','; export IFS
		NELIST=( $(sqlplus -s pmr/$(polpasmx -pmr) <<-EOSQL
                set head off
                set pages 0
                set feed off
                set wrap off
                set colsep ,
                select CO_INT_ID,CO_NAME from UTP_COMMON_OBJECTS where CO_OC_ID=${_CO_OC_ID}
                ;
                exit
        EOSQL
		) )
		unset CLEANLIST; IFS=' '
		let i=0; while [ ! -z "${NELIST[$i]}" ]; do
				CLEANLIST=( "${CLEANLIST[@]}" "$(echo ${NELIST[$i]}|tr -d [:blank:] |tr '\n' ' ')" )
				let i=$i+1
		done
		echo ${CLEANLIST[@]}
		IFS=$OLD_IFS
	}
	# ... only after that - sorry - really stupid shit is solved you can actually start  
	#--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --
	
	mkdir -p ${SQC_FMANA}
	rm -f ${FMTMPDIR}/${TMPPREFX}* 

	if [ "${OSSVERSION}" = "OSS5X" ]; then
	sqc_logit fmcol "FM collection type \"${OSSVERSION}\" defined for \"$(echo ${MOCNAM[@]})\" and last \"${COLDAYFM}\" days"
	for MOC in "${MOCNBR[@]}"
	do
		MOCLIST=( $(sqc_dbnelist ${MOC}) )
		let NUMMOCS=${#MOCLIST[@]}-1
		for j in $( seq 0 2 ${NUMMOCS} ) ; do
			let i=$j+1
			# echo " MOC intId ${MOCLIST[j]} Mocname ${MOCLIST[i]}"
			FMSPOOL="/tmp/SQC_FMANA_${MOC}_${MOCLIST[i]}_$$.tmp"
			sqlplus -s pmr/${DBPASS} <<-EOFMQ > /dev/null
			WHENEVER SQLERROR EXIT SQL.SQLCODE
				set headsep off
				set pagesize 0
				set feedback off
				set wrap off
				set trims on
				set trimspool on
				set linesize 3200
				spool ${FMSPOOL}
				select ('${MOCLIST[$i]}')||','||trim(DN)||','||trim(CONSEC_NBR)||','||trim(ALARM_NUMBER)||','||trim(ALARM_TYPE)|| ','||trim(ALARM_STATUS)||','||trim(SEVERITY)||','||trim(TEXT)||','||trim(to_char(ALARM_TIME, 'dd/mm/yyyy-hh24:mi:ss'))||','||trim(to_char(CANCEL_TIME, 'dd/mm/yyyy-hh24:mi:ss')) from FX_ALARM where NE_SITE_ID=${MOCLIST[$j]} and ALARM_TIME <= (sysdate-${COLDAYFM});
				spool off
				exit
			EOFMQ
			[ "$?" = "0" ] || sqc_logit "WARNING: sql failure in FM collection MO-intId \"${MOCLIST[j]}\" MO-name \"${MOCLIST[i]}\""
		done
	sync
	done
	#--  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --  --
	elif [ "${OSSVERSION}" = "NA15" ] ; then 
		sqc_logit fmcol "FM collection enabled but not implemented on NA15"
	else
		sqc_logit fmcol "FM collection not implemented for unknown OSS version \"${OSSVERSION}\""
	fi
	#==  ==  ==  ==  ==  ==  ==  ==  ==  ==  ==  ==  ==  ==  ==  ==  ==  ==  ==  ==
	sync && sleep 1
	#==  ==  ==  ==  ==  ==  ==  ==  ==  ==  ==  ==  ==  ==  ==  ==  ==  ==  ==  ==
	for i in $( seq 0 ${NMOC} ); do
		FMRESFIL=( $(find ${FMTMPDIR} -name "${TMPPREFX}${MOCNBR[$i]}_*.tmp" -size +0 2>/dev/null) )
		let NNES=${#FMRESFIL[@]}
		ROUNDFILE="${SQC_FMANA}/SQCFMANA_${CUSTOMER}${CLUSTER}_${MOCNAM[$i]}_${DATETAG}.csv"
		for FMNEFIL in "${FMRESFIL[@]}"; do 
			cat ${FMNEFIL} >> ${ROUNDFILE}
		done
		NALARMS="$(cat ${ROUNDFILE} 2>/dev/null|wc -l)"
		if [ "${NALARMS}" != "0" ] ; then  
			sqc_logit fmcol "found \"${NALARMS}\" Alarms from \"${NNES}\" NEs type \"${MOCNAM[$i]}\" and stored in \"${ROUNDFILE}\"" 
		else
			sqc_logit fmcol "no alarms found for NEs type \"${MOCNAM[$i]}\" - nothing stored" 
		fi
	done
}
#
#-----------------------------------------------------------------------------
#
sqc_zipnqa () {

	SCANDIR=$1; MYDIR=$(pwd); cd ${SCANDIR}
	sqc_logit zipnqa "proton ID set to \"${OPSTRG}\" for archive at \"${SCANDIR}\""
	XLSSUF=( $(find ${SCANDIR} -type f -name '*.xls') )
	CSVSUF=( $(find ${SCANDIR} -type f -name '*.csv') )
	OPERATOR="RS#${OPSTRG}#"      
 
	for XLS in ${XLSSUF[*]} ; do 
		FNAME=${XLS%.xls} 
                for CSV in ${CSVSUF[*]}; do
                CNAME=${CSV%.csv}
                if [ "${CNAME}" = "${FNAME}" ]; then 
                       ARC=$(basename ${CNAME}); DIR=$(dirname ${CNAME})
                       sqc_logit zipnqa "found pair ${CNAME}"
                       ZIPD="$(zip -j ${CNAME}.zip ${CNAME}.csv ${FNAME}.xls >/dev/null)$?" && sync
                       if [ "${ZIPD}" = "0" ] ;  then 
                              rm -f ${CSV}; rm -f ${XLS}
                              if [ ! "${ARC:0:3}" = "RS#" ] && [ ! -z "${OPSTRG}" ] ; then 
                                     mv ${CNAME}.zip ${DIR}/${OPERATOR}${ARC}.zip
                              fi
                      else 
					          sqc_logit zipnqa "ERROR: found pairing ${CNAME} but could not zip it"
							  export -p ERR="YES"
					  fi
                fi       
                done
         done
     cd ${MYDIR}
}
#
#-----------------------------------------------------------------------------
#
sqc_checkjobs() {
	MYJOBS=( $(crontab -l |grep ${RSRUN}|cut -d' ' -f7) )
	sqc_logit checkjob "found \"${#MYJOBS[@]}\" RS jobs in cron to be first layer tested"
	if [ "${#MYJOBS[@]}" != "0" ] ; then
		[ -x "${CONTENT}" ] || sqc_logit "ERROR: can not descend into content dir \"${CONTENT}\""
		
		unset CHXML ERR; NERR="NO"; let NMJOBS=${#MYJOBS[@]}-1; let i=0
		for i in $(seq 0 ${NMJOBS}); do
			if [ "$(ls ${MYJOBS[$i]} &>/dev/null)$?" = "0" ] ; then 
				JOBXMLS=( $(cat ${MYJOBS[$i]} |grep ".report="|grep ".xml$"|cut -d'=' -f2) )
				for JXML in "${JOBXMLS}" ; do 
					FILE="${CONTENT}/${JXML}"
					if [ "$(ls ${FILE} &>/dev/null)$?" = "0" ] ; then
							CHXML=( ${CHXML[@]} ${JXML} )
						else
							sqc_logit "ERROR: XML does not exist \"${JXML}\" for job \"${MYJOBS[$i]}" ; NERR="YES"
						fi
				done
			else
				sqc_logit "ERROR: properties file does not exist for job \"${MYJOBS[$i]}\"" ; NERR="YES"
			fi
		done
		if [ "${NERR}" = "NO" ] ; then 
			sqc_logit checkjob "properties and XML file dependencies complete - 1st layer OK!"
		else
			sqc_logit checkjob "1st layer failure - there are properties and/or XML files missing - NOK!"
		fi
	
		NERR="NO"
		let NCHXML=${#CHXML[@]}-1; UCXML=( $(for i in $(seq 0 ${NCHXML}) ; do echo ${CHXML[$i]}; done|sort -u) ); unset CHXML
		let NUCXML=${#UCXML[@]}-1
		sqc_logit checkjob "found ${#UCXML[@]} files to be second layer tested"
		for CXML in "${UCXML[@]}" ; do 
			MYKPIS=( $(grep "<kpi_ref ref=" ${CONTENT}/${CXML}|cut -d'"' -f2|cut -d'#' -f1) )
			for KPI in "${MYKPIS[@]}" ; do 
				if [ "$(ls ${CONTENT}/${KPI} &>/dev/null)$?" != "0" ] ; then 
					sqc_logit checkjob "ERROR: KPI \"${KPI}\" from \"${CXML}\" not found in content"
					export NERR="YES"
				fi
			done
		done
		if [ "${NERR}" = "NO" ] ; then 
			sqc_logit checkjob "KPIs referenced in all XML templates are found - 2nd layer OK!"
		else
			sqc_logit checkjob "2nd layer failure - at least one XML template requires KPIs/content that is not available - NOK!"
		fi
	fi
}
#
#-----------------------------------------------------------------------------
#
sqc_runjobs() {
	[ -x "${SQC_ROOT}" ] || sqc_logit "ERROR: can not cd into \"${SQC_ROOT}\""
	CHECKSCRIPT="${SQC_ROOT}/check.sh" ; CHECKLOG="${SQC_ROOT}/check.log"

	MYJOBS=( $(crontab -l |grep "${RSRUN}\|rscmd.sh" |cut -d' ' -f7) )
	sqc_logit checkjob "found \"${#MYJOBS[@]}\" RS jobs in cron to be tested with \"${RSRUN}\""
	[ -x "${RSRUN}" ] || sqc_logit "ERROR: can not execute \"${RSRUN}\""
	
	rm ${CHECKSCRIPT} ${CHECKLOG} &> /dev/null;  
	for JOB in "${MYJOBS[@]}"; do
		echo ${RSRUN} ${JOB} >> ${SQC_ROOT}/check.sh
	done

	chmod +x ${CHECKSCRIPT}; cat ${CHECKSCRIPT} 

	printf "\n\n\t $(tput bold)EXECUTE ${SQC_ROOT}/check.sh now ...? $(tput sgr0)"
	printf "\n\t [n|N] to abort or any key to run test"
	tput civis; read DUMMY; tput cnorm 
	
	[[ "${DUMMY}" == [n,N] ]] || ${CHECKSCRIPT} |tee -a ${CHECKLOG} & 
	return $?
}
#
#-----------------------------------------------------------------------------
#
usage() {
	bold=$(tput bold)
	normal=$(tput sgr0)
	printf '\033[?7l'
	printf "\n ${bold}NAME${normal}\n"
	printf "\t ${Script_defname} - Automated Data Collection Handling for e.g. Nokia NetENG Cloud Controller\n"
	printf "\n ${bold}SYNOPSIS${normal}\n"
	printf "\t ${Script_defname} [--fmonly] [--showarchive] [--nopersist] [--noextract] [--runjobs]\n\n"
	printf "\n ${bold}DESCRIPTION\n"
	printf "\t ${Script_defname}${normal} is a self-extracting tar archive with builtin bash code to be executed as soon as the\n"
	printf "\t tarball is unpacked.\n"
	printf "\t In current use of this bash code, the tarball itself contains mostly rscmd properties files and XML\n"
	printf "\t templates for NetAct PM data collection. After unpacking into a hardcoded directory the XML templates\n"
	printf "\t are copied into the expected place in the NetAct Reporting Suite / NPM directory structure and rscmd\n"
	printf "\t properties files from the archive will be scheduled as cron jobs to create corresponding reports.\n"
	printf "\t Besides this main task a set of other activities like FM data collection or cleanup of old data can be\n"
	printf "\t performed. Refer to options description in this help\n\n"
	printf "\t ${bold}--datadump${normal}\n"
	printf "\t Do not schedule any cron jobs but execute all other activities besides pure FM data collection.\n"
	printf "\t Use this option to create report files if you can not use cron.\n"
	printf "\t ${bold}--fmonly${normal}\n"
	printf "\t Do not schedule any cron jobs or execute any other activity besides pure FM data collection\n"
	printf "\t ${bold}--showarchive${normal}\n"
	printf "\t Show content of the embedded tarball. You also find the files unpacked last time the script was ran in a logfile\n"
	printf "\t under $CCCTRL/unarched.log. If you want the script to keep the archive after execution instead of deleting it then\n"
	printf "\t export the environment variable CLEANUARC=NO in your $HOME/.bashrc\n"
	printf "\t ${bold}--nopersist${normal}\n"
	printf "\t Normally ${Script_defname} would schedule in cron and execute daily to ensure housekeeping. This option\n"
	printf "\t prevents it and only runs the script once (i.e. unpacks the tarball and schedules everything else but ${bold}not${normal}\n"
	printf "\t including itself as ${Script_defname}. This option might be useful in some situations but is generally not encouraged\n"
	printf "\t ${bold}--noextract${normal}\n"
	printf "\t Do not unpack the tarball but instead use an existing directory that has the files unpacked from a\n"
	printf "\t previous run of the script. If this directory does not exists in the expected location the script exits\n"
	printf "\t ${bold}--runjobs${normal}\n"
	printf "\t Does ${bold}not{normal} schedule any ${bold}new${normal} jobs but executes all rscmd jobs that are in the ${bold}currently active${normal} crontab.\n"
	printf "\t Mind that this will create new output in the export directories and can mess up data collection if used often\n"
	printf "\t Use this option to test if your cron jobs as configured by the script can actually be executed unattended.\n"
	printf "\t ${bold}--checkjobs${normal}\n"
	printf "\t Does not schedule any new jobs nor run any scheduled jobs but verifies if all referenced files are in place\n"
	printf "\t Includes check down to KPI definition file level\n\n"
	printf "\t The ${bold}difference between${normal} \"--runjobs\" and \"--datadump\" is that latter one executes all jobs defined in the\n"
	printf "\t current repsets.cf as background and even if cron usage is maybe not allowed or possible for this user or host.\n"
	printf "\t In contrast to this behaviour \"--runjobs\" will execute what is currently configured in cron and will not function\n"
	printf "\t at all if e.g. cron usage is not possible\n"
	printf "\n\n"
	printf '\033[?7l'
# next to follow (implement first ;):
#	--repset	_. only show repset for this particular cluster
#	--nocron    -> do all but dont schedule anything in cron -> nice in combination with --runjobs to get things done once
#	--showsched -> re-format crontab schedule display in a way that also non-man-page-readers can understand it
#   --altout -> to different directory (by temporary properties file that will go into same directory)
}
#
#-----------------------------------------------------------------------------
#
sqc_trim () {
	LOGLEN=$1; LOGFILE=$2
	if [ "$(cat ${LOGFILE}|wc -l)" -gt ${LOGLEN} ] ; then
		mv ${LOGFILE} ${LOGFILE}.old
		tail -n ${LOGLEN} ${LOGFILE}.old > ${LOGFILE}
		rm ${LOGFILE}.old
	fi
}
###########################################################################
#  MAIN PROGRAM
###########################################################################
#---------------------------------------------------------------------------------
# 
# 
sqc_init() {
	sqc_logit init "checking for command line options $*"
	RUNCOMPLETE=NO; EXTRACTARCH="YES"; PERSISTANT="YES"
	[ $# = 0 ] && RUNCOMPLETE="YES"
	while [ $# !=  0 ]
	do
        case $1 in
		--datadump)
			RUNCOMPLETE="YES"
			DATADUMP="YES"
			;;
		--fmonly)
			sqc_colfm
			RUNCOMPLETE="NO"
			;;
		--noextract)
			if [ -d "${UNARCDIR}" ] ; then
				RUNCOMPLETE="YES" 
				EXTRACTARCH="NO"
			else
				sqc_logit "ERROR: directory \"${UNARCDIR}\" must have unpacked archive for this option"
				exit 1
			fi
		;;
		--showarchive)
			sed -e '1,/^exit$/d' "$0" | tar -ztvf - 
			exit 0
		;;
		--nopersist)
			PERSISTANT="NO"
			RUNCOMPLETE="YES"
		;;
		--checkjobs)
			sqc_checkjobs
			RUNCOMPLETE="NO"
		;;
		--runjobs)
			sqc_runjobs
			RUNCOMPLETE="NO"
		;;
		*)
			usage
			exit
		;;
	esac ; shift ; done
}
sqc_init $*
[ -f ${SQC_LOGF} ] && ( cat  ${SQC_LOGF} >> ${SQC_LOGF}.old ; cat /dev/null > ${SQC_LOGF} )
PWPROB="NO"
[ "$(which polpasmx &>/dev/null)$?" != 0 ] && ( sqc_logit init "WARNING: can not find polpasmx command!!"; PWPROB="YES" ) 
[ "$(polpasmx -pmr >/dev/null)$?" != "0" ] && ( sqc_logit init "WARNING: can not find polpasmx command!!"; PWPROB="YES")

if [ -z "${CUSTOMER}" ] || [ -z "${CLUSTER}" ]; then
	sqc_logit "ERROR: Customer and Cluster not set in environment. Cannot match local report sets"
	export -p ERR="YES"
elif [ -z "${SQC_ROOT}" ]; then
	sqc_logit "ERROR: Working directory ${SQC_ROOT} non existent."
	export -p ERR="YES"
elif [ "${IS_SYSOP}" != 'YES' ] && [ "${RUNSECURE}" = 'YES' ] ; then
	sqc_logit "ERROR: Secure runmode required but user not member of sysop: \"$(whoami)\""
	export -p ERR="YES"
elif [ "$(crontab -l &> /dev/null)$?" != "0" ] && [ -z "$(crontab -l 2>&1 >/dev/null|grep "^no crontab for $(whoami)$")" ] && [ "${DATADUMP}" != "YES" ]; then
		sqc_logit "ERROR: cron problem \"$(crontab -l 2>&1 >/dev/null|tr '\n' ' ')\""
		export -p ERR="YES"
elif [ "${PWPROB}" = 'YES' ] &&  [ "${RUNSECURE}" = 'YES' ] ; then
	sqc_logit "ERROR: Secure runmode required but DB password for \"${DBUSER}\" can not be found dynamically"
	export -p ERR="YES"
#elif [ "${PWPROB}" = 'YES' ] &&  [ "${RUNSECURE}" = 'NO' ] ; then
# lets think about this later ...
fi
if [ "${RUNCOMPLETE}" = "YES" ] && [ "${ERR}" = 'NO' ] ; then 
# --------------------------------------------------------------------
# ====================================================================
	sqc_logit main "start ${Script_defname} ${Script_version} on \"${CUSTOMER}${CLUSTER}\""
	sqc_logit main "script terminal : \"$(who am i|sed -e"s/[ ]\+/ /g")\""
	sqc_logit main "script checksum : \"$(md5sum $0|awk '{print $1}')\" - compare in makenew.log if needed"
	sqc_logit main "running at: $(hostname) localtime $(date) last$(who -b|sed -e"s/[ ]\+/ /g")"
# ====================================================================
# --------------------------------------------------------------------
# here you find some info about the self-extraction trick :
# http://www.stuartwells.net/slides/selfextract.htm
	if [ "${EXTRACTARCH}" = "YES" ] ; then
		mkdir -p ${UNARCDIR} &&
		[ $? = "0" ] && sqc_logit main "unpacking files into \"$(ls -ld ${UNARCDIR})\"... be patient"
		sed -e '1,/^exit$/d' "$0" | tar -C ${UNARCDIR} -ztvf - > ${SQC_ROOT}/unarched.log
		sed -e '1,/^exit$/d' "$0" | tar -C ${UNARCDIR} -zxvf - > /dev/null
	else
		sqc_logit main "using existing archive \"$(ls -ld ${UNARCDIR})\""
	fi
	sqc_logit main "setting up properties files for cluster \"${CUSTOMER}${CLUSTER}\""
	sqc_logit main "using DBIP \"${DBIP}\" for OSS Version \"${OSSVERSION}\""
	
	sqc_logit main "ensuring DOS/WIN format integrity ... (takes a second ...)"
	DAMDOSFILS=( $(find ${UNARCDIR} -maxdepth 4 -type f) ); NDOSFILS=${#DAMDOSFILS[@]}-1
	for CONVIT in ${DAMDOSFILS[*]} 
	do
		if [ -r "${CONVIT}" ] ; then
			cat ${CONVIT}|tr -d '\015' > DUMMYFIL.tmp &&
			mv DUMMYFIL.tmp ${CONVIT} 
		fi
	done; sync
	[ -r "${SQC_REPSETS}" ] || ( sqc_logit "ERROR: can not find report set definitions \"${SQC_REPSETS}\""; export -p ERR="YES" )
	sqc_logit main "report set definitions from \"$(ls -l ${SQC_REPSETS} 2>/dev/null)\""
	sqc_logit main "repset definitions version : $(grep -m 1 'Script_version' ${SQC_REPSETS}|cut -d'=' -f 2)"
	
	unset TECHNOL TECHVER DUMMY1 DUMMY2 CONTINU REPSET REPORT NEWSET MBBTECH
	let RSIDX=0; let RIDX=0
	while read VAR VAL
	do
		if [[ ${VAR} == *"%START" ]] ;then
			DUMMY1="$( echo ${VAR}|cut -d'%' -f 1 )"
			DUMMY2="$( echo ${DUMMY1}|cut -d '-' -f 2)"
			#-------------------------------------------
			TECHNOL="$( echo ${DUMMY1}|cut -d '-' -f 1)"
			TECHVER="${DUMMY2}"
			REPSET[${RSIDX}]="${TECHNOL} ${TECHVER}" 
			CONTINU=1;NEWSET=1
		elif [[ ${VAR} == *'%STOP' ]] ;then
			REPSET[$RSIDX]="${REPSET[$RSIDX]} ${RIDX}"
			let RSIDX=${RSIDX}+1
			CONTINU=0
		elif [ "${CONTINU}" = "1"  ] && ! [[ ${VAR} == *"[STOP]" ]] && [ "$( echo ${VAR}|cut -d'-' -f 1)" = "${TECHNOL}" ]; then
			REPORT[${RIDX}]="${VAR}" ; SCHEDULE[${RIDX}]="${VAL}"
			if [ "${NEWSET}" = 1 ]; then REPSET[${RSIDX}]="${REPSET[$RSIDX]} ${RIDX}" ; unset NEWSET ; fi
			let RIDX=${RIDX}+1
		fi
	done <${SQC_REPSETS}

	sqc_logit main "matching report sets for local cluster"
	let LREPIDX=0; MYCLUSTER=0
	while read VAR VAL
	do
		MYSTART="@${CUSTOMER}${CLUSTER}:properties"
		MYEND="@${CUSTOMER}${CLUSTER}:endprops"
		if [ "${VAR}" = "${MYSTART}" ] ; then
			MYCLUSTER="1"
			sqc_logit main "Found entry for local cluster \"${MYSTART}\""
		elif [ "${VAR}" = "${MYEND}" ] ; then
			MYCLUSTER="0"
		elif [ "${MYCLUSTER}" = 1 ] ; then 
			DUMMY="$(echo ${VAR}|cut -d' ' -f 1)"
			VALID="$(echo ${DUMMY}|cut -d'_' -f 1)"
			if [ "${VALID}" = 'SQCL1' ]; then 
				LOCREPSET[$LREPIDX]="${DUMMY}"
				let LREPIDX=${LREPIDX}+1
				sqc_logit main "Local Cluster needs report set \"${DUMMY}\""
				#-----------------------------------------------
				if [ "${SQC_MBBCOL}" = "YES" ] ; then
					MBBSYS="$(echo ${DUMMY:6}|cut -d'-' -f1)"
					DUMMY3=( ${MBBTECH[@]} ${MBBSYS} )
					MBBTECH=( $(echo ${DUMMY3[@]}|sort -u) )
				fi
			fi
		fi
	done <${SQC_REPSETS}

#----------------------------------------------------------------------------------------------------
	sqc_logit main "Preparing local config file with report sets"
#---------------------------------------------------------------------------------------------------
	[ -f "${SQC_CONF}" ] && mv ${SQC_CONF} ${SQC_CONF}.old &&
	printf "# NSNCC configuration file auto-generated $(date) as user $(whoami)\n#\n" > ${SQC_CONF}
	printf "# Section : SQC Reports\n#\n" >> ${SQC_CONF}

	let NLOCREPS=${#LOCREPSET[@]}-1
	let NREPSETS=${#REPSET[@]}-1
	unset MISSADAP
	
	for i in $(seq 0 ${NLOCREPS}); do
		for j in $(seq 0 ${NREPSETS}); do
			DUMMY=( $(echo ${REPSET[$j]}) )
			SETNAME=${DUMMY[0]} ;SETVER=${DUMMY[1]}
			let SETSTART=${DUMMY[2]};let SETEND=${DUMMY[3]}-1

			DEFEDSET="${SETNAME}-${SETVER}"

			if [ "${DEFEDSET}" = "${LOCREPSET[$i]}" ]; then
				printf "#\n#REPORT SET ${LOCREPSET[$i]}\n#\n" >> ${SQC_CONF}
				sqc_logit main "adding repset \"${LOCREPSET[$i]}\" to local config file"
				
				for k in $(seq ${SETSTART} ${SETEND}); do
					PROPTMPL="${SQC_PROPSARC}/${SETNAME}-${SETVER}/${REPORT[$k]}.properties"
					if [ -f "${PROPTMPL}" ]; then
						sqc_logit main "... adding job \"${REPORT[$k]}.properties\" from set \"${SETNAME}-${SETVER}\"" 
						echo "sqc_addcro ${SCHEDULE[$k]} ${RSRUN} ${CONFIG}/${REPORT[$k]}.properties" >> ${SQC_CONF}
						cp ${PROPTMPL} ${CONFIG} && sync 
						sed -i s/%DBUSER%/${DBUSER}/g ${CONFIG}/${REPORT[$k]}.properties
						sed -i s/%DBPASS%/${DBPASS}/g ${CONFIG}/${REPORT[$k]}.properties
						sed -i s/%DBIP%/${DBIP}/g  ${CONFIG}/${REPORT[$k]}.properties
						sed -i s/%CUSTOMER%/${CUSTOMER}/g  ${CONFIG}/${REPORT[$k]}.properties
						sed -i s/%CLUSTER%/${CLUSTER}/g  ${CONFIG}/${REPORT[$k]}.properties
						sed -i s/%OPSTRING%/${OPSTRG}/g ${CONFIG}/${REPORT[$k]}.properties
						XMLS=( ${XMLS[*]} $(grep '^jflx.runs.*.xml' ${CONFIG}/${REPORT[$k]}.properties ) )
						ADAP=( ${ADAP[*]} $(grep "report=" ${CONFIG}/${REPORT[$k]}.properties |grep -v "#"|cut -d'=' -f2|cut -d'/' -f1) )
					else
						sqc_logit "ERROR: missing properties file in archive:  \"${REPORT[$k]}.properties\" from set \"${SETNAME}-${SETVER}\""
						ERR="YES"
					fi
				done
				
				let NADAP=${#ADAP[@]}-1; CPADAP=( $(for n in $( seq 0 ${NADAP} ); do echo ${ADAP[$n]}; done|sort -u) )
				let NCPADAP=${#NCPADAP[@]}-1

				for CPADAPF in "${CPADAP[@]}"
				do
					ADDIR=${CONTENT}/${CPADAPF}
					ADARC=${CPADAPF}; META="$(echo ${CPADAPF}|cut -d'_' -f1)"
					SADDIR="${SQC_PROPSARC}/${SETNAME}-${SETVER}"
					SADARC="${SADDIR}/${ADARC}"
					METADA="${SADDIR}/${META}"
					TOUCHD="${CONTENT}/adaptations"
					if [ ! -d "${ADDIR}" ] && [ -d "${SADARC}" ]; then
						unset rc1 rc2
						rc1="$(cp -r ${SADARC} ${CONTENT})$?"
						rc2="$(cp -r ${METADA} ${CONTENT})$?"
						touch ${TOUCHD}/${META}; touch ${TOUCHD}/${CPADAPF}
						if [ "$rc1" = 0 ] && [ "$rc2" = 0 ]; then 
							sqc_logit main "... added adaptation \"${CPADAPF}\" and metadata \"${META}\" from own archive"
						else
							[ "$rc1" = "0" ] || sqc_logit "ERROR: could not install missing adaptation \"${CPADAPF}\""; 
							[ "$rc2" = "0" ] || sqc_logit "ERROR: could not install metadata \"${META}\""; 
							MISSADAP="YES"; ERR="YES"
						fi
					elif [ ! -d  "${ADDIR}" ] && [ ! -d "${SADARC}" ]; then
							sqc_logit "ERROR: missing adaptation \"${CPADAPF}\" from both own and OSS archive !!"
							MISSADAP="YES"; ERR="YES" 
					elif [ -d "${ADDIR}" ]; then
							sqc_logit main "... using existing adaptation \"${CPADAPF}\""
					fi
				done

				let NXMLS=${#XMLS[@]}-1; DUMMY=( $(for n in $( seq 0 ${NXMLS} ); do echo ${XMLS[$n]}; done|sort -u) )
				unset XMLS; XMLS=("${DUMMY[@]}"); let NXMLS=${#XMLS[@]}-1

				for n in $(seq 0 ${NXMLS} ); do
					DUMMY="$(echo ${XMLS[$n]} |cut -d'=' -f 2)"
					TEMPL="$(basename ${DUMMY})"; TPDIR="$(dirname ${DUMMY})"
					CPSRC="${SQC_PROPSARC}/${LOCREPSET[$i]}/${TEMPL}"; CPDST="${RSCMD}/content3/${TPDIR}"
					if [ -f "${CPSRC}" ] && [ -d "${CPDST}" ] ; then 
						cp ${CPSRC} ${CPDST} 2>/dev/null
						sqc_logit main "... adding XML report-template \"${CPDST}/${TEMPL}\""
					elif [ -f "${CPSRC}" ] && [ ! -d "${CPDST}" ] && [ ! "${MISSADAP}" = "YES" ]; then
						[ -d "${CONTENT}/${CPADAPF}" ] && rc="$(mkdir -p ${CPDST} &>/dev/null)$?"
						if [ "${rc}" = "0" ]; then
								cp ${CPSRC} ${CPDST} 
								sqc_logit main "created target directory \"${CPDST}\" - was missing in adaptation \"${CPADAPF}\""
								sqc_logit main "... adding XML report-template \"${CPDST}/${TEMPL}\""
						else
							sqc_logit "ERROR: can not find target for \"${TEMPL}\" in content3 subdirectory structure"
						fi
					elif [ ! -f "${CPSRC}" ] && [ -f "${CPDST}/${TEMPL}" ] ; then 
						sqc_logit "WARNING: required template \"${TEMPL}\" not in nsncc archive - using existing local version"
					elif [ "${MISSADAP}" = "YES" ] ; then
						ERR="YES"
					else
						sqc_logit "ERROR: can not copy \"${TEMPL}\" to \"${CPDST}\"" 
						ERR="YES"
					fi
				done
			fi
			unset XMLS; unset MISSADAP; unset ADAP CPADAP
		done
	done
	
	for CDIR in ${KPI_SQC} ${KPI_NQA} ${KPI_benchmark}
	do
		if [ ! -d "${CDIR}" ]; then
			mkdir -p ${CDIR} && sync
			sqc_logit "WARNING: Had to create result dir \"${CDIR}\""
		fi
	done
	sync
	sqc_logit main "Local config file renewed but not yet completed ..."

#----------------------------------------------------------------------------------------------------
	sqc_logit main "add housekeeping-standards to local config file"
#----------------------------------------------------------------------------------------------------
	crontab -l &> ${OLD_CRONTAB}
	crontab -r &> /dev/null
	cat <<-EOC > ${SQC_ROOT}/crontab.new.tmp
		15 0 * * 6 find /tmp -maxdepth 1 -name "NQA_??????????????.log" -exec rm -f {} \;
		16 0 * * * find /tmp -maxdepth 1 -name "WBTS_capa_RU40_8_?????????????_Jflx.csv" -exec rm -f {} \;
		17 0 * * * find /tmp -maxdepth 1 -name "RSRAN???_?????????????_Jflx.???" -exec rm -f {} \;
		18 0 * * * find /tmp -maxdepth 1 -name "BTSRadioDetail_?????????????_Jflx.???" -exec rm -f {} \;
		19 0 * * * find /tmp -maxdepth 1 -name "SQCL1*.csv" -exec rm -f {} \;
		01 01 * * * echo 'd * '|mail -N
EOC
	if [ "${PERSISTANT}" = "YES" ] ; then 
	cat <<-EOP >> ${SQC_ROOT}/crontab.new.tmp
	0  12 * * * ( source ${SQC_HOME}/.bashrc ; ${SQC_ROOT}/nsncc.sh )
EOP
	fi
	crontab ${SQC_ROOT}/crontab.new.tmp && rm -f ${SQC_ROOT}/crontab.new.tmp
	sqc_logit main "added regular cleaning of /tmp to local config file"
	
	printf "#\n#\n# Section : SQC Housekeeping\n#\n" >> ${SQC_CONF}
	cat <<-EOS >> ${SQC_CONF}
		sqc_cleanup ${PREP_TO_DEL} ${DEL_AFTER} ${KPI_NQA}
		sqc_cleanup ${PREP_TO_DEL} ${DEL_AFTER} ${KPI_SQC}
		sqc_cleanup ${PREP_TO_DEL} ${DEL_AFTER} ${KPI_benchmark}
		sqc_cleanup ${PREP_TO_DEL} ${DEL_AFTER} ${SQC_ROOT}/proton/data
		sqc_cleanup ${PREP_TO_DEL} ${DEL_AFTER} ${SQC_ROOT}/proton/sent
		sqc_cleanup ${PREP_TO_DEL} ${DEL_AFTER} ${SQC_ROOT}/PROTON2/sent
		sqc_cleanup ${PREP_TO_DEL} ${DEL_AFTER} ${SQC_ROOT}/PROTON2/data
		sqc_cleanup ${PREP_TO_DEL} ${DEL_AFTER} ${SQC_ROOT}/P2_capana/data
		sqc_cleanup ${PREP_TO_DEL} ${DEL_AFTER} ${SQC_ROOT}/P2_capana/sent
		sqc_cleanup ${KEEPALARMS}  ${DELALARMS} ${SQC_FMANA}
		EOS
	sqc_logit main "added search and delete old reportfiles to local config file"

	printf "#\n# Section: OSS performance checks\n#\n" >> ${SQC_CONF}
	
	mkdir -p ${WPERFD} &&
	cp ${UNARCDIR}/watch_performance ${WPERFD}
	sed -i "s|%WPERFD%|${WPERFD}|g" ${WPERFD}/watch_performance
	chown -R ${NSNCC}:sysop ${WPERFD}
	chmod 775 ${WPERFD}/watch_performance
	cat <<-OSS >> ${SQC_CONF}
		sqc_addcro '01 00 * * * ${SQC_ROOT}/watch_perf/watch_performance --start-observ --clean-old'
OSS
	sqc_logit main "added OSS performance check to local config file"
#----------------------------------------------------------------------------------------------------
	if [ "${SQC_MBBCOL}" = "YES" ]; then 
#----------------------------------------------------------------------------------------------------
		sqc_logit main "Creating Properties file for MBB Performance Benchmarker Data Collection ..."
		# theoretically we could think about having more than one output file or splitting properties 
		# files for other reasons as e.g. cron scheduling - that explains the unhandy framing below
		for FIL in "${MBB_PROPERTIES}" ; do
			[ -f "${FIL}" ] && mv ${FIL} ${FIL}.old   
			touch ${FIL}; chmod u+w ${FIL}
			[ -w "${FIL}" ] || ( sqc_logit "ERROR: can not write into \"${FIL}\"" ; export ERR="YES")
		done
		[ -r "${MBB_PROPTEMPLATE}" ] || sqc_logit "ERROR: can not find Template for MBB PBM collect \"${MBB_PROPTEMPLATE}\""

		sqc_logit main "... using template \"${MBB_PROPTEMPLATE} $(md5sum ${MBB_PROPTEMPLATE}|awk '{print "( MD5: "$1" )"}')\""

		unset DUMMY
		for PROPARA in "${MBBTECH[@]}"; do case "${PROPARA}" in
			*)
				PUSHTHRU="NO"
				while read LINE; do
					if [[ "${LINE}" == *"%START" ]]; then
						if [ "$( echo ${LINE}|cut -d'%' -f1 )" = "${PROPARA}" ] ; then
							PUSHTHRU="YES"; LINE="#${LINE}"
							sqc_logit main "... adding reports for \"${PROPARA}\" to \"${MBB_PROPERTIES}\""
						fi
					fi
					if [[ "${LINE}" == *"%STOP" ]]; then 
						PUSHTHRU="NO"
					fi
					if [ "${PUSHTHRU}" = "YES" ] ; then
						echo "${LINE}" >> ${MBB_PROPERTIES}
						DUMMY=( ${DUMMY[@]} $( echo ${LINE} |cut -d'.' -f 3) )
					fi
				done <${MBB_PROPTEMPLATE}
			;;
		esac; done
		if [ "${#MBBTECH[@]}" = "0" ]; then
			sqc_logit main "WARNING: MBB PBM Collection activated but no technologies from \"$( basename ${SQC_REPSETS} )\" match in \"$( basename ${MBB_PROPTEMPLATE} )\" "
		else
			ALLTECHS="$(let NDUM=${#DUMMY[@]}-1;JFXL=( $(for i in $(seq 0 ${NDUM}) ; do echo ${DUMMY[$i]}|grep -v "^#"; done|sort -u) );echo ${JFXL[@]}|tr ' ' ',')"
			sed -i "1ijflx.runs=${ALLTECHS[@]}" ${MBB_PROPERTIES}
			sed -i s/%DBUSER%/${DBUSER}/g ${MBB_PROPERTIES}
			sed -i s/%DBPASS%/${DBPASS}/g ${MBB_PROPERTIES}
			sed -i s/%DBIP%/${DBIP}/g ${MBB_PROPERTIES}
			sed -i s/%MBBDAYS/${MBBDAYS}/g ${MBB_PROPERTIES}
			
			printf "# Section : MBB Performance Benchmarker collection of System Reports\n#\n" >> ${SQC_CONF}
			echo "sqc_addcro '${MBB_PBMSCHEDULE}' ${RSRUN} ${MBB_PROPERTIES}" >> ${SQC_CONF}
			sqc_logit main "added MBB PBM collection to config at \"${SQC_CONF}\""
		fi
	else
		sqc_logit main "MBB Performance Benchmarker Data Collection is NOT managed via this tool"
	fi
#----------------------------------------------------------------------------------------------------
	if [ "${RUN3GNQA}" = "YES" ]; then 
#----------------------------------------------------------------------------------------------------
		WRNCTMPL="NQA_worstRNC-v3"

		ALLRAN=( $(find $CONTENT -type d -name "rsran_*"|sort -n) )
		USERAN="$(basename ${ALLRAN[@]:(-1)})"

		if [ -f "${CONTENT}/${USERAN}/reports/RSRAN000.xml" ] ; then
			sqc_logit main "defining contentdir \"${USERAN}\" for worst RNC system-reports"
			cp ${NQA_PROPSARC}/NQA_TEMPLATE-SQCv5-RNC.properties ${CONFIG}
			chmod u+x ${CONFIG}/NQA_TEMPLATE-SQCv5-RNC.properties &>/dev/null
			
			printf "#\n# Section: NQA analysis worst-rnc \n#\n" >> ${SQC_CONF}
			echo "sqc_addcro '30 06 * * *' ${RSRUN} ${CONFIG}/NQA_worstRNC-v3-xls.properties" >> ${SQC_CONF}
			echo "sqc_addcro '38 06 * * *' ${RSRUN} ${CONFIG}/NQA_worstRNC-v3-csv.properties" >> ${SQC_CONF}
			
			cp ${NQA_PROPSARC}/${WRNCTMPL}-csv.properties ${CONFIG}
			cp ${NQA_PROPSARC}/${WRNCTMPL}-xls.properties ${CONFIG}

			for EXT in csv xls 
			do
				sed -i s/%DBUSER%/${DBUSER}/g      ${CONFIG}/${WRNCTMPL}-${EXT}.properties
				sed -i s/%DBPASS%/${DBPASS}/g      ${CONFIG}/${WRNCTMPL}-${EXT}.properties
				sed -i s/%DBIP%/${DBIP}/g          ${CONFIG}/${WRNCTMPL}-${EXT}.properties
				sed -i s/%CUSTOMER%/${CUSTOMER}/g  ${CONFIG}/${WRNCTMPL}-${EXT}.properties
				sed -i s/%CLUSTER%/${CLUSTER}/g    ${CONFIG}/${WRNCTMPL}-${EXT}.properties
				sed -i s/%USERAN%/${USERAN}/g      ${CONFIG}/${WRNCTMPL}-${EXT}.properties
			done
			sqc_logit main "added 3G NQA analysis cron jobs to local config file"
		else
			sqc_logit "ERROR: can not find a system report template to use for worst RNC"; ERR="YES"
		fi
	else sqc_logit main "3G NQA worst RNC collection not enabled on this cluster"
	fi
#----------------------------------------------------------------------------------------------------
	if [ "${RUN2GNQA}" = "YES" ]; then
#----------------------------------------------------------------------------------------------------
:
		# not yet implemented
		# hook up here once done
		# sqc_logit main "added 2G NQA analysis cron jobs to local config file"
	fi
#----------------------------------------------------------------------------------------------------
		
		printf "#\n# Section: consolidating NQA files\n#\n" >> ${SQC_CONF}
		cat <<-EON >> ${SQC_CONF}
			sqc_zipnqa ${KPI_NQA}
			sqc_zipnqa ${KPI_SQC}
EON
		sqc_logit main "added pair-and-zip xls+csv directories to local config file"

#----------------------------------------------------------------------------------------------------
	sqc_logit main "puting improved rscmd wrappers and other files into into places"
#----------------------------------------------------------------------------------------------------
	if [ -f "${UNARCDIR}/rscmd-sqc.sh" ] ; then
		cp ${UNARCDIR}/rscmd-sqc.sh ${RSRUN}
		chmod u+x ${RSRUN} &>/dev/null
		case ${OSSVERSION} in
			"NA15")
				CLASS="com.nsn.oss.pm.cmd.CmdEngine"
			;;
			"OSS5X")
				CLASS="com.nsn.oss.rs.cmd.CmdEngine"
			;;
		esac
		sed -i s/%JCLASS%/${CLASS}/g ${RSRUN}
	fi
	if [ -f "${UNARCDIR}/nqa.sh" ] ; then
		cp ${UNARCDIR}/nqa.sh ${RSCMD}/bin
		chmod u+x ${RSCMD}/bin/nqa.sh &>/dev/null 
	fi
	
	if [ -f "${UNARCDIR}/engine.properties.${OSSVERSION}" ]; then
		mv ${RSCMD}/content3/conf/engine.properties ${RSCMD}/content3/conf/engine.properties.old
		cp ${UNARCDIR}/engine.properties.${OSSVERSION} ${RSCMD}/content3/conf/engine.properties
	elif [ -f "${UNARCDIR}/engine.properties"   ]; then
		mv ${RSCMD}/content3/conf/engine.properties ${RSCMD}/content3/conf/engine.properties.old
		cp ${UNARCDIR}/engine.properties ${RSCMD}/content3/conf
	fi
#----------------------------------------------------------------------------------------------------
	if [ "${COLECTFM}" = "YES" ]; then 
#----------------------------------------------------------------------------------------------------
		FMSCHEDULE="'30 10 * * 7'"
		printf "#\n# Section: FM analysis data collection \n#\n" >> ${SQC_CONF}
		echo "sqc_addcro ${FMSCHEDULE} ${SQC_ROOT}/nsncc.sh --fmonly" >> ${SQC_CONF}
		sqc_logit main "added FM collection schedule \"${FMSCHEDULE}\" deepth \"${COLDAYFM}\" days"
	else
		sqc_logit main "automatic FM collection not enabled for ${CUSTOMER}${CLUSTER} in this run"
	fi
#----------------------------------------------------------------------------------------------------
	sqc_logit main "cleaning up and trimming logs"
#----------------------------------------------------------------------------------------------------
	if [ "${CLEANUARC}" = "YES" ] ; then
		rm -rf ${UNARCDIR}
		sqc_logit main "deleting unarchive directory"
	else
		sqc_logit main "unarchive dir removal deactivated - mind that it could still be overwritten by this script"
	fi
	chmod u+x ${SQC_ROOT}/nsncc.sh &>/dev/null
	
	[ -f "${SQC_ROOT}/rscmd.log" ] && ( sqc_trim 600 ${SQC_ROOT}/rscmd.log )
	[ -f "${SQC_ROOT}/rscmd_javerr.log" ] && ( sqc_trim 600 ${SQC_ROOT}/rscmd_javerr.log )
	[ -f "${SQC_LOGF}.old" ] && ( sqc_trim 3600 ${SQC_LOGF}.old ) 

	if [ "${DATADUMP_CLEANLOGS}" = "YES" ] ; then
	for DDTMPS in ${CCCTRL} /tmp ; do
		NLOGSTD="$(find ${DDTMPS} -name"check.*" -maxdepth 1 -mtime +${DATADUMP_MAXLOGAGE} 2>/dev/null|wc -l)"
		sqc_logit main "found \"${NLOGSTD}\" old tempfiles from --datadump option to delete in ${DDTMPS}"
		find /tmp -name"check.*" -maxdepth 1 -mtime +${DATADUMP_MAXLOGAGE} -exec rm -f {} 2>/dev/null \;
	done; fi
#----------------------------------------------------------------------------------------------------
	CUSTADD="NO"; let L=0
	if [ -f "${SQC_CUSTOM}" ] ; then
		sqc_logit main "found local config file for customer specific additions" 
		printf "#\n# Section: Customer specific additions\n#\n" >> ${SQC_CONF}
		while read line
		do
			if [ ! ${line:0:1} == "#" ] ; then
				echo "${line}" >> ${SQC_CONF}
				sqc_logit main "added custom: \"${line}\""
				let L=$L+1
				fi
		done <${SQC_CUSTOM}
		CUSTADD="YES"
		[ "${L}" = "0" ] &&  sqc_logit main "local customer specific additions file is empty"
	fi
	if [ "${CUSTADD}" = "NO" ] ; then
		sqc_logit main "no customer specific additions found"
	else
		sqc_logit main "added \"${L}\" lines from \"${SQC_CUSTOM}\" to \"${SQC_CONF}\""
	fi
#----------------------------------------------------------------------------------------------------
	sqc_logit main "running config file functions \"${SQC_CONF}\""
#----------------------------------------------------------------------------------------------------
	[ ! -f "${OLD_CRONTAB}" ] && ( crontab -l > ${OLD_CRONTAB} ) 
	if [ "${DATADUMP}" = "YES" ] ; then
		sqc_logit WARNING "Datadump option set - will send collection jobs to batchq NOW rather than making a cron schedule!"
		DDSCRIPT="${CCCTRL}/check.${MYPID}"; export -p DDSCRIPT
		DDLOG="/tmp/check.${MYPID}.log"
		awk '/^sqc_addcro/ {print $7" "$8}' ${SQC_CONF} |grep ${RSRUN} > ${DDSCRIPT}
		echo "rm -f ${DDSCRIPT}" >> ${DDSCRIPT} 
		chmod u+x ${DDSCRIPT}
		nohup ${DDSCRIPT} > ${DDLOG} < /dev/null &
		sleep 1; NJOBS="$(jobs -l|wc -l 2>/dev/null)$?"
		if [ "${NJOBS}" = "10" ] ; then
			sqc_logit "sent all rscmd from config to background job PID \"$(jobs -p)\" started at \"$(date| tr -s ' ')\" see \"${DDLOG}\"" 
		else
			sqc_logit "WARNING: Can not unambiguously define if rscmd commands have been sent to nohup correctly:"
			( head -c 40 < /dev/zero | tr '\0' '-' ; echo ) >> ${DDLOG}
			printf "JOB STATUS AS FOUND AFTER SCRIPT ERROR TRAP\n" >> ${DDLOG}
			jobs -l >> ${DDLOG}
			( head -c 40 < /dev/zero | tr '\0' '-' ; echo ) >> ${DDLOG}
			JLIN="$(jobs -l|tr '\t' ' ')"
			sqc_logit "         \"${JLIN}\""
		fi
		grep -v "sqc_addcro" ${SQC_CONF} |grep -v "sqc_delcro" |grep -v "^#" > ${DDSCRIPT}.cont
		echo "rm -f ${DDSCRIPT}.cont" >> ${DDSCRIPT}.cont
		chmod u+x ${DDSCRIPT}.cont
		. ${DDSCRIPT}.cont || (sqc_logit "ERROR: can not continue configured actions after sending rscmd to nohup"; export ERR="YES")
	else
		. ${SQC_CONF} || (sqc_logit "ERROR: can not source configuration in file \"${SQC_CONF}\""; export ERR="YES")
	fi
	#
#----------------------------------------------------------------------------------------------------
	if [ "${VERBLOG}" = "YES" ]; then
		sqc_logit main "script ending with cron schedule set as follows"
		crontab -l | while IFS= read -r line
		do
			sqc_logit cron-job "${line}"
		done
	fi
	MD5="$(md5sum ${SQC_CONF})"
	sqc_logit main "config generated with checksum \"${MD5}\" !"
	echo "===================================================================================================================="
	[ "${VERBLOG}" = "YES" ] && cat ${SQC_CONF}
	[ "${ERR}" = "NO" ] || sqc_logit main "EXITING WITH ERRORS ON THE WAY !!!" 
fi
exit
