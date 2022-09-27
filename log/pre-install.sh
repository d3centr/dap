#!/bin/bash
source init.sh

echo 'DaP ~ running Fluent Bit pre-install'

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: logging
EOF

# Create log bucket.
aws s3api head-bucket --bucket $LOG_BUCKET || aws s3 mb s3://$LOG_BUCKET
echo "s3://$LOG_BUCKET"

# API is expecting a prefix: set empty
cat <<EOF | aws s3api put-bucket-lifecycle-configuration \
    --bucket $LOG_BUCKET \
    --lifecycle-configuration file:///dev/stdin
{
    "Rules": [
        {
            "Status": "Enabled", 
            "Expiration": {
                "Days": 7
            },
            "Prefix": ""
        }
    ]
}
EOF

echo 'DaP ~ stateful Fluent Bit resources provisioned'

