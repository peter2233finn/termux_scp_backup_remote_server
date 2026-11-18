lsync="$1"
rsync="$2"

ipAddress="192.168.x.x"
sshKeyFile="~/.ssh/id_rsa"
sshUser="user"
sshPort="22"


# fileRegex is a grep -E regex to check which files to upload.
# Set this to * to upload everything
fileRegex="\.jpg|\.mkv|\.webp|\.pdf|\.jpeg|\.mp4|\.mp3|\.png|\.zip|\.webm"

# Likewise, fileIgnore is a grep -E regex for files to ignore.
fileIgnore="\.trashed|\.thumbnail"

runSshCmd() {
	ssh -n $sshUser@$ipAddress -i $sshKeyFile -p $sshPort "$*"
}

function progress(){
        printf "\r"
        echo -n "$1 out of $2 files processed."
}

# get remote structure and make into unformatted state
echo "Gathering remote file structure"
ssh "$sshUser"@"$ipAddress" -i "$sshKeyFile" -p $sshPort "find \"${rsync}\"" > .rSyncUnformatted

echo "Gathering the local file structure"
find "$lsync" -type f | grep -Ei "$fileRegex" > .lSyncUnformatted


echo "Formatting file lists"
# grep in the command removes empty lines and awk removes trailing white space
cat .lSyncUnformatted | sed "s/$(echo "$lsync" | sed 's/\//\\\//g')//g" | grep -Eiv "$fileIgnore" | grep -v '^$' | sort > .lSyncFormatted
cat .rSyncUnformatted | sed "s/$(echo "$rsync" | sed 's/\//\\\//g')//g" | grep -v '^$' | sort > .rSyncFormatted

echo "Sorting"
grep -v -F -x -f .rSyncFormatted .lSyncFormatted > .toUpload

# create the remote directories to be identical to the client device
echo "Creating remote directories"
remoteDir=""
rm .remoteDir 2> /dev/null
find "$lsync" -type d | sed "s/$(echo "$lsync" | sed 's/\//\\\//g')/$(echo "$rsync" | sed 's/\//\\\//g')/g" | while read l; do echo "\"$l\""; done | while read dir; do
	echo "mkdir -p $dir;" >> .remoteDir
done

# run commands in 200 lines at a time. This fails when there are thousands of folders
l=0
x=''
for i in $(cat .remoteDir); do
	x=" ${x} ${i} "
	l=$((l+1))
	if [ $l -eq 200 ]; then
		runSshCmd "$x" 2> /dev/null
		l=0
		x=''
	fi
done

# Slopily do the last 200 (again), as the if statment above wont get these if there isnt a modulus of 200 folders
runSshCmd "$(tail -n 200 .remoteDir)" 2> /dev/null

x=0
total="$(wc -l .toUpload | awk '{print $1}')"
cat .toUpload | while read file; do
	remotepath="${rsync}${file}"
	localpath="${lsync}${file}"

	# I was using a SSH version that only accepts -O
	scp -O -P $sshPort -i $sshKeyFile "${localpath}" $sshUser@$ipAddress:"\"${remotepath}\""
	((x++))
	progress $x $total
done

# make sure the files are written
runSshCmd "sync"
