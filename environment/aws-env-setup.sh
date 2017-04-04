#!/usr/bin/env bash

declare -r SCRIPT_DIRECTORY=$(cd `dirname $0` && pwd)
declare -r aws_cf_net_template="$SCRIPT_DIRECTORY/aws-cf-net.template"
declare -r aws_cf_env_template="$SCRIPT_DIRECTORY/aws-cf-env.template"
declare -r aws_cf_net_stack_name="higginbotham-net-stack"
declare -r aws_cf_env_stack_name="higginbotham-env-stack"
declare -r hgbm_instance_name="higginbotham-server"
declare -r hgbm_docker_compose_file="https://raw.githubusercontent.com/davehemming/higginbotham/master/docker/docker-compose.yml"
declare -r hgbm_service_port=8080
declare aws_key_file=
declare hgbm_instance_id=
declare hgbm_instance_state=
declare hgbm_public_ip=
declare hgbm_system_status=
declare hgbm_instance_status=
declare hgbm_net_stack_exists=$(aws cloudformation describe-stacks \
--stack-name $aws_cf_net_stack_name \
--output text \
--query 'Stacks[*].StackName' &> /dev/null; printf "\n%s" $?)
declare hgbm_env_stack_exists=$(aws cloudformation describe-stacks \
--stack-name $aws_cf_env_stack_name \
--output text \
--query 'Stacks[*].StackName' &> /dev/null; printf "\n%s" $?)

while getopts "k:" opt; do
  case $opt in
    k)
      aws_key_file="${OPTARG}"
      ;;
    \?)
      printf "\n%s" "invalid option: -${OPTARG}" >&2
      exit 1
      ;;
    :)
      printf "\n%s" "option -${OPTARG} requires an argument" >&2
      exit 1
      ;;
  esac
done

if [[ ! $aws_key_file ]]; then
  printf "\n%s" "aws key file path has not been set. Use the -k option to set it." >&2
  exit 1
elif [[ ! -e $aws_key_file ]]; then
  printf "\n%s" "aws key file does not exist" >&2
  exit 1
fi

if [[ ! -e $aws_cf_net_template ]]; then
  printf "\n%s" "the aws cloud formation template file '${aws_cf_net_template}' does not exist" >&2
  exit 1
fi

if [[ $hgbm_env_stack_exists -eq 0 ]]; then
  printf "\n%s" "an aws cloudformation stack with the name '${aws_cf_env_stack_name}' already exists.\
  Please delete it before rerunning this script." >&2
  exit 1
fi

if [[ $hgbm_net_stack_exists -ne 0 ]]; then
  printf "\n%s" "creating an aws cloudformation stack with the name '${aws_cf_net_stack_name}'" >&2
  printf "\n%s" "..." >&2

  aws cloudformation create-stack \
  --stack-name $aws_cf_net_stack_name \
  --template-body "file://$aws_cf_net_template" \
  > /dev/null 2>&1

  aws_cf_env_stack_creation_status=
  while [[ $aws_cf_env_stack_creation_status != "CREATE_COMPLETE" ]]; do
    aws_cf_env_stack_creation_status=$(aws cloudformation describe-stacks \
    --stack-name $aws_cf_net_stack_name \
    --output text \
    --query 'Stacks[*].StackStatus')

    if [[ $aws_cf_env_stack_creation_status == "CREATE_COMPLETE" ]]; then
      printf "\n%s" "aws cloudformation environment stack with the name '${aws_cf_net_stack_name}' has been created" >&2
    else
      printf "." >&2
      sleep 1
    fi
  done
fi

printf "\n%s" "creating an aws cloudformation stack with the name '${aws_cf_env_stack_name}'" >&2
printf "\n%s" "..." >&2

declare -r aws_key_file_name=$(basename $aws_key_file ".pem")
aws cloudformation create-stack \
--stack-name $aws_cf_env_stack_name \
--template-body "file://$aws_cf_env_template" \
--parameters ParameterKey=KeyName,ParameterValue=$aws_key_file_name \
> /dev/null 2>&1

aws_cf_env_stack_creation_status=
while [[ $aws_cf_env_stack_creation_status != "CREATE_COMPLETE" ]]; do
  aws_cf_env_stack_creation_status=$(aws cloudformation describe-stacks \
  --stack-name $aws_cf_env_stack_name \
  --output text \
  --query 'Stacks[*].StackStatus')

  if [[ $aws_cf_env_stack_creation_status == "CREATE_COMPLETE" ]]; then
    printf "\n%s" "aws cloudformation stack with the name '${aws_cf_env_stack_name}' has been created" >&2
  else
    printf "." >&2
    sleep 1
  fi
