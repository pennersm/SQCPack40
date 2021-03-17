#! /bin/sh

extDir="../extensions/rsran/conf/"
backupsufix="_withoutID"
idSufix="_ids"
reportFileName="rsran_report.xml"
levelFileName="rsran_level.xml"
neVersion="rsran_RU50EP1"

CONTENT3=$VARROOT/global/shared/content3

NEW_EXT=`grep -H rsVersion \`find  $CONTENT3/rsran_*  | grep extensions | grep engine_ext.properties \` /dev/null | sort -n -t '=' -k 2 | cut -d ':' -f 1 | tail -n 1  | sed  's/.*\(rsran_.*\)/\1/'| cut -d '/' -f 1`



activateReportID() {

if   checkExtVersion ; then


	if  ! [ -f $extDir$reportFileName"_orig" ]; then
		
		cp $extDir$reportFileName $extDir$reportFileName"_orig"
	fi	
	if [ -f $extDir$reportFileName$backupsufix ]; then
		echo
		echo WARNING: NE ID in report already configured
		echo Press any key to continue
		read
	else	
		
		cp $extDir$reportFileName $extDir$reportFileName$backupsufix
		cp $extDir$reportFileName$idSufix $extDir$reportFileName	
		
		echo
		echo NE IDs display in reports successfully configured
		echo
		echo NB! In order to apply the new configuration please restart Performance Manager	
		echo Press any key to continue
		read
		
	fi
fi

f_menu	
}


deactivateReportID(){

if   checkExtVersion ; then



if [ -f $extDir$reportFileName$backupsufix ]; then
	mv $extDir$reportFileName$backupsufix $extDir$reportFileName
	
	echo
	echo NE IDs display in reports successfully unconfigured
	echo
	echo NB! In order to apply the new configuration please restart Performance Manager	
	echo Press any key to continue
	read
	
else
	echo
	echo NE ID in object selection already configured
	echo Press any key to continue
	read
fi	
fi
f_menu	
}





activateLevelID(){


if   checkExtVersion ; then


if  ! [ -f $extDir$levelFileName"_orig" ]; then
	
	cp $extDir$levelFileName $extDir$levelFileName"_orig"
fi

if [ -f $extDir$levelFileName$backupsufix ]; then
	echo
	echo Report ID already active
	echo Press any key to continue
	read	
else	

	cp $extDir$levelFileName $extDir$levelFileName$backupsufix
	cp $extDir$levelFileName$idSufix $extDir$levelFileName
	
	echo
	echo NE IDs display in object selection successfully configured
	echo In order to apply the new configuration please restart Performance Manager	
	echo Press any key to continue
	read
fi
fi
f_menu	
}

deactivateLevelID(){

if   checkExtVersion ; then

if [ -f $extDir$levelFileName$backupsufix ]; then
	mv $extDir$levelFileName$backupsufix $extDir$levelFileName
	
	echo
	echo NE IDs display in object selection successfully unconfigured
	echo In order to apply the new configuration please restart Performance Manager	
	echo Press any key to continue
	read	
	
else
	echo
	echo Report ID is not active
	echo Press any key to continue
	read
fi	
fi
f_menu	
}


checkExtVersion() {

if [ "$neVersion" != "$NEW_EXT"  ]; then
	
	echo
	echo $neVersion is not the newer RAN version installed 
	echo Only changes in $NEW_EXT configurations will have effect in PM
	echo If you want to procced with the configuration change press \'y\'
	
	read _proceed
	
	case "$_proceed" in
	y) return 0;;
	*) return 1;;
	esac
fi	
	return 0
			
	
}



getActiveExt(){
	echo Active extenssion version:
	echo $NEW_EXT
	read
	f_menu	
}





f_menu() {
tput clear

cat << EOF

ID configuration Menu

 1) Configure NE IDs Display in reports
 2) Configure NE IDs Display in Object Selection
 3) Unconfigure NE IDs Display in reports
 4) Unconfigure NE IDs Display in Object Selection
 -) ---------------------------------------------------------------------
 5) Check Active Extension
 -) ---------------------------------------------------------------------
 Q) Quit

EOF

echo -n "Prompt> "

read _my_choice



case "$_my_choice" in
 1) activateReportID ;;
 2) activateLevelID ;;
 3) deactivateReportID ;;
 4) deactivateLevelID ;;
 5) getActiveExt ;;
# H|h) showHelp ;;
 Q|q) exit ;;
esac
}

f_menu
