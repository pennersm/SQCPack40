#!/bin/bash
TTYOUT='NO'
unset PROPTEMPLATE NELIST
RSCMDIR='/var/opt/nokia/oss/global/shared/rscmd'
NQA2GTMPL='NQA_TEMPLATE-SQCv1-BSC.properties'
NQA3GTMPL='NQA_TEMPLATE-SQCv4-RNC.properties'
RSCMDIR='/var/opt/nokia/oss/global/shared/rscmd'
NOW=$(date +%d%m%Y%H%M%S)

RUN_NQA='NO';CLIERR='NO'; unset TPAR TARG; while [ $# !=  0 ]
do
	TPAR=$(echo $1 |cut -d= -f 2)
	TARG=$(echo $1 |cut -d= -f 1)

        case $TARG in
        -NQA2G)
                RUN_NQA='YES'
                MYNE=${TPAR};OCID='3'
                PROPTEMPLATE="${RSCMDIR}/configurations/${NQA2GTMPL}"
        ;;
        -NQA3G)
                RUN_NQA='YES'
                MYNE=${TPAR}; OCID='811'
                PROPTEMPLATE="${RSCMDIR}/configurations/${NQA3GTMPL}"
         ;;
        -CFFILE)
                export -p PROPTEMPLATE=${TPAR}
        ;;
        -v)
                TTYOUT='YES'
        ;;
        esac; shift
done
if [ -z "${TPAR}" ] || [ -z "${PROPTEMPLATE}" ] ; then CLIERR='YES'; fi
usage() {
        cat <<- EOT
		Start NQA analysis with dynamic generation of config file

		nqa.sh ( -NQA3G={RNCNAME|ALL} || -NQA2G={BSCNAME|ALL} ) [-v]

		MIND: It is either NQA2G or NQA3G - do not try to run both in one command

	EOT
}

if [ "${RUN_NQA}" = "YES" ] && [ "${CLIERR}" = 'NO' ]; then
        OUTDIR='/var/opt/nokia/oss/global/shared/rscmd/configurations'
        DBUSER='pmr'
        DBIP=$(host $(/opt/nokia/oss/bin/ldapacmx.pl -sgPkgHost db)|cut -d' ' -f 4)
        DBPASS=$(polpasmx -${DBUSER})
        [ "$(polpasmx -pmr >/dev/null)$?" != "0" ] && unset ${DBPASS}
        : ${DBPASS:='pmr'}
        if [ "${MYNE}" = 'ALL' ]; then
                NELIST=( $(sqlplus -S ${DBUSER}/${DBPASS} <<-EOSQL
			set heading off
			set pages 0
			set verify off
			set feedback off
			select CO_NAME from UTP_COMMON_OBJECTS where CO_OC_ID=$OCID;
			exit
		EOSQL
                ) )
        else
                NELIST="${MYNE}"
        fi

    TMPLOGF="/tmp/NQA_${NOW}.log" ; rm -f ${TMPLOGF} &>/dev/null
    TMPFILE="/tmp/NQA_${NOW}.nqa" ; rm -f ${TMPFILE} &>/dev/null

    for NE in ${NELIST[*]}; do
        . ${PROPTEMPLATE} ${NE}
        sleep 2; sync &&
		cat <<- EOO >> ${TMPFILE}
			echo "starting ${NE} at \$(date)" >> ${TMPLOGF}
			${RSCMDIR}/bin/rscmd.sh ${RSCMDIR}/configurations/NQA_${NE}_xls.properties
			rm -f ${RSCMDIR}/configurations/NQA_${NE}_xls.properties
			rm -f /tmp/RSRAN???_?????????????_Jflx.???
			${RSCMDIR}/bin/rscmd.sh ${RSCMDIR}/configurations/NQA_${NE}_csv.properties
			rm -f ${RSCMDIR}/configurations/NQA_${NE}_csv.properties
			rm -f /tmp/RSRAN???_?????????????_Jflx.???
			echo "-----------------------------------------------------------------------"; echo
			sleep 1; sync
		EOO
    done
    chmod u+x ${TMPFILE}
    nohup ${TMPFILE} >> ${TMPLOGF} &
    if [ "${TTYOUT}" = "YES" ] ; then
        echo ; echo "CTRL-C to stop tailing nohup log, reports will continue and log to ${TMPLOGF}"
        echo; echo; tail -f ${TMPLOGF}
    fi
else
    if [ "${TTYOUT}" = "YES" ] ; then echo "wrong or incomplete invocation, no NQA started" ; fi
    usage
    exit 1
fi