done

printf "\n%s" "waiting for higginbotham server to come up" >&2
printf "\n%s" "..." >&2

hgbm_instance_state=
while [[ -z $hgbm_instance_state || $hgbm_instance_state != "running" ]]; do
  hgbm_instance_state=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=$hgbm_instance_name" \
    "Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped" \
    --output text --query "Reservations[*].Instances[*].[State.Name]")

  if [[ $hgbm_instance_state == "running" ]]; then
  	printf "\n%s" "higginbotham server is up" >&2
  else
  	printf "." >&2
  	sleep 1
  fi
done

printf "\n%s" "downloading and installing updates and dependencies" >&2
printf "\n%s" "..." >&2

hgbm_instance_state=
while [[ -z $hgbm_instance_state || $hgbm_instance_state == "running" ]]; do
    hgbm_instance_state=$(aws ec2 describe-instances \
      --filters "Name=tag:Name,Values=$hgbm_instance_name" \
      "Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped" \
      --output text --query "Reservations[*].Instances[*].[State.Name]")

    if [[ $hgbm_instance_state != "running" ]]; then
      printf "\n%s" "finished installing updates" >&2
    else
      printf "." >&2
      sleep 1
    fi
done

printf "\n%s" "rebooting system to apply updates." >&2
printf "\n%s" "..." >&2

hgbm_instance_state=
while [[ -z $hgbm_instance_state || $hgbm_instance_state != "stopped" ]]; do
    hgbm_instance_state=$(aws ec2 describe-instances \
      --filters "Name=tag:Name,Values=$hgbm_instance_name" \
      "Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped" \
      --output text --query "Reservations[*].Instances[*].[State.Name]")

    if [[ $hgbm_instance_state != "stopped" ]]; then
      printf "." >&2
      sleep 1
    fi
done

printf "\n%s" "system has stopped, starting system." >&2
printf "\n%s" "..." >&2

hgbm_instance_id=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=$hgbm_instance_name" \
    "Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped" \
    --output text --query "Reservations[*].Instances[*].[InstanceId]")
aws ec2 start-instances --instance-ids $hgbm_instance_id > /dev/null 2>&1
hgbm_instance_state=
while [[ -z $hgbm_instance_state || $hgbm_instance_state != "running" ]]; do
    hgbm_instance_state=$(aws ec2 describe-instances \
      --filters "Name=tag:Name,Values=$hgbm_instance_name" \
      "Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped" \
      --output text --query "Reservations[*].Instances[*].[State.Name]")

    if [[ $hgbm_instance_state != "running" ]]; then
      printf "." >&2
      sleep 1
    fi
done

hgbm_public_dns_name=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=$hgbm_instance_name" \
    "Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped" \
    --output text --query "Reservations[*].Instances[*].[PublicDnsName]")
hgbm_server_ssh_open=1
while [[ $hgbm_server_ssh_open -ne 0 ]]; do
    hgbm_server_ssh_open=$(nc -w 1 $hgbm_public_dns_name 22 &> /dev/null; printf "\n%s" $?)
    if [[ $hgbm_server_ssh_open -eq 0 ]]; then
      printf "\n%s" "higginbotham server is back up after reboot" >&2
    else
      printf "." >&2
      sleep 1
    fi
done

printf "\n%s" "Starting higginbotham service" >&2
printf "\n%s" "..." >&2

ssh -o "StrictHostKeyChecking no" \
-i ~/Dev/aws/ssh-keys/aws-default.pem ubuntu@$hgbm_public_dns_name \
"wget $hgbm_docker_compose_file &>/dev/null; nohup docker-compose up &>/dev/null &" 2>/dev/null

hgbm_service_up=1
while [[ $hgbm_service_up -ne 0 ]]; do
    hgbm_service_up=$(curl $hgbm_public_dns_name:$hgbm_service_port &> /dev/null; printf "\n%s" $?)

    if [[ $hgbm_service_up -eq 0 ]]; then
      printf "\n%s" "higginbotham service is up and available at: http://$hgbm_public_dns_name:$hgbm_service_port" >&2
    else
      printf "." >&2
      sleep 1
    fi
done

exit 0
