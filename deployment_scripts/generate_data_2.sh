      # Set variables
      LOG_FILE="/var/log/miztiik-$(date +'%Y-%m-%d').json"

      URL="https://store-backend-fnapp-005.azurewebsites.net/api/store-events-consumer-fn"
      LOG_COUNT=2
      COMPUTER_NAME=$(hostname)
      SLEEP_AT_WORK_SECS=1
      LOG_COUNT=2

      GREEN="\e[32m"
      CYAN="\e[36m"
      YELLOW="\e[33m"
      RESET="\e[0m"

      for ((i=1; i<=LOG_COUNT; i++))
      do
      FILE_NAME_PREFIX=$(openssl rand -hex 4)
      FILE_NAME="${RANDOM}_$(date +'%Y-%m-%d')_event.json"

      PAYLOAD="{\"message\": \"hello world on $(date +'%Y-%m-%d')\" , \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\", \"computer_name\": \"${COMPUTER_NAME}\"}"
      
      echo -e "Sending payload: ${YELLOW} $PAYLOAD ${RESET}"

      RESP_STATUS=$(curl -s -X POST -H "Content-Type: application/json" -d "$PAYLOAD" "$URL")
      
      sleep ${SLEEP_AT_WORK_SECS}
      echo -e "\n  ${YELLOW} ($i/$LOG_COUNT) ${RESET} ${GREEN}${RESP_STATUS}${RESET}"
      done

