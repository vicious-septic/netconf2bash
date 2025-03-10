#!/bin/bash
#
# Sample to check Junos device snapshots relevance
#

#INIT 
if [ -z  $1 ];
then
	printf "ERROR: Usage - $0 <hostname> [<routing_engine_id>]"
	exit 1
else
	HOST=$1
fi


#Get raw netconf output from remote host in 5 seconds 
answer=`ssh -o ConnectTimeout=5 -Tt  ${HOST}  -s netconf <<'EOF'
<rpc>
 <get-software-information>
 </get-software-information>
</rpc>
]]>]]>
<rpc>
 <get-snapshot-information>
  <media>internal</media>
 </get-snapshot-information>
</rpc>
]]>]]>
<rpc>
 <request-end-session>
 </request-end-session>
</rpc>
]]>]]>

EOF
` 

if [ $? -ge 255 ]; then
 printf "ERROR: ssh exit code $?"
 exit 1
fi

if [ "$answer" = "" ]; then
 printf "ERROR: $HOST not answered" 
 exit 1
fi

#Remove netconf delimeters and xml namespace attributes 
answer=`printf "<x> $answer </x>" | sed 's/]]>]]>//g' | sed 's/xmlns="[^"]*"//g'`

#Check software info
re_count=$( printf "$answer" | xmllint --recover --xpath "count(//rpc-reply[1]/multi-routing-engine-results/multi-routing-engine-item)" - )
swinfo_count=$( printf "$answer"|xmllint --recover --xpath "count(//rpc-reply[1]//software-information)" -)
if [ $swinfo_count -gt 0 ]; then
	for (( n=1; n<=$swinfo_count; ++n ))
	do
		if [ $re_count -gt 0 ]; then
			prefix="/multi-routing-engine-results/multi-routing-engine-item[$n]"
		fi
		#Find runnning Junos version on recovery snapshots
		if [ $(printf "$answer" | xmllint --recover --xpath "count(//rpc-reply[2]$prefix/output)" - ) -gt 0 ]; 
		then
			junosver=$(printf "$answer"|xmllint --recover --xpath "//rpc-reply[1]$prefix/software-information//junos-version[1]/text()" -)
			if [ $( printf "$answer" | xmllint --recover --xpath "count(//rpc-reply[2]$prefix[./output[contains(.,'$junosver')]])" - ) -eq 0 ]; 
			then
				printf "ERROR: RE $n has no recovery Junos $junosver snapshots"
				exit 1
			fi
		fi
		#Compare primary and backup Junos partitions
		if [ $(printf "$answer"|xmllint --recover --xpath "count(//rpc-reply[2]$prefix//snapshot-information//software-version)" - ) -gt 1 ];
		then
			snapshot1=$(printf "$answer"|xmllint --recover --xpath "//rpc-reply[2]$prefix//snapshot-information//software-version[1]" -)
			snapshot2=$(printf "$answer"|xmllint --recover --xpath "//rpc-reply[2]$prefix//snapshot-information//software-version[2]" -)
			if [[ "$snapshot1" != "$snapshot2" ]];
			then
				printf "ERROR: RE $n snapshots have different Junos versions"
				exit 1
			fi
		fi
	done
	printf "OK"
	exit 0	
else
	printf "ERROR: no software info found"
	exit 1
fi

printf "ERROR: something went wrong"
exit 1


