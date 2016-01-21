#!/bin/bash

#This script is intended to transform static MPD generated by MP4BOX to dynamic. This is done by:
#1- Change type="static" to type="dynamic"
#2- Add availabilityStartTime at MPD level
#3- Set Period ids incrementally in case they are empty

if [ $# -ne 9 ]
then
	echo "Usage: ./ConvertMPD.sh MPDName VideoRepresentationID AudioRepresentationID ASTDelayFromNow EncodingSymbolsPerPacket VideoSegmentDuration AudioSegmentDuration VideoOutputFile AudioOutputFile"
	exit
fi 

period=1;	#This is used to incrementally set periods in MPD
toPrint=1;	#This is used to generate new MPD with only 1 video and 1 audio representation.
		#It assumes that audio and video are in seperate adaptation sets
		
videoChunks="Chunks_Video_Inband_Init.txt"		#This file is going to be used to generate FLUTE input file which determines 
									#how to send each segment (i.e. delay before each block of bytes
audioChunks="Chunks_Audio_Inband_Init.txt"

videoSegDur=$6		#Video Segment Duration
audioSegDur=$7		#Audio Segment Duration
firstAudioSegDur=448000

#videoOutput="FluteInput_Video.txt"
#audioOutput="FluteInput_Audio.txt"
videoOutput=$8
audioOutput=$9									
									
#Get CurrentTime
currTime=$(date --date="$4 seconds")

#Get date in UTC (This is the time reference used by the DASH reference client
AST=$(date -u +"%Y-%m-%dT%T" -d "$currTime")
echo $AST

a=$(awk -v startTime=$AST -v period=$period -v toPrint=$toPrint -v MPDName=$1 -v vidRepID=$2 -v audRepID=$3 'BEGIN {value="";gsub(/\./,"_Dynamic.",MPDName)} {sub(/type="static"/,"type=\"dynamic\" availabilityStartTime=\""startTime"Z\" timeShiftBufferDepth=\"PT5S\"");if ($1=="<Period") {sub(/id=""/,"start=\"PT0S\" id=\""period"\""); period++}; if (($1=="<Representation" && index($0,"id=\""vidRepID"\"") == 0 && index($0,"mimeType=\"video") > 0) ||($1=="<Representation" && index($0,"id=\""audRepID"\"") == 0 && index($0,"mimeType=\"audio") > 0)) toPrint=0;if (toPrint==1) {for (i=NF-1;i>1;i--) if (index($i,"timescale=") > 0 || index($i,"duration=") > 0) {value=$i;gsub(/[a-z,A-Z,=,"]/,"",value); print value} else if (index($i,"media=") > 0) {value=$i;gsub(/\$Number\$\.mp4/,"",value); print value};print $0 > MPDName}; if (index($0,"</Representation") > 0) toPrint=1}' $1)

#Convert CurrentTime to unix time. This is to be used later to determine when to send data chunks in FLUTE receiver
AST_UnixTime=$(($(date +%s%6N -d "$currTime")))
echo $AST_UnixTime

if [ $5 -eq 0 ]; then

	#The Resulting file of the below awk is passed to FLUTE sender which uses data to determine when to send (in absolute time) each chunk of each segment). Absolute times are used to avoid drift
	startSending=$(($AST_UnixTime - $videoSegDur - 100000))
	awk -v Time=$startSending 'BEGIN{startSending=Time} {printf("%s %d ",$1,$2);dataField=3; while (dataField<NF) {delayField=dataField+1; startSending +=$delayField;if (delayField == NF) printf ("%0.0f %0.0f\n", $dataField,startSending); else printf ("%0.0f %0.0f ", $dataField,startSending);dataField+=2}}' $videoChunks > $videoOutput

	startSending=$(($AST_UnixTime - $audioSegDur - 100000))
	awk -v Time=$startSending 'BEGIN{startSending=Time} {printf("%s %d ",$1,$2);dataField=3; while (dataField<NF) {delayField=dataField+1; startSending +=$delayField;if (delayField == NF) printf ("%0.0f %0.0f\n", $dataField,startSending); else printf ("%0.0f %0.0f ", $dataField,startSending);dataField+=2}}' $audioChunks > $audioOutput
else
	#Send complete segment after segment duration (i.e. total segment is generated)
	#Since RC starts fetching at AST => Start "generation" 2 segment durations before AST
	#1 segment duration to emulate generation and 1 segment duration to emulate the time to transmit segment
	startSending=$(($AST_UnixTime - 2*$videoSegDur))
	awk -v Time=$startSending -v segmentDur=$videoSegDur 'BEGIN{startSending=Time} {startSending +=segmentDur;printf ("%s %0.0f\n", $1,startSending)}' $videoChunks > $videoOutput
	
	startSending=$(($AST_UnixTime - 2*$audioSegDur))
	awk -v Time=$startSending -v segmentDur=$audioSegDur -v firstSeg=$firstAudioSegDur 'BEGIN{startSending=Time} {if(NR <= 2) {startSending +=firstSeg;} else {startSending +=segmentDur;}; printf ("%s %0.0f\n", $1,startSending)}' $audioChunks > $audioOutput
fi	
	


