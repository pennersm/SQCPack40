#!/bin/bash
UMASK=`umask`
EXEC=`readlink -e $1`

BASEDIR=$(dirname $0)/../
CURDIR=$PWD

CPDIR=lib
CP=""
JAVA_OPTS=-Xmx2048m $JAVA_OPTS
CLASSNAME=%JCLASS%

SHAREDCONFDIR=$VARROOT/global/shared/rscmd/content3
LOCALCONFDIR=$CURDIR/content3

CONFDIR=""
OUTDIR=$CURDIR/log

# First determine if there is shared content availab
if [[ -d $SHAREDCONFDIR ]]; then
  CONFDIR=$SHAREDCONFDIR
elif [[ -d $LOCALCONFDIR ]]; then
  CONFDIR=$LOCALCONFDIR
else
  echo "ERROR: None of the content directories exist ($LOCALCONFDIR or $SHAREDCONFDIR)"
  echo "Please make one of them available. See $0 --usage"
  exit 1;
fi


init() {

  ## Create string of Java system properties to pass to java executable
  SYSTEMPROPS="-Dcom.nokia.oss.qengine.basePath=$CONFDIR"
  SYSTEMPROPS=$SYSTEMPROPS" -Dcom.nokia.oss.qengine.confDir=$CONFDIR"
  SYSTEMPROPS=$SYSTEMPROPS" -Dlog4j.logger.com.nokia=OFF,A1"
  SYSTEMPROPS=$SYSTEMPROPS" -Dlog4j.logger.com.nokia=DEBUG,A2,VS"
  SYSTEMPROPS=$SYSTEMPROPS" -Dlog4j.appender.A2.File=$OUTDIR/jflx.log"
  SYSTEMPROPS=$SYSTEMPROPS" -Dlog4j.appender.VS.File=$OUTDIR/jflxValueStorage.log"

  if [[ ! -d $OUTDIR ]]; then
    mkdir $OUTDIR
  fi

}

run() {
  cd $BASEDIR
  for f in `ls $CPDIR/*.jar`; do
    CP=$CP:$f
  done;
  umask 002
  ERRTIM="$(date +'%b %d %H:%M:%S')"
  java $JAVA_OPTS $SYSTEMPROPS -cp $CP $CLASSNAME $EXEC 2> >(sed "s/^/${ERRTIM}  ${EXEC##*/} : /"|grep "Exception"| tee -a ${CCCTRL}/rscmd_javerr.log)
  cd $CURDIR
  umask $UMASK
}



  eval $( grep 'CCCTRL=' ${HOME}/.bashrc )
  echo "rscmd start job : ${EXEC##*/} at $(date) on $(hostname)"|tee -a ${CCCTRL}/rscmd.log
#### Prepare the environment
init
#### No, go to work
run && echo "rscmd end job   : ${EXEC##*/} at $(date) on $(hostname)" | tee -a ${CCCTRL}/rscmd.log 
