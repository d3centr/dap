#!/bin/bash
lib_path=../bootstrap/workflow/aws/lib
. $lib_path/profile-configuration.sh
. $lib_path/env.sh --dns
set -euo pipefail  # activate safe options once AWS_PROFILE has been set

echo "WARNING: privileges of web users are no different than admin users"
read -p "Enter an email to sign up for web access: "
while [[ ! $REPLY =~ .+@.+\..+ ]]; do
    echo "DaP ~ $REPLY does not look like an email, try again"
    read -p "Enter an email to sign up: "
done
email=$REPLY

read -sp "Enter a password: "
while [ ! `printf "$REPLY" | wc -c`  -ge 8 ]; do
    echo
    echo "DaP ~ password must be at least 8 characters, try again"
    read -sp "Enter a password: "
done
password=$REPLY
echo
read -sp "Confirm your password: "
while [ "$REPLY" != $password ]; do
    echo
    echo "DaP ~ passwords do not match, try again"
    read -sp "Confirm your password: "
done
password=$REPLY
echo

echo "DaP ~ creating new web user $email for $DaP_DOMAIN domain"
aws cognito-idp admin-create-user --user-pool-id $DaP_COGNITO_POOL \
    --username $email --temporary-password $password --message-action SUPPRESS
aws cognito-idp admin-update-user-attributes --user-pool-id $DaP_COGNITO_POOL \
    --username $email --user-attributes Name=email_verified,Value=true

echo "DaP ~ building up secret hash"
client_secret=`aws cognito-idp describe-user-pool-client \
    --user-pool-id $DaP_COGNITO_POOL --client-id $DaP_COGNITO_CLIENT \
    --query UserPoolClient.ClientSecret --output text`
secret_hash=`printf $email$DaP_COGNITO_CLIENT | 
    openssl sha256 -hmac $client_secret -binary | 
    base64`

echo "DaP ~ overriding FORCE_CHANGE_PASSWORD policy: password is not meant to be shared"
new_password_required=`aws cognito-idp initiate-auth \
    --auth-flow USER_PASSWORD_AUTH --client-id $DaP_COGNITO_CLIENT \
    --auth-parameters USERNAME=$email,PASSWORD=$password,SECRET_HASH=$secret_hash \
    --query Session --output text`

# faking new password because admin is not authenticating external users
mfa_setup=`aws cognito-idp admin-respond-to-auth-challenge \
    --user-pool-id $DaP_COGNITO_POOL --client-id $DaP_COGNITO_CLIENT \
    --session $new_password_required --challenge-name NEW_PASSWORD_REQUIRED \
    --challenge-responses NEW_PASSWORD=$password,USERNAME=$email,SECRET_HASH=$secret_hash \
    --query Session --output text`
echo "DaP ~ user and password authentication validated"

read secret_code session <<< `aws cognito-idp associate-software-token \
    --session $mfa_setup --query '[SecretCode, Session]' --output text`
echo "Set up a 2FA account in a TOTP app with secret key:"
echo $secret_code
echo "First, enter the code above in your app..."
read -p "Then, enter a derived 6-digit token here before it expires: "
status=`aws cognito-idp verify-software-token --session $session --user-code $REPLY \
    --query Status --output text`

if [ $status = SUCCESS ]; then
    echo "Web DaP user $email completed signup!"
    echo "access DaP applications at <subdomain>.$DaP_DOMAIN"
fi

