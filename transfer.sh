#!/bin/bash

# 1.VARIABLES FOR COLORS:

GREEN_COLOR='\e[1;32m%s\e[0m\n'
YELLOW_COLOR='\e[1;33m%s\e[0m\n'
RED_COLOR='\e[1;31m%s\e[0m\n'
PURPLE_COLOR='\e[1;35m%s\e[0m\n'
CYAN_COLOR='\e[1;36m%s\e[0m\n'

#2.INPUT DOMAIN NAME:

printf "$GREEN_COLOR" 'TYPE THE DOMAIN NAME AND WATCH THE MAGIC HAPPEN!'
read -e -r -p $'\e[36mDomain/Subdomain:\e[0m ' input_domain;


#4.GET DOMAIN DOCUMENT ROOT:

touch temp.txt

sub_folder=$(echo "${input_domain}" | cut -d '/' -f 2-)


if [ "$sub_folder" = "$input_domain"  ]; then
  sub_folder=""
  domain_name=$input_domain
  doc_root=$(uapi DomainInfo single_domain_data domain="$domain_name" | grep "documentroot:" | cut -d ' ' -f 6)

else

  domain_name=$(echo "$input_domain" | cut -d '/' -f 1)
  doc_root=$(uapi DomainInfo single_domain_data domain="$domain_name" | grep "documentroot:" | cut -d ' ' -f 6)
  doc_root=${doc_root}/${sub_folder}

fi

#4.1.CHECK IF DOMAIN EXISTS AND ASK FOR INPUT UNTIL EXISTING DOMAIN IS PROVIDED:

while [ -z "$doc_root" ]; do

  printf "$RED_COLOR" 'INVALID DOMAIN! TYPE THE DOMAIN AGAIN:'
  read -e -r -p $'\e[36mDomain/Subdomain:\e[0m ' input_domain;

  sub_folder=$(echo "$input_domain" | cut -d '/' -f 2-)


  if [ "$sub_folder" = "$input_domain"  ]; then
    sub_folder=""
    domain_name=$input_domain
    doc_root=$(uapi DomainInfo single_domain_data domain="$domain_name" | grep 'documentroot:' | cut -d ' ' -f 6)

  else

    doc_root=$(uapi DomainInfo single_domain_data domain="$domain_name" | grep 'documentroot:' | cut -d ' ' -f 6)
    doc_root=${doc_root}/${sub_folder}

  fi

done

#3.CHECK APPLICATION:

if [ -f wp-config.php ]; then

  application='WordPress'

elif [ -f app/etc/local.xml ]; then

  application='Magento1'

elif [ -f app/etc/env.php ]; then

  application='Magento2'

elif [ -f config.php ] && [ -f admin/config.php ]; then

  application='OpenCart'

elif [ -f configuration.php ]; then

  application='Joomla'

elif [ -f config/settings.inc.php ]; then

  application='PrestaShop1.6'

elif [ -f app/config/parameters.php ]; then

  application='PrestaShop1.7'

fi

#5.GET CPANEL USERNAME AND CUT IT TO 8 CHARS IF LONGER:

cpanel_user=$(uapi DomainInfo single_domain_data domain="$domain_name" | grep 'user:' | cut -d ' ' -f 6)

