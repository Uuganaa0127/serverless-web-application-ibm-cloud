#!/bin/bash

##############################################################################
# Copyright 2018 IBM Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
##############################################################################

root_folder=$(cd $(dirname $0); pwd)

# SETUP logging (redirect stdout and stderr to a log file)
readonly LOG_FILE="${root_folder}/deploy-html-function.log"
readonly ENV_FILE="${root_folder}/../local.env"

touch $LOG_FILE
exec 3>&1 # Save stdout
exec 4>&2 # Save stderr
exec 1>$LOG_FILE 2>&1

function _out() {
  echo "$@" >&3
  echo "$(date +'%F %H:%M:%S') $@"
}

function _err() {
  echo "$@" >&4
  echo "$(date +'%F %H:%M:%S') $@"
}

function check_tools() {
    MISSING_TOOLS=""
    git --version &> /dev/null || MISSING_TOOLS="${MISSING_TOOLS} git"
    curl --version &> /dev/null || MISSING_TOOLS="${MISSING_TOOLS} curl"
    ibmcloud --version &> /dev/null || MISSING_TOOLS="${MISSING_TOOLS} ibmcloud"    
    if [[ -n "$MISSING_TOOLS" ]]; then
      _err "Some tools (${MISSING_TOOLS# }) could not be found, please install them first and then run scripts/setup-app-id.sh"
      exit 1
    fi
}

function ibmcloud_login() {
  # Skip version check updates
  ibmcloud config --check-version=false

  # Obtain the API endpoint from BLUEMIX_REGION and set it as default
  _out Logging in to IBM cloud
  ibmcloud api --unset
  IBMCLOUD_API_ENDPOINT=$(ibmcloud api | awk '/'$BLUEMIX_REGION'/{ print $2 }')
  ibmcloud api $IBMCLOUD_API_ENDPOINT

  # Login to ibmcloud, generate .wskprops
  ibmcloud login --apikey $IBMCLOUD_API_KEY -a $IBMCLOUD_API_ENDPOINT
  ibmcloud target -o "$IBMCLOUD_ORG" -s "$IBMCLOUD_SPACE"
  ibmcloud fn api list > /dev/null

  # Show the result of login to stdout
  ibmcloud target
}

function setup() {
  _out Deploying function 'serverless-web-app-angular/html'

  cp ${root_folder}/../function-html/function-html.template.js ${root_folder}/../function-html/function-html.js
  npm --prefix ${root_folder}/text-replace start ${root_folder}/text-replace ${root_folder}/../function-html/function-html.js xxx-replace-me-xxx $COS_URL_HOME_BASE

  ibmcloud wsk action create serverless-web-app-sample/html ${root_folder}/../function-html/function-html.js --kind nodejs:8 -a web-export true

  _out Deploying API: function-html
  readonly NAMESPACE="${IBMCLOUD_ORG}_${IBMCLOUD_SPACE}"
  cp ${root_folder}/../function-html/swagger-template.json ${root_folder}/../function-html/swagger.json
  npm --prefix ${root_folder}/text-replace start ${root_folder}/text-replace ${root_folder}/../function-html/swagger.json xxx-your-openwhisk-namespace-for-example:niklas_heidloff%40de.ibm.com_demo-xxx $NAMESPACE
  API_HOME=$(ibmcloud wsk api create --config-file ${root_folder}/../function-html/swagger.json | awk '/https:/{ print $1 }')
  _out API_HOME: $API_HOME
  printf "\nAPI_HOME=$API_HOME" >> $ENV_FILE

 _out Updating function: serverless-web-app-generic/redirect
  readonly CONFIG_FILE="${root_folder}/../function-login/config.json"
  rm $CONFIG_FILE
  touch $CONFIG_FILE
  printf "{\n" >> $CONFIG_FILE
  printf "\"client_id\": \"" >> $CONFIG_FILE
  printf $APPID_CLIENTID >> $CONFIG_FILE
  printf "\",\n" >> $CONFIG_FILE
  printf "\"client_secret\": \"" >> $CONFIG_FILE
  printf $APPID_SECRET >> $CONFIG_FILE
  printf "\",\n" >> $CONFIG_FILE
  printf "\"oauth_url\": \"" >> $CONFIG_FILE
  printf $APPID_OAUTHURL >> $CONFIG_FILE
  printf "\",\n" >> $CONFIG_FILE
  printf "\"webapp_redirect\": \"" >> $CONFIG_FILE
  printf $API_HOME >> $CONFIG_FILE
  printf "\",\n" >> $CONFIG_FILE
  printf "\"redirect_uri\": \"" >> $CONFIG_FILE
  printf $API_LOGIN >> $CONFIG_FILE
  printf "\"\n" >> $CONFIG_FILE
  printf "}" >> $CONFIG_FILE
  CONFIG=`cat $CONFIG_FILE`
  ibmcloud wsk action update serverless-web-app-generic/redirect ${root_folder}/../function-login/redirect.js --kind nodejs:8 -a web-export true -p config "${CONFIG}"

  _out Done! Open your app: ${API_HOME}
}



# Main script starts here
check_tools

# Load configuration variables
if [ ! -f $ENV_FILE ]; then
  _err "Before deploying, copy template.local.env into local.env and fill in environment specific values."
  exit 1
fi
source $ENV_FILE
export IBMCLOUD_API_KEY BLUEMIX_REGION APPID_TENANTID APPID_OAUTHURL APPID_CLIENTID APPID_SECRET CLOUDANT_USERNAME CLOUDANT_PASSWORD COS_URL_HOME COS_URL_HOME_BASE API_HOME

_out Full install output in $LOG_FILE
ibmcloud_login
setup
