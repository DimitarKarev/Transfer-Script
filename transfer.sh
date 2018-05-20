#!/bin/bash

# 1.VARIABLES FOR COLORS:

RED_COLOR=$'\033[31;1m'
GREEN_COLOR=$'\033[32;1m'
YELLOW_COLOR=$'\033[33;1m'
PURPLE_COLOR=$'\033[35;1m'
CYAN_COLOR=$'\033[36;1m'
DEFAULT_COLOR=$'\033[0m'

#2.INPUT DOMAIN NAME:

printf "%sTYPE THE DOMAIN NAME AND WATCH THE MAGIC HAPPEN!%s\\n" "$GREEN_COLOR" "$DEFAULT_COLOR"

#2.1.CHECK IF INPUT DOMAIN EXISTS AND ASK FOR INPUT UNTIL EXISTING DOMAIN IS PROVIDED:

current_user=$(whoami)
counter=0

while [ -z "$doc_root" ]; do

  if [ "$counter" != 0 ]; then

    printf "%sINVALID DOMAIN! TYPE THE DOMAIN AGAIN:%s\\n" "$RED_COLOR" "$DEFAULT_COLOR"

  fi

  read -e -r -p $'\e[36mDomain/Subdomain:\e[0m ' input_domain;

  #2.1.1.CONVERT INPUT TO LOWERCASE:

  input_domain="${input_domain,,}"

  #2.1.2.REMOVE ANY '/' AT THE END OF THE INPUT:

  last_char="${input_domain: -1}"

  while [ "$last_char" = '/' ]; do

  input_domain=${input_domain%?};
  last_char="${input_domain: -1}"

  done

  sub_folder=$( echo "${input_domain}" | cut -d '/' -s -f 2- )
  domain_name=$( echo "$input_domain" | cut -d '/' -f 1 )

  if [ "$current_user" = 'root' ]; then

    cpanel_user=$( /scripts/whoowns "$input_domain" )
    doc_root=$( uapi --user="$cpanel_user"  DomainInfo single_domain_data domain="$domain_name" | grep 'documentroot:' | cut -d ' ' -f 6 )

  else

    doc_root=$( uapi DomainInfo single_domain_data domain="$domain_name" | grep 'documentroot:' | cut -d ' ' -f 6 )

  fi

  if [ ! -z "$sub_folder" ]; then

    doc_root=${doc_root}/${sub_folder}

  fi

  ((counter++))

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

#4.GET CPANEL USERNAME AND CUT IT TO 8 CHARS IF LONGER:

if [ -z "$cpanel_user" ]; then

  cpanel_user=$( uapi DomainInfo single_domain_data domain="$domain_name" | grep 'user:' | cut -d ' ' -f 6 )

fi

