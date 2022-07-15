#!/bin/bash


if ! grep -q aws_access_key_id ~/.aws/config; then
  if ! grep -q aws_access_key_id ~/.aws/credentials; then
    echo "AWS config not found or CLI not installed. Please run \"aws configure\"."
    exit 1
  fi
fi

######################################################################
#Requesting input
#echo "following bucket will be created"
#echo "app-leap, static-dev or web-dev or dependency-dev"
#read -r -p "Enter enviornment: " ENVNAME
#fix bucket name
#BUCKETNAM=(app-leap-$ENVNAME)
######################################################################

#Commandline arguments
args=$(getopt -n "$(basename "$0")" -o h --longoptions help -- "$@") || exit 1
eval set -- "$args"

while :; do
    case $1 in
        -h|--help)  echo This script will create a bucket, named as supplied argument \n
                    echo will create, encrypt, disable public access, put policy and enable access logs \n
                    echo example ./s3-bucket-operaton.sh my-bucket-name; exit ;;
        --) shift; break ;;
        *) echo "error: $1"; exit 1;;
    esac
done

BUCKETNAM=$1
# create bucket
function createbucket(){
	aws s3api create-bucket --bucket $BUCKETNAM
}

#enable encryption
function enable_encryption(){
    aws s3api put-bucket-encryption \
     --bucket $BUCKETNAM \
     --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
}

function tag_bucket(){
	aws s3api put-bucket-tagging --bucket $BUCKETNAM --tagging \
	'{
		"TagSet": [
			{
				"Key": "Name",
				"Value": "'$BUCKETNAM'"                
			},
            {
				"Key": "AnotherTag",
				"Value": "AnotherTagValue"                
			},
                        {
				"Key": "Again AnotherTag",
				"Value": "Again AnotherTagValue"                
			}
		]
	}'
}

#block public access
function public_access_block(){
    aws s3api put-public-access-block \
    --bucket $BUCKETNAM \
    --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
}


#set aws account id
#AWSID=$(aws sts get-caller-identity --profile default --query 'Account' --output text)
AWSID=$(aws sts get-caller-identity --query 'Account' --output text)

#set bucket policy for log bucket
#set file://policy.json
cat << EOF >> policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "S3ServerAccessLogsPolicy",
            "Effect": "Allow",
            "Principal": {
                "Service": "logging.s3.amazonaws.com"
            },
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::$BUCKETNAM/logs*",
            "Condition": {
                "StringEquals": {
                    "aws:SourceAccount": "$AWSID"
                },
                "ArnLike": {
                    "aws:SourceArn": "arn:aws:s3:::$BUCKETNAM"
                }
            }
        },
        {
            "Sid": "S3PolicyStmt-DO-NOT-MODIFY-1657884101218",
            "Effect": "Allow",
            "Principal": {
                "Service": "logging.s3.amazonaws.com"
            },
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::$BUCKETNAM/*"
        }
    ]
}
EOF

function set_bucket_policy(){
    aws s3api put-bucket-policy \
    --bucket $BUCKETNAM \
    --policy file://policy.json    
}

#put bucket logging in the create s3 bucket
#set logging-status file:/logging.json
cat << EOF >> logging.json
{
        "LoggingEnabled": {
            "TargetBucket": "$BUCKETNAM",
            "TargetPrefix": "local_bucket_access_logs/"
        }
    }
EOF

function put_bucket_logging(){
    aws s3api put-bucket-logging \
    --bucket $BUCKETNAM \
    --bucket-logging-status file://logging.json    
    
}

echo "Creating Bucket, enabling default encryption, blocking public access, creating Tags..."
#function call
createbucket 
enable_encryption
public_access_block
tag_bucket
set_bucket_policy
put_bucket_logging

#List & delete files, policy.json, logging.json etc
echo "Following 2 temporary files were created:"
ls -lt | head -3
echo ""
echo "Temporary files deleting ..........."
echo "Applying rm policy.json logging.json"
echo ""
rm policy.json logging.json
sleep 5
echo "Following bucket is created"
echo ""
aws s3 ls | grep -i $BUCKETNAM
echo ""
echo "Completed!"