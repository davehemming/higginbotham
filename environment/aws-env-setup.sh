#!/usr/bin/env bash

declare aws_key_file=
declare -r aws_cf_net_template="`dirname $0`/aws-cf-net.template"
declare -r aws_cf_env_template="`dirname $0`/aws-cf-env.template"
declare -r aws_cf_net_stack_name="higginbotham-net-stack"
declare -r aws_cf_env_stack_name="higginbotham-env-stack"
declare -r hgbm_instance_name="higginbotham-server"
declare hgbm_instance_id=
declare hgbm_instance_state=
declare hgbm_public_ip=
declare hgbm_system_status=
declare hgbm_instance_status=
declare hgbm_net_stack_exists=$(aws cloudformation describe-stacks \
--stack-name $aws_cf_net_stack_name \
--output text \
--query 'Stacks[*].StackName' &> /dev/null; echo $?)
declare hgbm_env_stack_exists=$(aws cloudformation describe-stacks \
--stack-name $aws_cf_env_stack_name \
--output text \
--query 'Stacks[*].StackName' &> /dev/null; echo $?)

while getopts "k:" opt; do
  case $opt in
    k)
      aws_key_file="${OPTARG}"
      ;;
    \?)
      echo "invalid option: -${OPTARG}" >&2
      exit 1
      ;;
    :)
      echo "option -${OPTARG} requires an argument" >&2
      exit 1
      ;;
  esac
done

if [[ ! $aws_key_file ]]; then
  echo "aws key file path has not been set. Use the -k option to set it." >&2
  exit 1
elif [[ ! -e $aws_key_file ]]; then
  echo "aws key file does not exist" >&2
  exit 1
fi

if [[ ! -e $aws_cf_net_template ]]; then
  echo "the aws cloud formation template file '${aws_cf_net_template}' does not exist" >&2
  exit 1
fi

if [[ $hgbm_env_stack_exists -eq 0 ]]; then
  echo "an aws cloudformation stack with the name '${aws_cf_env_stack_name}' already exists.\
  Please delete it before rerunning this script." >&2
  exit 1
fi

if [[ $hgbm_net_stack_exists -ne 0 ]]; then
  echo "creating an aws cloudformation stack with the name '${aws_cf_net_stack_name}'" >&2
  echo -n "..." >&2

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
      echo
  	  echo "aws cloudformation environment stack with the name '${aws_cf_net_stack_name}' has been created" >&2
    else
      echo -n "." >&2
      sleep 1
    fi
  done
fi

echo "creating an aws cloudformation stack with the name '${aws_cf_env_stack_name}'" >&2
echo -n "..." >&2

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
    echo
    echo "aws cloudformation stack with the name '${aws_cf_env_stack_name}' has been created" >&2
  else
    echo -n "." >&2
    sleep 1
  fi
done

echo "waiting for higginbotham server to come up" >&2
echo -n "..." >&2

hgbm_instance_state=
while [[ -z $hgbm_instance_state || $hgbm_instance_state != "running" ]]; do
  hgbm_instance_state=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=$hgbm_instance_name" \
    "Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped" \
    --output text --query "Reservations[*].Instances[*].[State.Name]")

  if [[ $hgbm_instance_state == "running" ]]; then
  	echo
  	echo "higginbotham server is up" >&2
  else
  	echo -n "." >&2
  	sleep 1
  fi
done

echo "downloading and installing updates and dependencies" >&2
echo -n "..." >&2

hgbm_instance_state=
while [[ -z $hgbm_instance_state || $hgbm_instance_state == "running" ]]; do
    hgbm_instance_state=$(aws ec2 describe-instances \
      --filters "Name=tag:Name,Values=$hgbm_instance_name" \
      "Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped" \
      --output text --query "Reservations[*].Instances[*].[State.Name]")

    if [[ $hgbm_instance_state != "running" ]]; then
      echo
  	    echo "finished installing updates" >&2
    else
      echo -n "." >&2
      sleep 1
    fi
done

echo "rebooting system to apply updates." >&2
echo -n "..." >&2

hgbm_instance_state=
while [[ -z $hgbm_instance_state || $hgbm_instance_state != "stopped" ]]; do
    hgbm_instance_state=$(aws ec2 describe-instances \
      --filters "Name=tag:Name,Values=$hgbm_instance_name" \
      "Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped" \
      --output text --query "Reservations[*].Instances[*].[State.Name]")

    if [[ $hgbm_instance_state != "stopped" ]]; then
      echo -n "." >&2
      sleep 1
    fi
done

echo
echo "system has stopped, starting system." >&2
echo -n "..." >&2

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
      echo -n "." >&2
      sleep 1
    fi
done

rs_public_ip=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=$hgbm_instance_name" \
    "Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped" \
    --output text --query "Reservations[*].Instances[*].[PublicIpAddress]")
hgbm_server_ssh_open=1
while [[ $hgbm_server_ssh_open -ne 0 ]]; do
    hgbm_server_ssh_open=$(nc -w 1 $rs_public_ip 22 &> /dev/null; echo $?)
    if [[ $hgbm_server_ssh_open -eq 0 ]]; then
      echo
      echo "higginbotham server is back up after reboot"
    else
      echo -n "." >&2
      sleep 1
    fi
done