cpanel_user_length=${#cpanel_user}

if [ "$cpanel_user_length" -ge 8 ]; then

   cpanel_user=$(echo "$cpanel_user" | cut -c 1-8)

fi

#6.GET DATABASE_PREFIX:

db_prefix_length=2

db_prefix=$(echo "$domain_name" | cut -c 1-$db_prefix_length)

#7.GET DATABASE NAME AND DEFINE DEFAULT DB PASSWORD:

db_name=${cpanel_user}_${db_prefix}
db_name=${db_name//./}
dbPass='4eYJEq3KyZr5r1'

#8.CREATE DATABASE (CHECK IF DATABASE EXISTS AND IF YES CHANGE DATABASE_PREFIX UNTIL NEW DB CAN BE CREATED):

db_nameStatus=$(uapi Mysql create_database name="$db_name" | grep 'status:' | cut -d ' ' -f 4)

while [ "$db_nameStatus" -eq 0 ]; do

  db_prefix_length=$((db_prefix_length+1))

  db_prefix=$(echo "$domain_name" | cut -c 1-$db_prefix_length)

#8.1 REMOVE ALL INSTANCES OF '.' IN DATABASE NAME:

  db_name=${cpanel_user}_${db_prefix}
  db_name=${db_name//./}

  db_nameStatus=$(uapi Mysql create_database name="$db_name" | grep 'status:' | cut -d ' ' -f 4)

done

printf "$GREEN_COLOR" 'DATABASE CREATED.'

#9.CREATE DATABASE USER, ADD PRIVILIGES AND OUTPUT IF USER IS CREATED SUCCESSFULLY:

dbUserStatus=$(uapi Mysql create_user name="$db_name" password="$dbPass" | grep 'status:' | cut -d ' ' -f 4)

uapi Mysql set_privileges_on_database user="$db_name" database="$db_name" privileges=ALL%20PRIVILEGES > /dev/null 2>&1

if [ "$dbUserStatus" -eq 1 ]; then

  printf "$GREEN_COLOR" 'DATABASE USER CREATED.'

else

  printf "$RED_COLOR" 'DATABASE USER NOT CREATED!'

fi

#I.WORDPRESS SPECIFIC STEPS:

if [ "$application" = 'WordPress' ]; then

#10.GET OLD DATABASE DETAILS:

  oldDbName=$( < wp-config.php grep -m 1 DB_NAME | cut -d \' -f 4 )
  oldDbUser=$( < wp-config.php grep -m 1 DB_USER | cut -d \' -f 4 )
  oldDbHost=$( < wp-config.php grep -m 1 DB_HOST | cut -d \' -f 4 )

#11.UPDATE DATABASE DETAILS:

#11.1.MAKE A COPY OF ORIGINAL WP-CONFIG:

  cp wp-config.php wp-config.php.bk

#11.2.REPLACE DATABASE NAME USER AND HOSTNAME:

  sed -i "s/$oldDbName\\b/$db_name/g;s/$oldDbUser\\b/$db_name/g;s/$oldDbHost/localhost/g" wp-config.php

#11.3.DELETE DB_PASS LINE AND REPLACE IT WITH PREDEFIEND.

  dbPassLine=$(grep -n 'DB_PASSWORD' wp-config.php | cut -f1 -d:)

  defaultDbLine="define('DB_PASSWORD', '4eYJEq3KyZr5r1');"

  sed -e "${dbPassLine}d" -i wp-config.php
  sed -i "${dbPassLine}i\\$defaultDbLine" wp-config.php

#FIX PATHS IN wp-config.php, wordfence-waf.php, .user.ini AND .htaccess FILES:

  oldDocRoot=$( < wp-config.php grep -m 1 WPCACHEHOME | sed 's/wp-content.*$/wp-content/' | rev | cut -d '/' -f2- | rev | cut -d \' -f 4 | sed 's_/_\\/_g')
  newDocRoot=${doc_root//\//\\/}

  if [ ! -z "$oldDocRoot" ]; then

    sed -i "s/$oldDocRoot/$newDocRoot/g" wp-config.php

  fi

  if [ -f wordfence-waf.php ]; then
    if [ -z "$oldDocRoot" ]; then

      oldDocRoot=$( < wordfence-waf.php grep -m 1 define | sed 's/wp-content.*$/wp-content/' | rev | cut -d / -f2- | rev | cut -d \' -f 2 | sed 's_/_\\/_g' )

    fi

    sed -i "s/$oldDocRoot/$newDocRoot/g" wordfence-waf.php

  fi

  if [ -f .user.ini ]; then
    if [ -z "$oldDocRoot" ]; then

      oldDocRoot=$( < .user.ini grep -m 1 auto_prepend_file | rev | cut  -d '/' -f 2- | rev | cut -d \' -f 2 | sed 's_/_\\/_g' )

    fi

	if [ ! -z "$oldDocRoot" ]; then

	  sed -i "s/$oldDocRoot/$newDocRoot/g" .user.ini

	fi
  fi

  if [ -f .htaccess ]; then

    cp .htaccess .htaccess.bk

    oldPath=$( < .htaccess grep -m 1 RewriteBase | cut -d ' ' -f 2 | sed 's_/_\\/_g' )

    if [ -z $sub_folder ]; then

      newPath=$(echo / | sed 's_/_\\/_g')

    else

     newPath=$(echo /${sub_folder}/ | sed 's_/_\\/_g')

    fi

    sed -i "s/RewriteBase $oldPath/RewriteBase $newPath/" .htaccess
    sed -i "s/RewriteRule \\. $oldPath/RewriteRule \\. $newPath/" .htaccess

    if [ ! -z "$oldDocRoot" ]; then

    sed -i "s/$oldDocRoot/$newDocRoot/g" .htaccess

    fi
  fi

#II. OPENCART SPECIFIC STEPS:

elif [ "$application" = 'OpenCart' ]; then

#10.GET OLD DATABASE DETAILS:

  oldDbName=$( < config.php grep -m 1 DB_DATABASE | cut -d \' -f 4 )
  oldDbUser=$( < config.php grep -m 1 DB_USERNAME | cut -d \' -f 4 )
  oldDbHost=$( < config.php grep -m 1 DB_HOSTNAME | cut -d \' -f 4 )

#11.UPDATE DATABASE DETAILS:

#11.1.MAKE A COPY OF ORIGINAL CONFIG FILES:

  cp config.php config.php.bk
  cp admin/config.php admin/config.php.bk

#11.2.REPLACE DATABASE NAME USER AND HOSTNAME:

  sed -i "s/$oldDbName\\b/$db_name/g;s/$oldDbUser\\b/$db_name/g;s/$oldDbHost/localhost/g" config.php admin/config.php
  
#11.3.DELETE DB_PASS LINE AND REPLACE IT WITH PREDEFIEND IN CONFIG AND ADMIN/CONFIG FILES.

  defaultDbLine="define('DB_PASSWORD', '4eYJEq3KyZr5r1');"

  dbPassLine=$(grep -n 'DB_PASSWORD' config.php | cut -f1 -d:)

  sed -e "${dbPassLine}d" -i config.php
  sed -i "${dbPassLine}i\\$defaultDbLine" config.php

  dbPassLine=$(grep -n 'DB_PASSWORD' admin/config.php | cut -f1 -d:)

  sed -e "${dbPassLine}d" -i admin/config.php
  sed -i "${dbPassLine}i\\$defaultDbLine" admin/config.php

#11.4.GET OLD DIRECTORY PATH:

  oldDocRoot=$( < config.php grep -m 1 DIR_APPLICATION | cut -d \' -f 4 | rev | cut -d '/' -f 3- | rev | sed 's_/_\\/_g' )
  newDocRoot=${doc_root//\//\\/}

#11.5.REPLACE DIRECTORY PATH IN CONFIG FILES:

  sed -i "s/$oldDocRoot/$newDocRoot/g" config.php
  sed -i "s/$oldDocRoot/$newDocRoot/g" admin/config.php

# III.MAGENTO 1 SPECIFIC STEPS:

elif [ "$application" = "Magento1" ]; then

#10.GET OLD DATABASE DETAILS:

  oldDbName=$( < app/etc/local.xml grep -m 1 dbname | cut -d \[ -f 3 | cut -d \] -f 1 )
  oldDbUser=$( < app/etc/local.xml grep -m 1 username | cut -d \[ -f 3 | cut -d \] -f 1 )
  oldDbHost=$( < app/etc/local.xml grep -m 1 host | cut -d \[ -f 3 | cut -d \] -f 1 )

#11.UPDATE DATABASE DETAILS:

#11.1.MAKE A COPY OF ORIGINAL CONFIG FILE:

  cp app/etc/local.xml app/etc/local.xml.bk

#11.2.REPLACE DATABASE NAME USER AND HOSTNAME:

  sed -i "s/$oldDbName\\b/$db_name/g;s/$oldDbUser\\b/$db_name/g;s/$oldDbHost/localhost/g" app/etc/local.xml

#11.3.DELETE DB_PASS LINE AND REPLACE IT WITH PREDEFIEND.

  dbPassLine=$(grep -n 'password' app/etc/local.xml | cut -f1 -d:)

  defaultDbLine="                    <password><![CDATA[4eYJEq3KyZr5r1]]></password>"

  sed -e "${dbPassLine}d" -i app/etc/local.xml
  sed -i "${dbPassLine}i\\$defaultDbLine" app/etc/local.xml

# IV.MAGENTO 2 SPECIFIC STEPS:

elif [ "$application" = 'Magento2' ]; then

#10.GET OLD DATABASE DETAILS:

  oldDbName=$( < app/etc/env.php grep -m 1 dbname | cut -d \' -f 4 )
  oldDbUser=$( < app/etc/env.php grep -m 1 username | cut -d \' -f 4 )
  oldDbHost=$( < app/etc/env.php grep -m 1 host | cut -d \' -f 4 )

#11.UPDATE DATABASE DETAILS:

#11.1.MAKE A COPY OF ORIGINAL CONFIG FILE:

  cp app/etc/env.php app/etc/env.php.bk

#11.2.REPLACE DATABASE NAME USER AND HOSTNAME:

  sed -i "s/$oldDbName\\b/$db_name/g;s/$oldDbUser\\b/$db_name/g;s/$oldDbHost/localhost/g" app/etc/env.php

#11.3.DELETE DB_PASS LINE AND REPLACE IT WITH PREDEFIEND.

  dbPassLine=$(grep -n 'password' app/etc/env.php | cut -f1 -d:)

  defaultDbLine="        'password' => '4eYJEq3KyZr5r1',"

  sed -e "${dbPassLine}d" -i app/etc/env.php
  sed -i "${dbPassLine}i\\$defaultDbLine" app/etc/env.php

#V JOOMLA SPECIFIC STEPS:

elif [ $application = "Joomla" ]; then

#10.GET OLD DATABASE DETAILS:

  oldDbName=$( < configuration.php grep -m 1 "public \$db =" | cut -d \' -f 2 )
  oldDbUser=$( < configuration.php grep -m 1 "public \$user =" | cut -d \' -f 2 )
  oldDbHost=$( < configuration.php grep -m 1 "public \$host =" | cut -d \' -f 2 )

#11.UPDATE DATABASE DETAILS:

#11.1.MAKE A COPY OF ORIGINAL CONFIG FILE:

  cp configuration.php configuration.php.bk

#11.2.REPLACE DATABASE NAME USER AND HOSTNAME:

  sed -i "s/$oldDbName\\b/$db_name/g;s/$oldDbUser\\b/$db_name/g;s/$oldDbHost/localhost/g" configuration.php

#11.3.DELETE DB_PASS LINE AND REPLACE IT WITH PREDEFIEND.

  dbPassLine=$(grep -n 'password' configuration.php | cut -f1 -d:)
  defaultDbLine="        public \$password = '4eYJEq3KyZr5r1';"

  sed -e "${dbPassLine}d" -i configuration.php
  sed -i "${dbPassLine}i\\$defaultDbLine" configuration.php

#11.4.GET OLD DIRECTORY PATH:

  oldDocRoot=$( < configuration.php grep "public \$log_path =" | cut -d \' -f 2 | rev | cut -d '/' -f 3- | rev | sed 's_/_\\/_g' )
  newDocRoot=${doc_root//\//\\/}

 #VI PRESTASHOP 1.6 SPECIFIC STEPS:

#11.5.REPLACE DIRECTORY PATH IN CONFIG FILES:

  sed -i "s/$oldDocRoot/$newDocRoot/g" configuration.php

elif [ $application = 'PrestaShop1.6' ]; then

#10.GET OLD DATABASE DETAILS:

  oldDbName=$( < config/settings.inc.php grep -m 1 "_DB_NAME_" | cut -d \' -f 4 )
  oldDbUser=$( < config/settings.inc.php grep -m 1 "_DB_USER_" | cut -d \' -f 4 )
  oldDbHost=$( < config/settings.inc.php grep -m 1 "_DB_SERVER_" | cut -d \' -f 4 )

#11.UPDATE DATABASE DETAILS:

#11.1.MAKE A COPY OF ORIGINAL CONFIG FILE:

  cp config/settings.inc.php config/settings.inc.php.bk

#11.2.REPLACE DATABASE NAME USER AND HOSTNAME:

  sed -i "s/$oldDbName\\b/$db_name/g;s/$oldDbUser\\b/$db_name/g;s/$oldDbHost/localhost/g" config/settings.inc.php

#11.3.DELETE DB_PASS LINE AND REPLACE IT WITH PREDEFIEND.

  dbPassLine=$(grep -n '_DB_PASSWD_' config/settings.inc.php | cut -f1 -d:)
  defaultDbLine="define('_DB_PASSWD_', '4eYJEq3KyZr5r1');"

  sed -e "${dbPassLine}d" -i config/settings.inc.php
  sed -i "${dbPassLine}i\\$defaultDbLine" config/settings.inc.php

#VII PRESTASHOP 1.7 SPECIFIC STEPS:

elif [ $application = 'PrestaShop1.7' ]; then

#10.GET OLD DATABASE DETAILS:

  oldDbName=$( < app/config/parameters.php grep -m 1 'database_name' | cut -d \' -f 4 )
  oldDbUser=$( < app/config/parameters.php grep -m 1 'database_user' | cut -d \' -f 4 )
  oldDbHost=$( < app/config/parameters.php grep -m 1 'database_host' | cut -d \' -f 4 )

#11.UPDATE DATABASE DETAILS:

#11.1.MAKE A COPY OF ORIGINAL CONFIG FILE:

  cp app/config/parameters.php app/config/parameters.php.bk

#11.2.REPLACE DATABASE NAME USER AND HOSTNAME:

  sed -i "s/$oldDbName\\b/$db_name/g;s/$oldDbUser\\b/$db_name/g;s/$oldDbHost/localhost/g" app/config/parameters.php

#11.3.DELETE DB_PASS LINE AND REPLACE IT WITH PREDEFIEND.

  dbPassLine=$(grep -n 'database_password' app/config/parameters.php | cut -f1 -d:)
  defaultDbLine="    'database_password' => '4eYJEq3KyZr5r1',"

  sed -e "${dbPassLine}d" -i app/config/parameters.php
  sed -i "${dbPassLine}i\\$defaultDbLine" app/config/parameters.php

else

  printf "$RED_COLOR" 'APPLICATION IS NOT RECOGNIZED. CONFIGURATION FILE NEEDS TO BE EDITED MANUALLY.'
  printf "$PURPLE_COLOR" 'DATABASE DETAILS:'
  printf "$PURPLE_COLOR" "DATABASE NAME: $db_name"
  printf "$PURPLE_COLOR" "DATABASE USER: $db_name"
  printf "$PURPLE_COLOR" "DATABASE PASS: $dbPass"

fi

#12.SEARCH FOR DATABASE DUMPS IN CURRENT DIRECTORY AND ASK WHICH DUMP TO IMPORT IF MORE THAN ONE:

find ./* -maxdepth 0 -name '*.sql' > temp.txt

numberOfLines=$(wc -l < temp.txt)

if [ "$numberOfLines" = 1 ]; then

  dbDump=$(cat temp.txt)

elif [ "$numberOfLines" = 0 ]; then

  printf "$RED_COLOR" 'NO SQL FILE FOUND IN CURRENT DIRECTORY. DATABASE NEEDS TO BE IMPORTED MANUALLY!'
  printf "$PURPLE_COLOR" 'DATABASE DETAILS:'
  printf "$PURPLE_COLOR" "DATABASE NAME: $db_name"
  printf "$PURPLE_COLOR" "DATABASE USER: $db_name"
  printf "$PURPLE_COLOR" "DATABASE PASS: $dbPass"

else

  cat temp.txt

  printf "$RED_COLOR" 'MORE THAN ONE SQL FILE FOUND!'
  read -e -r -p $'\e[36mTYPE THE NAME OF THE FILE TO IMPORT:\e[0m ' dbDump;

#12.1.CHECK IF SQL FILE EXISTS AND ASK FOR INPUT UNTIL EXISTING SQL FILE IS PROVIDED:

  while [ ! -f "$dbDump" ]; do

    printf "$RED_COLOR" 'INVALID SQL FILE!'
    read -e -r -p $'\e[36mTYPE THE NAME OF THE FILE AGAIN:\e[0m ' dbDump;

  done

fi

#13.CHECK IF CREATE DATABASE LINE EXISTS AND REMOVE IT:

if [ "$numberOfLines" != 0 ]; then
  if grep -q 'CREATE DATABASE' "$dbDump"; then

    line=$(grep -nm1 'CREATE DATABASE' "$dbDump" | cut -d '\:' -f 1)
    line2=$((line+1))
    sed -i.bk -e "${line},${line2}d" "$dbDump"
  fi
fi

#14.IMPORT DATABASE AND SHOW IF DATABASE HAS BEEN IMPORTED SUCCESSFULLY:

 ImportErrors=1

if [ "$numberOfLines" != 0 ]; then

  printf "$YELLOW_COLOR" 'IMPORTING DATABASE.'

  mysql -u "$db_name" -p"$dbPass" "$db_name" < "$dbDump" 2>&1 | grep -v 'Warning: Using a password' > temp.txt

  ImportErrors=$(wc -l temp.txt | cut -d ' ' -f 1 )

  if [ "$ImportErrors" -eq 0 ]; then

   printf "$GREEN_COLOR" 'DATABASE IMPORTED.'

  else

   printf "$RED_COLOR" 'DATABASE WAS NOT IMPORTED SUCCESSFULLY DUE TO THE FOLLOWING ERROR:'

   cat temp.txt

   printf "$RED_COLOR" 'DATABASE NEEDS TO BE IMPORTED MANUALLY!'

  fi
fi

#15.FIX PERMISSIONS AND PRINT WHEN PERMISSIONS ARE FIXED:

printf "$YELLOW_COLOR" 'FIXING PERMISSIONS.'

find . -type d -exec chmod 755 {} \; && find . -type f -exec chmod 644 {} \;

if [ -f bin/magento ]; then

  chmod 755 bin/magento

fi

printf "$GREEN_COLOR" 'PERMISSIONS FIXED.'

#16.MOVE FILES TO ROOT DIRECTORY OF THE DOMAIN AND SHOW WHERE THE FILES WERE MOVED:

currentPath=$(pwd)

if [ "$currentPath" != "$doc_root" ]; then

  if [ ! -d "$doc_root" ]; then

    mkdir -p "$doc_root"

  fi

  mv ./* .[^.]* "$doc_root"

  printf "$GREEN_COLOR" "FILES MOVED TO $doc_root"

  cd "$doc_root" || exit

fi

#17.CHECK IF CURRENT DOMAIN IN DATABASE IS DIFFERENT FROM INPUT DOMAIN AND ASK IF SEARCH AND REPLACE SHOULD BE PERFORMED:

#I.WORDPRESS SPECIFIC STEPS:

#17.1.CHECK IF WP CLI IS WORKING:

if [ $application = 'WordPress' ]; then

  tablePrefix=$( < wp-config.php grep -m 1 table_prefix | cut -d \' -f 2 )
  tablePrefixCLI=$(wp db prefix)
  wpCliWorking="y"

  if [ "$tablePrefix" != "$tablePrefixCLI" ]; then

    wpCliWorking='n'
    printf "$RED_COLOR" 'WP CLI IS NOT WORKING'

  fi
fi
replaceDb="n"
wwwInputDomain=www."$input_domain"

#17.2.CHECK IF SQL FILE WAS FOUND AND IF DB WAS SUCCESSFULLY IMPORTED:
if [ "$numberOfLines" != 0 ] && [ "$ImportErrors" -eq 0 ] && [ $application = 'WordPress' ] && [ $wpCliWorking = 'y' ]; then

   oldDomain=$(wp option get siteurl | cut -d '/' -f 3-)

#17.3.CHECK IF INPUT DOMAIN MATCHES THE DOMAIN IN THE DATABASE:
  if [ "$input_domain" != "$oldDomain" ] && [ "$wwwInputDomain" != "$oldDomain" ] && [ ! -z "$oldDomain" ]; then

     printf "$RED_COLOR" "OLD DOMAIN: $oldDomain IS DIFFERENT FROM CURRENT DOMAIN: $input_domain!"
     read -e -r -p $'\e[36mWould you like to perform search and replace? (y/n):\e[0m ' replaceDb;

    if [ "$replaceDb" = 'y' ]; then

       printf "$YELLOW_COLOR" 'PERFORMING SEARCH AND REPLACE.'

       replace=$(wp search-replace "$oldDomain" "$input_domain" | grep Success: | cut -d ' ' -f 3)

      if [ ! -z "$replace" ]; then

        printf "$GREEN_COLOR" "SEARCH AND REPLACE SUCCESSFULLY COMPLETED. $replace REPLACEMENTS WERE MADE."

	  else

	   printf "$RED_COLOR" 'SEARCH AND REPLACE WAS NOT SUCCESSFULLY COMPLETED!'

      fi

    else

       printf "$RED_COLOR" 'SEARCH AND REPLACE WAS NOT PERFORMED!'

    fi
  fi
fi

# II.OPENCART SPECIFIC STEPS:

replaceDb='n'
wwwInputDomain=www."$input_domain"

# 17.1.CHECK IF SQL FILE WAS FOUND AND IF DB WAS SUCCESSFULLY IMPORTED:

if [ "$numberOfLines" != 0 ] && [ "$ImportErrors" -eq 0 ] && [ $application = 'OpenCart' ]; then

oldDomain=$( < config.php grep HTTP_SERVER | cut -d '/' -f 3- | rev | cut -d '/' -f 2- | rev )

  if [ "$input_domain" != "$oldDomain" ] && [ "$wwwInputDomain" != "$oldDomain" ] && [ ! -z "$oldDomain" ]; then

#17.3.CHECK IF INPUT DOMAIN MATCHES THE DOMAIN IN THE CONFIG FILE:

printf "$RED_COLOR" "OLD DOMAIN: $oldDomain IS DIFFERENT FROM CURRENT DOMAIN: $input_domain!"
     read -e -r -p $'\e[36mWould you like for the Domain value in the config files to be replaced? (y/n):\e[0m ' replaceDb;

    if [ "$replaceDb" = "y" ]; then

	  oldURL=${oldDomain//\//\\/}
	  newURl=${input_domain//\//\\/}

	  sed -i "s/$oldURL/$newURl/g" config.php
	  sed -i "s/$oldURL/$newURl/g" admin/config.php

	  replacedURL=$( < config.php grep HTTP_SERVER | cut -d '/' -f 3- | rev | cut -d '/' -f 2- | rev )

	  if [ "$replacedURL" = "$input_domain" ]; then

	    printf "$GREEN_COLOR" 'DOMAIN VALUE SUCCESSFULLY REPLACED.'

	  else

	    printf "$GREEN_COLOR" 'DOMAIN VALUE WAS NOT REPLACED!'

	  fi

	else

       printf "$RED_COLOR" 'DOMAIN VALUE WAS NOT REPLACED!'

    fi
  fi
fi

#18.GET SERVER HOSTNAME AND IP_ADDRESS:

ip_address=$(/bin/hostname -i)
hostname=$(/bin/hostname)

#19.WGET PROPAGATION AND TEMPLATE FILES:

wget -q https://files.wowmania.net/propagation.txt && chmod 644 propagation.txt

if [ "$replaceDb" = 'y' ]; then

   wget -q https://files.wowmania.net/template-search-replace.txt && mv template-search-replace.txt template.txt && chmod 644 template.txt

else

   wget -q https://files.wowmania.net/template.txt && chmod 644 template.txt

fi

if [ -f propagation.txt ] && [ -f template.txt ]; then

   printf "$GREEN_COLOR" 'PROPAGATION AND TEMPLATE FILES DOWNLOADED.'

else

   printf "$RED_COLOR" 'PROPAGATION AND TEMPLATE FILES CANNOT BE DOWNLOADED!'

fi

#20. PRINT HOSTS FILE LINE, PROPAGATION AND REPLY TEMPLATE LINKS:

printf "$CYAN_COLOR" 'HOSTS FILE LINE:'
printf "$PURPLE_COLOR" "$ip_address $domain_name www.$domain_name"

if [ -f propagation.txt ] && [ -f template.txt ]; then

  printf "$CYAN_COLOR" 'LINK TO propagation.txt FILE:'
  printf "$PURPLE_COLOR" "$input_domain/propagation.txt"

  replaceOldDomain=${oldDomain//\//\\/}
  replaceInputDomain=${input_domain//\//\\/}
  sed -i "s/OLDURL/$replaceOldDomain/g;s/NEWURL/$replaceInputDomain/g;s/DOMAIN/$domain_name/g;s/HOSTNAME/$hostname/g;s/IP_ADDRESS/$ip_address/g" template.txt

  printf "$CYAN_COLOR" 'LINK TO TEMPLATE:'
  printf "$PURPLE_COLOR" "$input_domain/template.txt"

fi

printf "$GREEN_COLOR" 'THE DEPLOYMENT OF THE WEBSITE HAS BEEN COMPLETED.'

#21.DELETE TEMPORARY FILES:

read -e -r -p $'\e[36mDELETE SCRIPT AND TEMPORARY FILES?(y/n):\e[0m ' delete;

if [ "$delete" = 'y' ]; then

  rm -rf transfer.sh temp.txt template.txt

  printf "$GREEN_COLOR" 'TEMPORARY FILES REMOVED.'

else

  printf "$RED_COLOR" 'TEMPORARY FILES WERE NOT REMOVED!'

fi