cpanel_user_length=${#cpanel_user}

if [ "$cpanel_user_length" -ge 8 ]; then

  cpanel_user=$( echo "$cpanel_user" | cut -c 1-8 )

fi

#5.CREATE DATABASE (CHECK IF DATABASE EXISTS AND IF YES CHANGE DATABASE_PREFIX UNTIL NEW DB CAN BE CREATED):

db_prefix_length=1
db_name_status=0
while [ "$db_name_status" -eq 0 ]; do

#5.1 GET DATABASE NAME PREFIX:

  db_prefix_length=$((db_prefix_length+1))

  db_prefix_value=$( echo "$domain_name" | cut -c 1-"$db_prefix_length" )

#5.2 REMOVE ALL INSTANCES OF '.' IN DATABASE NAME:

  db_name=${cpanel_user}_${db_prefix_value}
  db_name=${db_name//./}

#5.3 CREATE THE DATABASE:
  if [ "$current_user" = 'root' ]; then

    db_name_status=$( uapi --user="$cpanel_user" Mysql create_database name="$db_name" | grep 'status:' | cut -d ' ' -f 4 )

  else

    db_name_status=$( uapi Mysql create_database name="$db_name" | grep 'status:' | cut -d ' ' -f 4 )

  fi

done

printf "%sDATABASE CREATED.%s\\n" "$GREEN_COLOR" "$DEFAULT_COLOR"

db_pass='4eYJEq3KyZr5r1'

#6.CREATE DATABASE USER, ADD PRIVILIGES AND OUTPUT IF USER IS CREATED SUCCESSFULLY:

if [ "$current_user" = 'root' ]; then

  db_user_status=$( uapi --user="$cpanel_user" Mysql create_user name="$db_name" password="$db_pass" | grep 'status:' | cut -d ' ' -f 4 )
  uapi --user="$cpanel_user" Mysql set_privileges_on_database user="$db_name" database="$db_name" privileges=ALL%20PRIVILEGES > /dev/null 2>&1

else

  db_user_status=$( uapi Mysql create_user name="$db_name" password="$db_pass" | grep 'status:' | cut -d ' ' -f 4 )
  uapi Mysql set_privileges_on_database user="$db_name" database="$db_name" privileges=ALL%20PRIVILEGES > /dev/null 2>&1

fi

if [ "$db_user_status" -eq 1 ]; then

  printf "%sDATABASE USER CREATED.%s\\n" "$GREEN_COLOR" "$DEFAULT_COLOR"

else

  printf "%sDATABASE USER NOT CREATED!%s\\n" "$RED_COLOR" "$DEFAULT_COLOR"

fi

#I.WORDPRESS SPECIFIC STEPS:

if [ "$application" = 'WordPress' ]; then

#7.GET OLD DATABASE DETAILS:

  old_db_name=$( < wp-config.php grep -m 1 DB_NAME | cut -d \' -f 4 )
  old_db_user=$( < wp-config.php grep -m 1 DB_USER | cut -d \' -f 4 )
  old_db_host=$( < wp-config.php grep -m 1 DB_HOST | cut -d \' -f 4 )

#8.UPDATE DATABASE DETAILS:

#8.1.MAKE A COPY OF ORIGINAL WP-CONFIG:

  cp wp-config.php wp-config.php.bk

#8.2.REPLACE DATABASE NAME USER AND HOSTNAME:

  sed -i "s/$old_db_name\\b/$db_name/g;s/$old_db_user\\b/$db_name/g;s/$old_db_host/localhost/g" wp-config.php

#8.3.DELETE DB_PASS LINE AND REPLACE IT WITH PREDEFIEND.

  db_pass_line=$( grep -n 'DB_PASSWORD' wp-config.php | cut -f1 -d: )

  default_db_line="define('DB_PASSWORD', '4eYJEq3KyZr5r1');"

  sed -e "${db_pass_line}d" -i wp-config.php
  sed -i "${db_pass_line}i\\$default_db_line" wp-config.php

#FIX PATHS IN wp-config.php, wordfence-waf.php, .user.ini AND .htaccess FILES:

  old_doc_root=$( < wp-config.php grep -m 1 WPCACHEHOME | sed 's/wp-content.*$/wp-content/' | rev | cut -d '/' -f2- | rev | cut -d \' -f 4 | sed 's_/_\\/_g' )
  new_doc_root=${doc_root//\//\\/}

  if [ ! -z "$old_doc_root" ]; then

    sed -i "s/$old_doc_root/$new_doc_root/g" wp-config.php

  fi

  if [ -f wordfence-waf.php ]; then
    if [ -z "$old_doc_root" ]; then

      old_doc_root=$( < wordfence-waf.php grep -m 1 define | sed 's/wp-content.*$/wp-content/' | rev | cut -d '/' -f2- | rev | cut -d \' -f 2 | sed 's_/_\\/_g' )

    fi

    sed -i "s/$old_doc_root/$new_doc_root/g" wordfence-waf.php

  fi

  if [ -f .user.ini ]; then
    if [ -z "$old_doc_root" ]; then

      old_doc_root=$( < .user.ini grep -m 1 auto_prepend_file | rev | cut  -d '/' -f 2- | rev | cut -d \' -f 2 | sed 's_/_\\/_g' )

    fi

	  if [ ! -z "$old_doc_root" ]; then

	  sed -i "s/$old_doc_root/$new_doc_root/g" .user.ini

	  fi
  fi

  if [ -f .htaccess ]; then

    cp .htaccess .htaccess.bk

    old_path=$( < .htaccess grep -m 1 RewriteBase | cut -d ' ' -f 2 | sed 's_/_\\/_g' )

    if [ -z "$sub_folder" ]; then

      new_path=$( echo / | sed 's_/_\\/_g' )

    else

     new_path=$( echo /"${sub_folder}"/ | sed 's_/_\\/_g' )

    fi

    sed -i "s/RewriteBase $old_path/RewriteBase $new_path/" .htaccess
    sed -i "s/RewriteRule \\. $old_path/RewriteRule \\. $new_path/" .htaccess

    if [ ! -z "$old_doc_root" ]; then

    sed -i "s/$old_doc_root/$new_doc_root/g" .htaccess

    fi
  fi

#II. OPENCART SPECIFIC STEPS:

elif [ "$application" = 'OpenCart' ]; then

#7.GET OLD DATABASE DETAILS:

  old_db_name=$( < config.php grep -m 1 DB_DATABASE | cut -d \' -f 4 )
  old_db_user=$( < config.php grep -m 1 DB_USERNAME | cut -d \' -f 4 )
  old_db_host=$( < config.php grep -m 1 DB_HOSTNAME | cut -d \' -f 4 )

#8.UPDATE DATABASE DETAILS:

#8.1.MAKE A COPY OF ORIGINAL CONFIG FILES:

  cp config.php config.php.bk
  cp admin/config.php admin/config.php.bk

#8.2.REPLACE DATABASE NAME USER AND HOSTNAME:

  sed -i "s/$old_db_name\\b/$db_name/g;s/$old_db_user\\b/$db_name/g;s/$old_db_host/localhost/g" config.php admin/config.php

#8.3.DELETE DB_PASS LINE AND REPLACE IT WITH PREDEFIEND IN CONFIG AND ADMIN/CONFIG FILES.

  default_db_line="define('DB_PASSWORD', '4eYJEq3KyZr5r1');"

  db_pass_line=$( grep -n 'DB_PASSWORD' config.php | cut -f1 -d: )

  sed -e "${db_pass_line}d" -i config.php
  sed -i "${db_pass_line}i\\$default_db_line" config.php

  db_pass_line=$( grep -n 'DB_PASSWORD' admin/config.php | cut -f1 -d: )

  sed -e "${db_pass_line}d" -i admin/config.php
  sed -i "${db_pass_line}i\\$default_db_line" admin/config.php

#8.4.GET OLD DIRECTORY PATH:

  old_doc_root=$( < config.php grep -m 1 DIR_APPLICATION | cut -d \' -f 4 | rev | cut -d '/' -f 3- | rev | sed 's_/_\\/_g' )
  new_doc_root=${doc_root//\//\\/}

#8.5.REPLACE DIRECTORY PATH IN CONFIG FILES:

  sed -i "s/$old_doc_root/$new_doc_root/g" config.php
  sed -i "s/$old_doc_root/$new_doc_root/g" admin/config.php

# III.MAGENTO 1 SPECIFIC STEPS:

elif [ "$application" = 'Magento1' ]; then

#7.GET OLD DATABASE DETAILS:

  old_db_name=$( < app/etc/local.xml grep -m 1 dbname | cut -d '[' -f 3 | cut -d ']' -f 1 )
  old_db_user=$( < app/etc/local.xml grep -m 1 username | cut -d '[' -f 3 | cut -d ']' -f 1 )
  old_db_host=$( < app/etc/local.xml grep -m 1 host | cut -d '[' -f 3 | cut -d ']' -f 1 )

#8.UPDATE DATABASE DETAILS:

#8.1.MAKE A COPY OF ORIGINAL CONFIG FILE:

  cp app/etc/local.xml app/etc/local.xml.bk

#8.2.REPLACE DATABASE NAME USER AND HOSTNAME:

  sed -i "s/$old_db_name\\b/$db_name/g;s/$old_db_user\\b/$db_name/g;s/$old_db_host/localhost/g" app/etc/local.xml

#8.3.DELETE DB_PASS LINE AND REPLACE IT WITH PREDEFIEND.

  db_pass_line=$( grep -n 'password' app/etc/local.xml | cut -f1 -d: )

  default_db_line="                    <password><![CDATA[4eYJEq3KyZr5r1]]></password>"

  sed -e "${db_pass_line}d" -i app/etc/local.xml
  sed -i "${db_pass_line}i\\$default_db_line" app/etc/local.xml

# IV.MAGENTO 2 SPECIFIC STEPS:

elif [ "$application" = 'Magento2' ]; then

#7.GET OLD DATABASE DETAILS:

  old_db_name=$( < app/etc/env.php grep -m 1 dbname | cut -d \' -f 4 )
  old_db_user=$( < app/etc/env.php grep -m 1 username | cut -d \' -f 4 )
  old_db_host=$( < app/etc/env.php grep -m 1 host | cut -d \' -f 4 )

#8.UPDATE DATABASE DETAILS:

#8.1.MAKE A COPY OF ORIGINAL CONFIG FILE:

  cp app/etc/env.php app/etc/env.php.bk

#8.2.REPLACE DATABASE NAME USER AND HOSTNAME:

  sed -i "s/$old_db_name\\b/$db_name/g;s/$old_db_user\\b/$db_name/g;s/$old_db_host/localhost/g" app/etc/env.php

#8.3.DELETE DB_PASS LINE AND REPLACE IT WITH PREDEFIEND.

  db_pass_line=$( grep -n 'password' app/etc/env.php | cut -f1 -d: )

  default_db_line="        'password' => '4eYJEq3KyZr5r1',"

  sed -e "${db_pass_line}d" -i app/etc/env.php
  sed -i "${db_pass_line}i\\$default_db_line" app/etc/env.php

#8.4.ADD CRON JOBS:

  if [ "$current_user" = 'root' ]; then

    {
    echo "2,17,32,55 * * * * /usr/local/bin/php ${doc_root}/update/cron.php >> ${doc_root}/var/log/update.cron.log"
    echo "7,27,40,49 * * * * cd ${doc_root}/bin && ./magento setup:cron:run >> ${doc_root}/var/log/setup.cron.log"
    echo "13,21,36,56 * * * * cd ${doc_root}/bin && ./magento cron:run | grep -v 'Ran jobs by schedule' >> ${doc_root}/var/log/magento.cron.log"
    } >> /var/spool/cron/"$cpanel_user"

  else

    crontab -l > mycrons
    {
    echo "2,17,32,55 * * * * /usr/local/bin/php ${doc_root}/update/cron.php >> ${doc_root}/var/log/update.cron.log"
    echo "7,27,40,49 * * * * cd ${doc_root}/bin && ./magento setup:cron:run >> ${doc_root}/var/log/setup.cron.log"
    echo "13,21,36,56 * * * * cd ${doc_root}/bin && ./magento cron:run | grep -v 'Ran jobs by schedule' >> ${doc_root}/var/log/magento.cron.log"
    } >> mycrons
    crontab mycrons
    rm -rf mycrons

  fi

#V JOOMLA SPECIFIC STEPS:

elif [ "$application" = 'Joomla' ]; then

#7.GET OLD DATABASE DETAILS:

  old_db_name=$( < configuration.php grep -m 1 "public \$db =" | cut -d \' -f 2 )
  old_db_user=$( < configuration.php grep -m 1 "public \$user =" | cut -d \' -f 2 )
  old_db_host=$( < configuration.php grep -m 1 "public \$host =" | cut -d \' -f 2 )

#8.UPDATE DATABASE DETAILS:

#8.1.MAKE A COPY OF ORIGINAL CONFIG FILE:

  cp configuration.php configuration.php.bk

#8.2.REPLACE DATABASE NAME USER AND HOSTNAME:

  sed -i "s/$old_db_name\\b/$db_name/g;s/$old_db_user\\b/$db_name/g;s/$old_db_host/localhost/g" configuration.php

#8.3.DELETE DB_PASS LINE AND REPLACE IT WITH PREDEFIEND.

  db_pass_line=$( grep -n 'password' configuration.php | cut -f1 -d: )
  default_db_line="        public \$password = '4eYJEq3KyZr5r1';"

  sed -e "${db_pass_line}d" -i configuration.php
  sed -i "${db_pass_line}i\\$default_db_line" configuration.php

#8.4.GET OLD DIRECTORY PATH:

  old_doc_root=$( < configuration.php grep "public \$log_path =" | cut -d \' -f 2 | rev | cut -d '/' -f 3- | rev | sed 's_/_\\/_g' )
  new_doc_root=${doc_root//\//\\/}

#7.5.REPLACE DIRECTORY PATH IN CONFIG FILES:

  sed -i "s/$old_doc_root/$new_doc_root/g" configuration.php

 #VI PRESTASHOP 1.6 SPECIFIC STEPS:

elif [ "$application" = 'PrestaShop1.6' ]; then

#8.GET OLD DATABASE DETAILS:

  old_db_name=$( < config/settings.inc.php grep -m 1 "_DB_NAME_" | cut -d \' -f 4 )
  old_db_user=$( < config/settings.inc.php grep -m 1 "_DB_USER_" | cut -d \' -f 4 )
  old_db_host=$( < config/settings.inc.php grep -m 1 "_DB_SERVER_" | cut -d \' -f 4 )

#8.UPDATE DATABASE DETAILS:

#8.1.MAKE A COPY OF ORIGINAL CONFIG FILE:

  cp config/settings.inc.php config/settings.inc.php.bk

#8.2.REPLACE DATABASE NAME USER AND HOSTNAME:

  sed -i "s/$old_db_name\\b/$db_name/g;s/$old_db_user\\b/$db_name/g;s/$old_db_host/localhost/g" config/settings.inc.php

#8.3.DELETE DB_PASS LINE AND REPLACE IT WITH PREDEFIEND.

  db_pass_line=$( grep -n '_DB_PASSWD_' config/settings.inc.php | cut -f1 -d: )
  default_db_line="define('_DB_PASSWD_', '4eYJEq3KyZr5r1');"

  sed -e "${db_pass_line}d" -i config/settings.inc.php
  sed -i "${db_pass_line}i\\$default_db_line" config/settings.inc.php

#VII PRESTASHOP 1.7 SPECIFIC STEPS:

elif [ "$application" = 'PrestaShop1.7' ]; then

#7.GET OLD DATABASE DETAILS:

  old_db_name=$( < app/config/parameters.php grep -m 1 'database_name' | cut -d \' -f 4 )
  old_db_user=$( < app/config/parameters.php grep -m 1 'database_user' | cut -d \' -f 4 )
  old_db_host=$( < app/config/parameters.php grep -m 1 'database_host' | cut -d \' -f 4 )

#8.UPDATE DATABASE DETAILS:

#8.1.MAKE A COPY OF ORIGINAL CONFIG FILE:

  cp app/config/parameters.php app/config/parameters.php.bk

#8.2.REPLACE DATABASE NAME USER AND HOSTNAME:

  sed -i "s/$old_db_name\\b/$db_name/g;s/$old_db_user\\b/$db_name/g;s/$old_db_host/localhost/g" app/config/parameters.php

#8.3.DELETE DB_PASS LINE AND REPLACE IT WITH PREDEFIEND.

  db_pass_line=$( grep -n 'database_password' app/config/parameters.php | cut -f1 -d: )
  default_db_line="    'database_password' => '4eYJEq3KyZr5r1',"

  sed -e "${db_pass_line}d" -i app/config/parameters.php
  sed -i "${db_pass_line}i\\$default_db_line" app/config/parameters.php

else

  application='Other'

  printf "%sAPPLICATION IS NOT RECOGNIZED. CONFIGURATION FILE NEEDS TO BE EDITED MANUALLY!%s\\n" "$RED_COLOR" "$DEFAULT_COLOR"
  printf "%sDATABASE DETAILS:%s\\n" "$PURPLE_COLOR" "$DEFAULT_COLOR"
  printf "%sDATABASE NAME: %s%s\\n" "$PURPLE_COLOR" "$db_name" "$DEFAULT_COLOR"
  printf "%sDATABASE USER: %s%s\\n" "$PURPLE_COLOR" "$db_name" "$DEFAULT_COLOR"
  printf "%sDATABASE PASS: %s%s\\n" "$PURPLE_COLOR" "$db_pass" "$DEFAULT_COLOR"

fi

#12.SEARCH FOR DATABASE DUMPS IN CURRENT DIRECTORY AND ASK WHICH DUMP TO IMPORT IF MORE THAN ONE:

read -r -a sql_files <<< "$(find ./* -maxdepth 0 -name '*.sql' | cut -d '/' -f 2- | tr '\n' ' ')"

number_of_sql_files=${#sql_files[@]}

if [ "$number_of_sql_files" -eq 1 ]; then

  db_dump=${sql_files[0]}

elif [ "$number_of_sql_files" -eq 0 ]; then

  printf "%sNO SQL FILE FOUND IN CURRENT DIRECTORY. DATABASE NEEDS TO BE IMPORTED MANUALLY!%s\\n" "$RED_COLOR" "$DEFAULT_COLOR"

  if [ "$application" != 'Other' ]; then

    printf "%sDATABASE DETAILS:%s\\n" "$PURPLE_COLOR" "$DEFAULT_COLOR"
    printf "%sDATABASE NAME: %s%s\\n" "$PURPLE_COLOR" "$db_name" "$DEFAULT_COLOR"
    printf "%sDATABASE USER: %s%s\\n" "$PURPLE_COLOR" "$db_name" "$DEFAULT_COLOR"
    printf "%sDATABASE PASS: %s%s\\n" "$PURPLE_COLOR" "$db_pass" "$DEFAULT_COLOR"

  fi

else

  printf "%sMORE THAN ONE SQL FILE FOUND!%s\\n" "$RED_COLOR" "$DEFAULT_COLOR"
  printf "%s\\n" "${sql_files[@]}"

#12.1.CHECK IF SQL FILE EXISTS AND ASK FOR INPUT UNTIL EXISTING SQL FILE IS PROVIDED:

  while [ ! -f "$db_dump" ]; do

  if [ ! -z "$db_dump" ]; then

    printf "%sINVALID SQL FILE!%s\\n" "$RED_COLOR" "$DEFAULT_COLOR"

  fi

    read -e -r -p $'\e[36mTYPE THE NAME OF THE SQL FILE:\e[0m ' db_dump;

  done
fi

#13.CHECK IF CREATE DATABASE LINE EXISTS AND REMOVE IT:

if [ "$number_of_sql_files" != 0 ]; then
  if grep -q 'CREATE DATABASE' "$db_dump"; then

    create_db_line_num=$( grep -nm1 'CREATE DATABASE' "$db_dump" | cut -d ':' -f 1 )
    use_line_num=$((create_db_line_num+1))
    use_line_value=$(sed "${use_line_num}q;d" "$db_dump")

    if echo "$use_line_value" | grep -q 'USE' ; then

      sed -i.bk -e "${create_db_line_num},${use_line_num}d" "$db_dump"

    else

      sed -i.bk -e "${create_db_line_num}d" "$db_dump"

    fi
  fi
fi

#14.IMPORT DATABASE AND SHOW IF DATABASE HAS BEEN IMPORTED SUCCESSFULLY:

if [ "$number_of_sql_files" != 0 ]; then

  printf "%sIMPORTING DATABASE.%s\\n" "$YELLOW_COLOR" "$DEFAULT_COLOR"

  import_error=$( mysql -u "$db_name" -p"$db_pass" "$db_name" < "$db_dump" 2>&1 | grep -v 'Warning: Using a password' )

  if [ -z "$import_error" ]; then

    printf "%sDATABASE IMPORTED.%s\\n" "$GREEN_COLOR" "$DEFAULT_COLOR"

  else

    printf "%sDATABASE WAS NOT IMPORTED SUCCESSFULLY DUE TO THE FOLLOWING ERROR:%s\\n" "$RED_COLOR" "$DEFAULT_COLOR"
    printf "%s%s%s\\n" "$RED_COLOR" "$import_error" "$DEFAULT_COLOR"
    printf "%sDATABASE NEEDS TO BE IMPORTED MANUALLY!%s\\n" "$RED_COLOR" "$DEFAULT_COLOR"

  fi
fi

#15.FIX PERMISSIONS AND PRINT WHEN PERMISSIONS ARE FIXED:

printf "%sFIXING PERMISSIONS.%s\\n" "$YELLOW_COLOR" "$DEFAULT_COLOR"

find . -type d -print0 | xargs -0 chmod 0755 && find . -type f -print0 | xargs -0 chmod 0644

if [ -f bin/magento ]; then

  chmod 755 bin/magento

fi

printf "%sPERMISSIONS FIXED.%s\\n" "$GREEN_COLOR" "$DEFAULT_COLOR"

#16.MOVE FILES TO ROOT DIRECTORY OF THE DOMAIN AND SHOW WHERE THE FILES WERE MOVED:

currentPath=$(pwd)

if [ "$currentPath" != "$doc_root" ]; then

  if [ ! -d "$doc_root" ]; then

    mkdir -p "$doc_root"

  fi

  mv ./* .[^.]* "$doc_root"

  printf "%sFILES MOVED TO: %s%s\\n" "$GREEN_COLOR" "$doc_root" "$DEFAULT_COLOR"

  cd "$doc_root" || exit

fi

#17.CHECK IF CURRENT DOMAIN IN DATABASE IS DIFFERENT FROM INPUT DOMAIN AND ASK IF SEARCH AND REPLACE SHOULD BE PERFORMED:

replace_db="n"
www_input_domain=www."$input_domain"

#I.WORDPRESS SPECIFIC STEPS:

#17.1. CHECK IF WP CLI IS INSTALLED AND INSTALL IT IF NEEDED:

if [ "$application" = 'WordPress' ] && [ "$current_user" = 'root' ] && [ ! -f /user/local/bin/wp ]; then

  curl -s -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar 2>/dev/null && chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp

  if [ -f /user/local/bin/wp ]; then

    printf "%sWP CLI INSTALLED.%s\\n" "$GREEN_COLOR" "$DEFAULT_COLOR"

  fi
fi

#17.2.CHECK IF WP CLI IS WORKING:

if [ "$application" = 'WordPress' ] && [ "$number_of_sql_files" != 0 ] && [ -z "$import_error" ] ; then

  db_table_prefix=$( < wp-config.php grep -m 1 table_prefix | cut -d \' -f 2 )
  db_table_prefix_cli=$(wp db prefix)
  wp_cli_working='yes'

  if [ "$db_table_prefix" != "$db_table_prefix_cli" ]; then

    wp_cli_working='no'
    printf "%sWP CLI IS NOT WORKING!%s\\n" "$RED_COLOR" "$DEFAULT_COLOR"

  fi
fi

#17.3.CHECK IF SQL FILE WAS FOUND AND IF DB WAS SUCCESSFULLY IMPORTED:
if [ "$application" = 'WordPress' ] && [ "$number_of_sql_files" != 0 ] && [ -z "$import_error" ] && [ "$wp_cli_working" = 'yes' ]; then

   old_domain=$( wp option get siteurl | cut -d '/' -f 3- )
   old_domain_www=$( echo "$old_domain" | cut -d '.' -f 1)

  if [ "$old_domain_www" = 'www' ]; then

    input_domain=$www_input_domain

  fi

#17.4.CHECK IF INPUT DOMAIN MATCHES THE DOMAIN IN THE DATABASE:
  if [ "$input_domain" != "$old_domain" ] && [ "$www_input_domain" != "$old_domain" ] && [ ! -z "$old_domain" ]; then

    printf "%sOLD DOMAIN: %s IS DIFFERENT FROM CURRENT DOMAIN: %s!%s\\n" "$RED_COLOR" "$old_domain" "$input_domain" "$DEFAULT_COLOR"

    while [[ "$replace_db" != 'y' && "$replace_db" != 'n' ]]; do

      read -e -r -p $'\e[36mWould you like to perform search and replace? (y/n):\e[0m ' replace_db;

      replace_db="${replace_db,,}"

    done

    if [ "$replace_db" = 'y' ]; then

       printf "%sPERFORMING SEARCH AND REPLACE.%s\\n" "$YELLOW_COLOR" "$DEFAULT_COLOR"

       replace=$( wp search-replace "$old_domain" "$input_domain" | grep Success: | cut -d ' ' -f 3 )

      if [ ! -z "$replace" ]; then

        printf "%sSEARCH AND REPLACE SUCCESSFULLY COMPLETED. %s REPLACEMENTS WERE MADE.%s\\n" "$GREEN_COLOR" "$replace" "$DEFAULT_COLOR"

	  else

	   printf "%sSEARCH AND REPLACE WAS NOT SUCCESSFULLY COMPLETED!%s\\n" "$RED_COLOR" "$DEFAULT_COLOR"

      fi

    else

       printf "%sSEARCH AND REPLACE WAS NOT PERFORMED!%s\\n" "$RED_COLOR" "$DEFAULT_COLOR"

    fi
  fi
fi

# II.OPENCART SPECIFIC STEPS:

# 17.1.CHECK IF SQL FILE WAS FOUND AND IF DB WAS SUCCESSFULLY IMPORTED:

if [ "$number_of_sql_files" != 0 ] && [ -z "$import_error" ] && [ "$application" = 'OpenCart' ]; then

old_domain=$( < config.php grep HTTP_SERVER | cut -d '/' -f 3- | rev | cut -d '/' -f 2- | rev )

old_domain_www=$( echo "$old_domain" | cut -d '.' -f 1)

  if [ "$old_domain_www" = 'www' ]; then

   input_domain=$www_input_domain

  fi

  if [ "$input_domain" != "$old_domain" ] && [ "$www_input_domain" != "$old_domain" ] && [ ! -z "$old_domain" ]; then

#17.3.CHECK IF INPUT DOMAIN MATCHES THE DOMAIN IN THE CONFIG FILE:

    printf "%sOLD DOMAIN: %s IS DIFFERENT FROM CURRENT DOMAIN: %s!%s\\n" "$RED_COLOR" "$old_domain" "$input_domain" "$DEFAULT_COLOR"
    read -e -r -p $'\e[36mWould you like for the Domain value in the config files to be replaced? (y/n):\e[0m ' replace_db;

    replace_db="${replace_db,,}"

    if [ "$replace_db" = 'y' ]; then

      old_url=${old_domain//\//\\/}
      new_url=${input_domain//\//\\/}

      sed -i "s/$old_url/$new_url/g" config.php
      sed -i "s/$old_url/$new_url/g" admin/config.php

      replacedURL=$( < config.php grep HTTP_SERVER | cut -d '/' -f 3- | rev | cut -d '/' -f 2- | rev )

      if [ "$replacedURL" = "$input_domain" ]; then

        printf "%sDOMAIN VALUE SUCCESSFULLY REPLACED.%s\\n" "$GREEN_COLOR" "$DEFAULT_COLOR"

      else

        printf "%sDOMAIN VALUE WAS NOT REPLACED!%s\\n" "$RED_COLOR" "$DEFAULT_COLOR"

      fi

    else

      printf "%sDOMAIN VALUE WAS NOT REPLACED!%s\\n" "$RED_COLOR" "$DEFAULT_COLOR"

    fi
  fi
fi

#18.GET SERVER HOSTNAME AND IP_ADDRESS:

ip_address=$(/bin/hostname -i)
hostname=$(/bin/hostname)

#19.WGET PROPAGATION AND TEMPLATE FILES:

wget -q https://files.wowmania.net/propagation.txt && chmod 644 propagation.txt

if [ "$replace_db" = 'y' ]; then

   wget -q https://files.wowmania.net/template-search-replace.txt && mv template-search-replace.txt template.txt && chmod 644 template.txt

else

   wget -q https://files.wowmania.net/template.txt && chmod 644 template.txt

fi

if [ -f propagation.txt ] && [ -f template.txt ]; then

   printf "%sPROPAGATION AND TEMPLATE FILES DOWNLOADED.%s\\n" "$GREEN_COLOR" "$DEFAULT_COLOR"

else

   printf "%sPROPAGATION AND TEMPLATE FILES CANNOT BE DOWNLOADED!%s\\n" "$RED_COLOR" "$DEFAULT_COLOR"

fi

# FIX OWNERSHIP:

if [ "$current_user" = 'root' ]; then

  chown "${cpanel_user}": ./* .[^.]* -R

fi

#20. PRINT HOSTS FILE LINE, PROPAGATION AND REPLY TEMPLATE LINKS:

printf "%sHOSTS FILE LINE:%s\\n" "$CYAN_COLOR" "$DEFAULT_COLOR"
printf "%s%s %s www.%s%s\\n" "$PURPLE_COLOR" "$ip_address" "$domain_name" "$domain_name" "$DEFAULT_COLOR"

if [ -f propagation.txt ] && [ -f template.txt ]; then

  printf "%sLINK TO propagation.txt FILE:%s\\n" "$CYAN_COLOR" "$DEFAULT_COLOR"
  printf "%s%s/propagation.txt%s\\n" "$PURPLE_COLOR" "$input_domain" "$DEFAULT_COLOR"

  replace_old_domain=${old_domain//\//\\/}
  replace_input_domain=${input_domain//\//\\/}
  sed -i "s/old_url/$replace_old_domain/g;s/new_url/$replace_input_domain/g;s/DOMAIN/$domain_name/g;s/HOSTNAME/$hostname/g;s/IP_ADDRESS/$ip_address/g" template.txt

  printf "%sLINK TO TEMPLATE:%s\\n" "$CYAN_COLOR" "$DEFAULT_COLOR"
  printf "%s%s/template.txt%s\\n" "$PURPLE_COLOR" "$input_domain" "$DEFAULT_COLOR"

fi

printf "%sTHE DEPLOYMENT OF THE WEBSITE HAS BEEN COMPLETED.%s\\n" "$GREEN_COLOR" "$DEFAULT_COLOR"

#21.DELETE TEMPORARY FILES:

while [[ "$delete" != 'y' && "$delete" != 'n' ]]; do

  read -e -r -p $'\e[36mDelete Temporary Files? (y/n):\e[0m ' delete;

  delete="${delete,,}"

done

if [ "$delete" = 'y' ]; then

  rm -rf transfer.sh template.txt

  printf "%sTEMPORARY FILES REMOVED.%s\\n" "$GREEN_COLOR" "$DEFAULT_COLOR"

else

  printf "%sTEMPORARY FILES WERE NOT REMOVED!%s\\n" "$RED_COLOR" "$DEFAULT_COLOR"

fi
