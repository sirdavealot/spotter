# Desktop client. Uses multipass to spin up an Ubuntu VM to act as a jump server for logging into the server
# AWS CLI and necessary scripts are installed on the server to enable dynamically calling for instance ID, instance DNS address etc..

#
RANGE=999
num=$RANDOM
let "num %= $RANGE"
VM_NAME="spot-jump-"$num

if [ "$1" == --setup ]
then
    echo 'Installing.. The process will take 5-10 mins'
    echo ''

    # Install multipass if not already installed
    str=`multipass 2> /dev/null || echo uninstalled`
    if [ "$str" == uninstalled ]; then
        brew update
        brew cask install multipass
        sleep 10
    fi

    # Clean up any old VMs
    multipass stop --all
    multipass delete --all
    multipass purge

    # Launch new VM, install AWS CLI, and download utility scripts from github
    multipass launch --name $VM_NAME
    multipass exec $VM_NAME -- sudo apt update
    multipass exec $VM_NAME -- sudo apt install -y awscli

    CREDS=$(tail -1 /Volumes/Keybase/team/atg_and_obt/atg_aws_cli.csv)
    rem=$CREDS
    KEY="${rem%%,*}"; rem="${rem#*,}"
    SECRET="${rem%%,*}"

    touch _aws_creds_tmp
    echo '[default]' >> _aws_creds_tmp
    echo 'aws_access_key_id = '$KEY >> _aws_creds_tmp
    echo 'aws_secret_access_key = '$SECRET >> _aws_creds_tmp
    touch _aws_cfg_tmp
    echo '[default]' >> _aws_cfg_tmp
    echo 'region = us-west-2' >> _aws_cfg_tmp
    echo 'output = json' >> _aws_cfg_tmp

    multipass exec $VM_NAME -- mkdir /home/ubuntu/.aws
    multipass exec $VM_NAME -- touch /home/ubuntu/.aws/credentials
    multipass exec $VM_NAME -- touch /home/ubuntu/.aws/config
    multipass transfer _aws_creds_tmp $VM_NAME:/home/ubuntu/.aws/credentials
    multipass transfer _aws_cfg_tmp $VM_NAME:/home/ubuntu/.aws/config
    rm _aws_creds_tmp
    rm _aws_cfg_tmp

    multipass exec $VM_NAME -- git clone https://github.com/sirdavealot/spotter.git
    multipass exec $VM_NAME -- cd spotter

    multipass transfer /Volumes/Keybase/team/atg_and_obt/atg_oregon.pem $VM_NAME:/home/ubuntu/atg_oregon.pem
    multipass exec $VM_NAME -- chmod 600 /home/ubuntu/atg_oregon.pem

    echo 'Spot instance successfull set up. You can now log in (i.e. run script again with --login argument)'

elif [ "$1" == --login ]
then
    str=$(multipass ls --format csv | tail -1)
    VM_NAME="${str%%,*}"

    # Check if instance is up. If not, start it
    str=$(multipass exec $VM_NAME -- aws ec2 describe-instances --filters "Name=tag:Name,Values=Backtesting_spot" --output=text --query="Reservations[*].Instances[*].State")
    str=`echo $str | tr " " :`
    STATE=${str##*:}

    if [ "$STATE" != running ]; then
        echo 'Instance not currently running. Starting it.. May take 1-2 mins'
        multipass exec $VM_NAME -- ./spotter/start.sh $INST_ID
    fi

    INST_ID=$(multipass exec $VM_NAME -- aws ec2 describe-instances --filters "Name=tag:Name,Values=Backtesting_spot" --output=text --query="Reservations[*].Instances[*].InstanceId")
    multipass exec $VM_NAME -- aws ec2 describe-instances --region us-west-2 --instance-ids $INST_ID --output=text --query "Reservations[*].Instances[*].PublicDnsName"
    echo 'SSHing into instance.. Type <exit> anytime to return to your regular shell'
    echo ''
    multipass exec $VM_NAME -- ./spotter/login.sh $INST_ID

elif [ "$1" == --stop ]
then
    str=$(multipass ls --format csv | tail -1)
    VM_NAME="${str%%,*}"

    INST_ID=$(multipass exec $VM_NAME -- aws ec2 describe-instances --filters "Name=tag:Name,Values=Backtesting_spot" --output=text --query="Reservations[*].Instances[*].InstanceId")
    multipass exec $VM_NAME -- aws ec2 describe-instances --region us-west-2 --instance-ids $INST_ID --output=text --query "Reservations[*].Instances[*].PublicDnsName"
    multipass exec $VM_NAME -- ./spotter/stop.sh $INST_ID

else
    echo 'This tool automates logins to spot instances that change over time'
    echo 'Run the script with the appropriate argument below. If this is your first time, use --setup:'
    echo "    --setup  (One-time initial setup, ie './client --setup')"
    echo '    --login  (Login to spot instance)'
    echo '    --stop   (Stop spot instance when you are finished with it)'
fi