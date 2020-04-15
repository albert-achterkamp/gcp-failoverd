#internal_vip
#internal=true
#external_vip
#external=true

mkdir -p /var/log/gcp-failoverd
internal_status=true
external_status=true
while $internal_status || $external_status; do
  ZONE=`gcloud compute instances list --filter="name=$(hostname)"| grep $(hostname) | awk '{ print $2 }'`
  if $internal; then
    INTERNAL_IP=`gcloud compute addresses list --filter="name=$internal_vip"| grep $internal_vip | awk '{ print $2 }'`
    INTERNAL_IP_STATUS=`gcloud compute addresses list --filter="name=$internal_vip"| grep $internal_vip | awk '{ print $NF }'`
    INTERNAL_INSTANCE_REGION=$(gcloud compute addresses list --filter="name=${internal_vip}"|grep ${internal_vip}|awk '{print $(NF-2)}')
    INTERNAL_INSTANCE_NAME=$(gcloud compute addresses describe ${internal_vip} --region=${INTERNAL_INSTANCE_REGION} --format='get(users[0])'|awk -F'/' '{print $NF}')
    INTERNAL_INSTANCE_ZONE=$(gcloud compute instances list --filter="name=${INTERNAL_INSTANCE_NAME}"|grep ${INTERNAL_INSTANCE_NAME}|awk '{print $2}')
    INTERNAL_INSTANCE_STATUS=$(gcloud compute instances describe --zone=${INTERNAL_INSTANCE_ZONE} $INTERNAL_INSTANCE_NAME --format='get(status)')
    if [[ $INTERNAL_IP_STATUS == "IN_USE" ]] && [[ $INTERNAL_INSTANCE_STATUS == "STOPPING" || $INTERNAL_INSTANCE_STATUS == "TERMINATED" ]];
    then
      echo "The instance $INTERNAL_INSTANCE_NAME has a status of $INTERNAL_INSTANCE_STATUS" &>> /var/log/gcp-failoverd/default.log
      #Update the alias from the terminated instance to null
      until gcloud compute instances network-interfaces update $INTERNAL_INSTANCE_NAME --zone $INTERNAL_INSTANCE_ZONE --aliases "" &>> /var/log/gcp-failoverd/default.log; do
        echo "Trying to update the alias from $INTERNAL_INSTANCE_NAME to null" &>> /var/log/gcp-failoverd/default.log
        sleep 2
      done
    fi
    # Assign IP aliases to me because now I am the MASTER!
    until gcloud compute instances network-interfaces update $(hostname) --zone $ZONE --aliases "${INTERNAL_IP}/32" &>> /var/log/gcp-failoverd/default.log; do
      echo "Trying to assign IP aliases to me because now I am the MASTER!" &>> /var/log/gcp-failoverd/default.log
      sleep 2
    done
    echo "I became the MASTER of ${INTERNAL_IP} at: $(date)" >> /var/log/gcp-failoverd/default.log
    internal_status=false
  else
    internal_status=false
  fi

  if $external; then
    EXTERNAL_IP=`gcloud compute addresses list --filter="name=$external_vip"| grep $external_vip | awk '{ print $2 }'`
    EXTERNAL_IP_STATUS=`gcloud compute addresses list --filter="name=$external_vip"| grep $external_vip | awk '{ print $NF }'`
    EXTERNAL_INSTANCE_REGION=$(gcloud compute addresses list --filter="name=${external_vip}"|grep ${external_vip}|awk '{print $(NF-1)}')
    EXTERNAL_INSTANCE_NAME=$(gcloud compute addresses describe ${external_vip} --region=${EXTERNAL_INSTANCE_REGION} --format='get(users[0])'|awk -F'/' '{print $NF}')
    EXTERNAL_INSTANCE_ZONE=$(gcloud compute instances list --filter="name=${EXTERNAL_INSTANCE_NAME}"|grep ${EXTERNAL_INSTANCE_NAME}|awk '{print $2}')
    EXTERNAL_INSTANCE_STATUS=$(gcloud compute instances describe --zone=${EXTERNAL_INSTANCE_ZONE} $EXTERNAL_INSTANCE_NAME --format='get(status)')
    EXTERNAL_ACCESS_CONFIG=$(gcloud compute instances describe --zone=${EXTERNAL_INSTANCE_ZONE} $EXTERNAL_INSTANCE_NAME --format='get(networkInterfaces[0].accessConfigs[0].name)')
    if [[ $EXTERNAL_IP_STATUS == "IN_USE" ]] && [[ $EXTERNAL_INSTANCE_STATUS == "STOPPING" || $EXTERNAL_INSTANCE_STATUS == "TERMINATED" ]];
    then
      echo "The instance $EXTERNAL_INSTANCE_NAME has a status of $EXTERNAL_INSTANCE_STATUS" &>> /var/log/gcp-failoverd/default.log
      #Delete the access config from the terminated node
      until gcloud compute instances delete-access-config --zone=${EXTERNAL_INSTANCE_ZONE} $EXTERNAL_INSTANCE_NAME --access-config-name=${EXTERNAL_ACCESS_CONFIG} &>> /var/log/gcp-failoverd/default.log; do
        echo "Trying to Delete the access config from $INTERNAL_INSTANCE_NAME" &>> /var/log/gcp-failoverd/default.log
        sleep 2
      done
    fi
    # Assign Access Config to me because now I am the MASTER!
    until gcloud compute instances add-access-config $(hostname) --zone $ZONE --access-config-name "$(hostname)-access-config" --address $EXTERNAL_IP &>> /var/log/gcp-failoverd/default.log; do
      echo "Trying to assign IP access config to me because now I am the MASTER!" &>> /var/log/gcp-failoverd/default.log
      sleep 2
    done
    echo "I became the MASTER of ${EXTERNAL_IP} at: $(date)" >> /var/log/gcp-failoverd/default.log
    external_status=false
  else
    external_status=false
  fi
  echo "External IP Status $external_status at $(date)" >> /var/log/gcp-failoverd/default.log
  echo "Internal IP Status $internal_status at $(date)" >> /var/log/gcp-failoverd/default.log
  sleep 2
done
