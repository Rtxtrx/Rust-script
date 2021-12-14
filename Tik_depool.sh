#!/bin/bash
#
#
echo "INFO: $(basename "$0") BEGIN $(date +%s) / $(date  +'%F %T %Z')"

SCRIPT_DIR=`cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P`
source "${SCRIPT_DIR}/env.sh"
source "${SCRIPT_DIR}/functions.shinc"

#===============================================
# Check node sync
TIME_DIFF=$(Get_TimeDiff)
if [[ $TIME_DIFF -gt $TIMEDIFF_MAX ]];then
    echo "###-ERROR(line $LINENO): Your node is not synced. Wait until full sync (<$TIMEDIFF_MAX) Current timediff: $TIME_DIFF"
    "${SCRIPT_DIR}/Send_msg_toTelBot.sh" "$HOSTNAME Server" "$Tg_SOS_sign ###-ERROR(line $LINENO): Your node is not synced. Wait until full sync (<$TIMEDIFF_MAX) Current timediff: $TIME_DIFF" 2>&1 > /dev/null
    exit 1
fi
echo "INFO: Current TimeDiff: $TIME_DIFF"

#=================================================
# get elector address
elector_addr=$(Get_Elector_Address)
echo "INFO: Elector Address: $elector_addr"

#=================================================
# Get elections ID
elections_id=$(Get_Current_Elections_ID)
elections_id=$((elections_id))
echo "INFO:      Election ID: $elections_id"
#=================================================
# Continue to Tik depool
if [[ $elections_id -eq 0 ]];then
    echo "+++-WARN(line $LINENO):There is no elections now! Exit!"
    exit 1
else
    echo "${elections_id}" >> "${ELECTIONS_WORK_DIR}/${elections_id}.log"
fi
#=================================================
# Addresses and vars
Depool_Name=$1
if [[ -z $Depool_Name ]];then
    Depool_Name="depool"
    Depool_addr=`cat "${KEYS_DIR}/${Depool_Name}.addr"`
    if [[ -z $Depool_addr ]];then
        echo "###-ERROR(line $LINENO): Can't find DePool address file! ${KEYS_DIR}/${Depool_Name}.addr"
        exit 1
    fi
else
    Depool_addr=$Depool_Name
    acc_fmt="$(echo "$Depool_addr" |  awk -F ':' '{print $2}')"
    [[ -z $acc_fmt ]] && Depool_addr=`cat "${KEYS_DIR}/${Depool_Name}.addr"`
fi
if [[ -z $Depool_addr ]];then
    echo "###-ERROR(line $LINENO): Can't find DePool address file! ${KEYS_DIR}/${Depool_Name}.addr"
    exit 1
    exit 0