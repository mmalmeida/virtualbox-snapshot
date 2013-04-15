#!/bin/bash
#
#Virtualbox backup script
#
# Author
#  |
#  +-- Miguel Almeida (ITClinical)
#
# Last modified
#  |
#  +-- 19-07-2011
#
# Version
#  |
#  +-- 0.0.1

# ------------- system commands used by this script --------------------
#28 10 * * *  root

ID=/usr/bin/id;
ECHO=/bin/echo;

MOUNT=/bin/mount;
RM=/bin/rm;
MV=/bin/mv;
CP=/bin/cp;
MKDIR=/bin/mkdir
USERNAME=youruser
SUDO='sudo -H -u'

start_time=$(date '+%s')
dayofweek=$(date '+%u')
vdipath='/path/to/VirtualBox VMs'
backupPath=/path/to/backup/auto


current_log=$backupPath/current.log
touch $current_log

setWeekNumber(){
  if [ "$week" != "" ] ; then
		previousWeek=$week
	else
		previousWeek="week0"
	fi

	day_num=$(date +%d)
        day_num=$((10#$day_num))

	if (( $day_num <= 7 )); then
		week="week1"
	elif (( $day_num > 7 && $day_num <= 14 )); then
		week="week2"
	elif (( $day_num > 14 && $day_num <= 21 )); then
		week="week3"
	elif (( $day_num > 21 && $day_num <= 28 )); then
		week="week4"
	elif (( $day_num > 28 )); then
		week="week5"
	fi
        printf '%s (%s): Week number was set to %s \n' "$(date '+%Y-%m-%d %H:%M')" $virtualmachine $week >> $current_log
	echo $week > $currentweekfile
}


moveWeekSnapshots(){

	if [ "$week" = "week2" ] ; then
		$CP -al $backupPath/$virtualmachine/week1/Snapshots/* $backupPath/$virtualmachine/$week/Snapshots;
	elif [ "$week" = "week3" ] ; then
		$CP -al $backupPath/$virtualmachine/week2/Snapshots/* $backupPath/$virtualmachine/$week/Snapshots;
	elif [ "$week" = "week4" ] ; then
		$CP -al $backupPath/$virtualmachine/week3/Snapshots/* $backupPath/$virtualmachine/$week/Snapshots;
	elif [ "$week" = "week5" ] ; then
		$CP -al $backupPath/$virtualmachine/week4/Snapshots/* $backupPath/$virtualmachine/$week/Snapshots;
	fi
        printf '%s (%s): Made weekly snapshots hardlink \n' "$(date '+%Y-%m-%d %H:%M')" $virtualmachine >> $current_log
}

copyBaseFiles(){
        printf '%s (%s): Copying base files: moving monthly  \n' "$(date '+%Y-%m-%d %H:%M')" $virtualmachine >> $current_log
	# step 1: delete the oldest snapshot, if it exists:
	if [ -d $backupPath/$virtualmachine/monthly.2 ] ; then			\
	$RM -rf $backupPath/$virtualmachine/monthly.2 ;				\
	fi ;

	# step 2: shift the middle snapshots(s) back by one, if they exist
	if [ -d $backupPath/$virtualmachine/monthly.1 ] ; then			\
		$MV $backupPath/$virtualmachine/monthly.1 $backupPath/$virtualmachine/monthly.2 ;	\
	fi;
	if [ -d $backupPath/$virtualmachine/monthly.0 ] ; then			\
		$CP -al $backupPath/$virtualmachine/monthly.0 $backupPath/$virtualmachine/monthly.1;	\
	fi;
	# step 3: Rsync the virtual machine to monthly.0
        printf '%s (%s): Rsync the virtual machine to monthly.0  \n' "$(date '+%Y-%m-%d %H:%M')" $virtualmachine >> $current_log
	if [[ -d $vdipath/$virtualmachine/ ]] ; then			\
		monthlyCopy
	fi;
}

monthlyCopy(){
	rsync -va --delete "$vdipath/$virtualmachine/" $backupPath/$virtualmachine/monthly.0
	printf '%s (%s): Finished monthly rsync to backup \n' "$(date '+%Y-%m-%d %H:%M')" $virtualmachine >> $current_log ; \
}
dailyCopy(){
	rsync -va --delete "$vdipath/$virtualmachine/Snapshots" $backupPath/$virtualmachine/$week
	rsync -va "$vdipath/$virtualmachine/$virtualmachine.vbox" $backupPath/$virtualmachine/$week
	printf '%s (%s): Finished daily copy to %s \n' "$(date '+%Y-%m-%d %H:%M')" $virtualmachine $backupPath/$virtualmachine/$week >> $current_log ; \
}
weeklyCopy(){
	moveWeekSnapshots
	rsync -va --delete "$vdipath/$virtualmachine/Snapshots" $backupPath/$virtualmachine/$1
	rsync -va "$vdipath/$virtualmachine/$virtualmachine.vbox" $backupPath/$virtualmachine/$1
	printf '%s (%s): Finished weekly copy to %s \n' "$(date '+%Y-%m-%d %H:%M')" $virtualmachine $backupPath/$virtualmachine/$1 >> $current_log ; \
}
dailySnapshot(){
	snapshotLogger "daily" $dayofweek
	$SUDO $USERNAME vboxmanage snapshot $virtualmachine take snapshot-$dayofweek --pause
#	touch $vdipath/$virtualmachine/Snapshots/snapshot-$dayofweek
        printf '%s (%s): Daily snapshot-%s created \n' "$(date '+%Y-%m-%d %H:%M')" $virtualmachine $dayofweek >> $current_log
}
weeklySnapshot(){

	snapshotLogger "week" $1
	$SUDO $USERNAME vboxmanage snapshot $virtualmachine take snapshot-$1 --pause
#	touch $vdipath/$virtualmachine/Snapshots/snapshot-$week
	printf '%s (%s): Weekly snapshot created for week %s  \n' "$(date '+%Y-%m-%d %H:%M')" $virtualmachine $1 >> $current_log
}

snapshotDelete(){
	type=$1;
	linecnt=0;
	while read -r line; do
		((linecnt++))
		array[$linecnt]="${line#*=\"}"
		array[$linecnt]="${array[$linecnt]%\"}"
	done < <($SUDO $USERNAME vboxmanage snapshot $virtualmachine list --machinereadable | grep "SnapshotName=*")
	# use for loop to reverse the array
	for (( j = $linecnt ; j > 0; j-- ));
	do
		if [[ ${array[$j]} =~ "week" && $type == "weekly" || ! ${array[$j]} =~ "week" && $type == "daily" ]]; then
			$SUDO $USERNAME vboxmanage snapshot $virtualmachine delete ${array[$j]}
			printf '%s (%s): Deleted snapshot %s  \n' "$(date '+%Y-%m-%d %H:%M')" $virtualmachine ${array[$j]} >> $current_log
		fi
	done
	
}
snapshotLogger(){
	printf '%s (%s) Logging message to host \n' "$(date '+%Y-%m-%d %H:%M')" $virtualmachine >> $current_log
#	echo 'This should be in snapshot '$1 ' ' $2 | ssh miguel@192.168.10.5 'cat >> ~/Desktop/backupTest'
}

createDirectories(){
	$MKDIR -p $backupPath/$virtualmachine/week0/Snapshots/
	$MKDIR -p $backupPath/$virtualmachine/week1/Snapshots/
	$MKDIR -p $backupPath/$virtualmachine/week2/Snapshots/
	$MKDIR -p $backupPath/$virtualmachine/week3/Snapshots/
	$MKDIR -p $backupPath/$virtualmachine/week4/Snapshots/
}


backup(){

	# Find which week of the month 1-5 it is.
	#If the week hasn't been defined yet, define it and take the weekly snapshot
	touch $currentweekfile

	week=$(cat $currentweekfile)
	firstRun=false
	if [ "$week" = "" ] ; then
		printf '%s Week not defined. Setting firstRun to true  \n' "$(date '+%Y-%m-%d %H:%M')" >> $current_log
		firstRun=true
		setWeekNumber
		copyBaseFiles
		createDirectories
		weeklySnapshot "week0"
	fi

	if [ "$dayofweek" = "7" ] ; then
		#Sunday:
		#	1) delete daily
		#	2) Create weekly
		#	3) Backup transfer
		printf '%s: Deleting daily snapshots. Will keep weekly one \n' "$(date '+%Y-%m-%d %H:%M')" >> $current_log
		snapshotDelete "daily"
		if [ "$firstRun" = false ] ; then
			weeklySnapshot $week
			setWeekNumber
		fi

		weeklyCopy $previousWeek

		#First sunday of the month: backup base
		if [ "$week" = "week1" -a "$firstRun" = false ] ; then
			snapshotDelete "weekly"
			copyBaseFiles
			weeklySnapshot "week0"

		fi

	else
		dailySnapshot
		dailyCopy
	fi

}


##Running the script
FILE=$backupPath/backup.cfg
while read CMD; do
	virtualmachine=$CMD
        currentweekfile=$backupPath/$virtualmachine/currentweek
        backup
done < "$FILE"
