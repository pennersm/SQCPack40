#!/bin/bash
CORENV=0
[ -d "$(pwd)/complete_tarball" ] || CORENV=1
[ -d "$(pwd)/tmp"              ] || CORENV=1
[ -f "$(pwd)/nsncc.sh"         ] || CORENV=1

if [ ! "${CORENV}" = "0" ]; then echo "looks like no complete env" ; exit; fi
MYLOG="$(pwd)/makenew.log"
printf "____________________________________________________________________________________\n"|tee -a ${MYLOG}
if [ -f "$(pwd)/complete_tarball/nsncc.sh" ] ; then
	printf "saving copy of old tarball version\t: $(ls -lh $(pwd)/complete_tarball/nsncc.sh|awk '{print $6"-"$7" "$8" ("$5")"}')\n"|tee -a ${MYLOG}
	mv complete_tarball/nsncc.sh complete_tarball/nsncc.sh.old
fi
rm nsncc.tar.gz &>/dev/null

cd tmp
printf "last file modified in tmp arch\t\t: $(ls -lh $(find . -maxdepth 4 -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -f2- -d" ")|awk '{print $6"-"$7" "$8" ("$5") "$9}')\n"|tee -a ${MYLOG}
printf "bash part last modified \t\t: $(ls -l ../nsncc.sh|awk '{print $6"-"$7" "$8" ("$5") Bytes"}')\n"|tee -a ${MYLOG}
tar czf ../nsncc.tar.gz .
cd ..

cat nsncc.sh nsncc.tar.gz >  complete_tarball/nsncc.sh
chmod +x  complete_tarball/nsncc.sh

printf "new self-exec tarball created\t\t: $(ls -lh $(pwd)/complete_tarball/nsncc.sh|awk '{print $6"-"$7" "$8" ("$5")"}')\n"|tee -a ${MYLOG}
printf "new tarball MD5 checksum \t\t: $(md5sum complete_tarball/nsncc.sh)\n"|tee -a ${MYLOG}
printf "new repsets.cf MD5 checksum\t\t: $(md5sum tmp/repsets.cf)\n"|tee -a ${MYLOG}
printf "____________________________________________________________________________________\n\n"|tee -a ${MYLOG}
#
#
LOGLEN="6000"
if [ "$(cat ${MYLOG} 2>/dev/null|wc -l)" -gt ${LOGLEN} ] ; then
	mv ${mylog} ${mylog}.tmp
	tail -n ${LOGLEN} ${MYLOG}.tmp > ${MYLOG}
	rm ${MYLOG}.tmp
fi
