#!/bin/bash
# This is an external deploy script for besync command.
# You can edit this file to add custom commands to be executed when you run 'besync deploy'.

# The following is an example of how this file can look with custom commands:

#   echo ====== Step 1/3: Build the project ...  ======
#   cd /home/darek/project/
#   npm run build
#   if [[ $? -ne 0 ]]; then
#       echo "Build failed. Aborting deployment."
#       exit 1
#   fi

#   echo ====== Step 2/3: Deploy the result of build to the server ...  ======
#   rsync -avz -e ssh --partial /home/darek/project/dist/ root@servername:/var/www/example.com//assets/

#   echo ====== Step 3/3: Deploy other static files like index.html and images ...  ======
#   rsync -avz -e ssh --partial --include="*/" --include="images/" --exclude="*" /home/darek/project/ root@servername:/var/www/example.com//

#   echo Deployment completed successfully.
