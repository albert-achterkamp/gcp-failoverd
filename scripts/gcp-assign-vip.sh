#internal_vip
#internal=true
#external_vip
#external=true

mkdir -p /var/log/gcp-failoverd
#Check if the VIP is being used
if $internal; then
    INTERNAL_IP=`gcloud compute addresses list --filter="name=$internal_vip"| grep $internal_vip | awk '{ print $2 }'`
fi
if $external; then
    EXTERNAL_IP=`gcloud compute addresses list --filter="name=$external_vip"| grep $external_vip | awk '{ print $2 }'`
fi
internal_status=true
external_status=true
while $internal_status || $external_status; do
  ZONE=`gcloud compute instances list --filter="name=$(hostname)"| grep $(hostname) | awk '{ print $2 }'`
  if $internal; then
    INTERNAL_IP_STATUS=`gcloud compute addresses list --filter="name=$internal_vip"| grep $internal_vip | awk '{ print $NF }'`
  else
    internal_status=false
  fi

  if $external; then
    EXTERNAL_IP_STATUS=`gcloud compute addresses list --filter="name=$external_vip"| grep $external_vip | awk '{ print $NF }'`
  else
    external_status=false
  fi

  if [[ $INTERNAL_IP_STATUS == "IN_USE" ]];
  then
    #Check if the instance where the IP is tagged is running
    INTERNAL_INSTANCE_REGION=$(gcloud compute addresses list --filter="name=${internal_vip}"|grep ${internal_vip}|awk '{print $(NF-2)}')
    INTERNAL_INSTANCE_NAME=$(gcloud compute addresses describe ${internal_vip} --region=${INTERNAL_INSTANCE_REGION} --format='get(users[0])'|awk -F'/' '{print $NF}')
    INTERNAL_INSTANCE_ZONE=$(gcloud compute instances list --filter="name=${INTERNAL_INSTANCE_NAME}"|grep ${INTERNAL_INSTANCE_NAME}|awk '{print $2}')
    INTERNAL_INSTANCE_STATUS=$(gcloud compute instances describe --zone=${INTERNAL_INSTANCE_ZONE} $INTERNAL_INSTANCE_NAME --format='get(status)')
    if [[ $INTERNAL_INSTANCE_STATUS == "RUNNING" ]];
    then
      echo "Internal IP address in use at $(date)" >> /var/log/gcp-failoverd/default.log
    else
      #Update the alias from the terminated instance to null
      gcloud compute instances network-interfaces update $INTERNAL_INSTANCE_NAME \
        --zone $INTERNAL_INSTANCE_ZONE \
        --aliases "" >> /var/log/gcp-failoverd/default.log
      INTERNAL_IP_STATUS="RESERVED"
    fi
  fi
  if [[ $EXTERNAL_IP_STATUS == "IN_USE" ]];
  then
    #Check if the instance where the IP is tagged is running
    EXTERNAL_INSTANCE_REGION=$(gcloud compute addresses list --filter="name=${external_vip}"|grep ${external_vip}|awk '{print $(NF-1)}')
    EXTERNAL_INSTANCE_NAME=$(gcloud compute addresses describe ${external_vip} --region=${EXTERNAL_INSTANCE_REGION} --format='get(users[0])'|awk -F'/' '{print $NF}')
    EXTERNAL_INSTANCE_ZONE=$(gcloud compute instances list --filter="name=${EXTERNAL_INSTANCE_NAME}"|grep ${EXTERNAL_INSTANCE_NAME}|awk '{print $2}')
    EXTERNAL_INSTANCE_STATUS=$(gcloud compute instances describe --zone=${EXTERNAL_INSTANCE_ZONE} $EXTERNAL_INSTANCE_NAME --format='get(status)')
    if [[ $EXTERNAL_INSTANCE_STATUS == "RUNNING" ]];
    then
      echo "External IP address in use at $(date)" >> /var/log/gcp-failoverd/default.log
    else
      EXTERNAL_ACCESS_CONFIG=$(gcloud compute instances describe --zone=${EXTERNAL_INSTANCE_ZONE} $EXTERNAL_INSTANCE_NAME --format='get(networkInterfaces[0].accessConfigs[0].name)')
      #Delete the access config from the terminated node
      gcloud compute instances delete-access-config --zone=${EXTERNAL_INSTANCE_ZONE} $EXTERNAL_INSTANCE_NAME --access-config-name=${EXTERNAL_ACCESS_CONFIG} >> /var/log/gcp-failoverd/default.log
      EXTERNAL_IP_STATUS="RESERVED"
    fi
  fi
  if [[ $INTERNAL_IP_STATUS == "IN_USE" ]];
  then
    echo "Internal IP address in use at $(date)" >> /var/log/gcp-failoverd/default.log
  else
    # Assign IP aliases to me because now I am the MASTER!
    gcloud compute instances network-interfaces update $(hostname) \
      --zone $ZONE \
      --aliases "${INTERNAL_IP}/32" >> /var/log/gcp-failoverd/default.log
    if [ $? -eq 0 ]; then
      echo "I became the MASTER of ${INTERNAL_IP} at: $(date)" >> /var/log/gcp-failoverd/default.log
      internal_status=false
    fi
  fi
  if [[ $EXTERNAL_IP_STATUS == "IN_USE" ]];
  then
    echo "External IP address in use at $(date)" >> /var/log/gcp-failoverd/default.log
  else
    # Assign IP aliases to me because now I am the MASTER!
    gcloud compute instances add-access-config $(hostname) \
     --zone $ZONE \
     --access-config-name "$(hostname)-access-config" --address $EXTERNAL_IP >> /var/log/gcp-failoverd/default.log
    if [ $? -eq 0 ]; then
      echo "I became the MASTER of ${EXTERNAL_IP} at: $(date)" >> /var/log/gcp-failoverd/default.log
      external_status=false
    fi
  fi
  sleep 2
done
