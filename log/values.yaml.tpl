fluent-bit:
  image:
    repository: $IMAGE
    tag: $IMAGE_TAG
  tolerations:
    - key: spark
      operator: Equal
      value: exec
      effect: NoSchedule
  config:
    # https://docs.fluentbit.io/manual/pipeline/outputs/s3#using-s3-without-persisted-disk
    outputs: |
      [OUTPUT]
          Name s3
          Match kube.*
          bucket $LOG_BUCKET
          region $REGION
          store_dir /home/ec2-user/buffer
          s3_key_format_tag_delimiters ._
          s3_key_format /fluent-bit/date=%Y-%m-%d/namespace=$TAG[5]/pod=$TAG[4]/$UUID.json
          total_file_size 1M
          upload_timeout 1m
          use_put_object On

