#!/bin/bash
#
#
echo "INFO: $(basename "$0") BEGIN $(date +%s) / $(date  +'%F %T %Z')"

SCRIPT_DIR=`cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P`
source "${SCRIPT_DIR}/env.sh"
source "${SCRIPT_DIR}/functions.shinc"

###################
TIMEDIFF_MAX=100
SLEEP_TIMEOUT=20
SEND_ATTEMPTS=3
###################

Tik_Payload="te6ccgEBAQEABgAACCiAmCM="
NANOSTAKE=$((1 * 1000000000))

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
   fi

dpc_addr=${Depool_addr##*:}
dpc_wc=${Depool_addr%%:*}
if [[ ${#dpc_addr} -ne 64 ]] || [[ ${dpc_wc} -ne 0 ]];then
    echo "###-ERROR(line $LINENO): Wrong DePool address! ${Depool_addr}"
    exit 1
fi

#=================================================
#=================================================
# prepare user signature
Work_Chain=${Tik_addr%%:*}
tik_acc_addr=${Tik_addr##*:}
touch $tik_acc_addr
echo "${tik_secret}${tik_public}" > ${KEYS_DIR}/tik.keys.txt
rm -f ${KEYS_DIR}/tik.keys.bin
xxd -r -p ${KEYS_DIR}/tik.keys.txt ${KEYS_DIR}/tik.keys.bin

#=================================================
# make boc file 
function Make_BOC_file(){
    TC_OUTPUT="$($CALL_TC message --raw --output tik-msg.boc \
            --sign ${KEYS_DIR}/Tik.keys.json \
            --abi $SafeC_Wallet_ABI \
            "$(cat ${KEYS_DIR}/Tik.addr)" submitTransaction \
            "{\"dest\":\"$Depool_addr\",\"value\":$NANOSTAKE,\"bounce\":true,\"allBalance\":false,\"payload\":\"$Tik_Payload\"}" \
            | grep -i 'Message saved to file')"

    if [[ -z $(echo $TC_OUTPUT | grep -i 'Message saved to file') ]];then
        echoerr "###-ERROR(line $LINENO): CANNOT create boc file!!! Can't continue."
        exit 2
    fi

    mv -f tik-msg.boc "${ELECTIONS_WORK_DIR}/tik-msg.boc"
}

##############################################################################
################  Send TIK query to DePool ###################################
##############################################################################
Last_Trans_lt=$(Get_Account_Info ${Depool_addr} | awk '{print $3}')

function Send_Tik(){
    local Attempts_to_send=$SEND_ATTEMPTS
    while [[ $Attempts_to_send -gt 0 ]]; do
        local result=`Send_File_To_BC "${ELECTIONS_WORK_DIR}/tik-msg.boc"`
        if [[ "$result" == "failed" ]]; then
            echoerr "###-ERROR(line $LINENO): Send message for Tik FAILED!!!"| tee -a "${ELECTIONS_WORK_DIR}/${elections_id}.log"
        fi

        local Curr_Trans_lt=$(Get_Account_Info ${Depool_addr} | awk '{print $3}')
        if [[ $Curr_Trans_lt == $Last_Trans_lt ]];then
            echoerr "+++-WARNING(line $LINENO): DePool does not crank up .. Repeat sending.."| tee -a "${ELECTIONS_WORK_DIR}/${elections_id}.log"
            Attempts_to_send=$((Attempts_to_send - 1))
        else
            break
        fi
    done
    echo $Attempts_to_send
}

for (( TryToSetEl=0; TryToSetEl <= 5; TryToSetEl++ ))
do
    echo -n "INFO: Make boc for lite-client ..."
    Make_BOC_file
    echo " DONE"
    echo -n "INFO: Send Tik query to DePool ..."
    #################
    Attempts_to_send=$(( $(Send_Tik | tail -n 1) ))
    #################
    echo " DONE"
    [[ $Attempts_to_send -le 0 ]] && echo "###-=ERROR(line $LINENO): ALARM!!! DePool DOES NOT CRANKED UP!!!" | tee -a "${ELECTIONS_WORK_DIR}/${elections_id}.log"

    Depool_Rounds_Info="$(Get_DP_Rounds $Depool_addr)"
    Curr_Rounds_Info="$(Rounds_Sorting_by_ID "$Depool_Rounds_Info")"
    Curr_DP_Elec_ID=$(( $(echo "$Curr_Rounds_Info" |jq -r '.[1].supposedElectedAt'| xargs printf "%d\n") ))

    if [[ $elections_id -gt 0 ]];then
        echo "INFO: Checking DeePool is set to current elections..."| tee -a "${ELECTIONS_WORK_DIR}/${elections_id}.log"
        echo "Elections ID in DePool: $Curr_DP_Elec_ID"| tee -a "${ELECTIONS_WORK_DIR}/${elections_id}.log"
        [[ $elections_id -eq $Curr_DP_Elec_ID ]] && break
        echo "+++-WARNING: Not set yet. Try #${TryToSetEl}..."| tee -a "${ELECTIONS_WORK_DIR}/${elections_id}.log"
        sleep $SLEEP_TIMEOUT
    else
        break
    fi 
done

if [[ $elections_id -ne $Curr_DP_Elec_ID ]] && [[ $elections_id -gt 0 ]]; then
    echo "###-ERROR(line $LINENO): Current elections ID from elector $elections_id ($(TD_unix2human "$elections_id")) is not equal elections ID from DP: $Curr_DP_Elec_ID ($(TD_unix2human "$Curr_DP_Elec_ID"))" \
        | tee -a "${ELECTIONS_WORK_DIR}/${elections_id}.log"
    echo "INFO: $(basename "$0") END $(date +%s) / $(date)"
    date +"INFO: %F %T %Z Tik DePool FALED!" | tee -a "${ELECTIONS_WORK_DIR}/${elections_id}.log"
    "${SCRIPT_DIR}/Send_msg_toTelBot.sh" "$HOSTNAME Server: DePool Tik:" \
        "$Tg_SOS_sign ALARM!!! Current elections ID from elector $elections_id ($(TD_unix2human $elections_id)) is not equal elections ID from DePool: $Curr_DP_Elec_ID ($(TD_unix2human $Curr_DP_Elec_ID))" 2>&1 > /dev/null
    echo "ERORR ELECTION $elections_id DIFFER ELECTION FROM DePOOL $Curr_DP_Elec_ID" > "${prepElections}"
else
    echo "INFO:      Election ID: $elections_id" | tee -a "${ELECTIONS_WORK_DIR}/${elections_id}.log"
    echo "Elections ID in DePool: $Curr_DP_Elec_ID" | tee -a "${ELECTIONS_WORK_DIR}/${elections_id}.log"
    date +"INFO: %F %T %Z DePool is set for current elections." | tee -a "${ELECTIONS_WORK_DIR}/${elections_id}.log"
   #
   "${SCRIPT_DIR}/Send_msg_toTelBot.sh" "$HOSTNAME Server: DePool:" \
        "$Tg_CheckMark Depool set to curent election. Current elections ID from elector $elections_id ($(TD_unix2human $elections_id)) is equal elections ID from DePool: $Curr_DP_Elec_ID ($(TD_unix2human $Curr_DP_Elec_ID))" 2>&1 > /dev/null
   #
    echo "INFO $elections_id" > "${prepElections}"
fi

echo "+++INFO: $(basename "$0") FINISHED $(date +%s) / $(date  +'%F %T %Z')"
echo "================================================================================================"

      
    exit 0