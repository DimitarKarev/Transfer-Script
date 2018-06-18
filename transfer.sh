#!/bin/bash

#1.CONSTANTS FOR COLORS:

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

    cpanel_user=$( /scripts/whoowns "$domain_name" )

    if [ ! -z "$cpanel_user" ]; then

      doc_root=$( uapi --user="$cpanel_user"  DomainInfo single_domain_data domain="$domain_name" | grep 'documentroot:' | cut -d ' ' -f 6 )

    fi

  else

    doc_root=$( uapi DomainInfo single_domain_data domain="$domain_name" | grep 'documentroot:' | cut -d ' ' -f 6 )

  fi

  if [ ! -z "$sub_folder" ]; then

    doc_root=${doc_root}/${sub_folder}

  fi

  ((counter++))

done

#3.GET CPANEL USERNAME AND CUT IT TO 8 CHARS IF LONGER:

if [ -z "$cpanel_user" ]; then

  cpanel_user=$( uapi DomainInfo single_domain_data domain="$domain_name" | grep 'user:' | cut -d ' ' -f 6 )

fi

cpanel_user_length=${#cpanel_user}

if [ "$cpanel_user_length" -ge 8 ]; then

  cpanel_user=$( echo "$cpanel_user" | cut -c 1-8 )

fi

#4.CREATE DATABASE (CHECK IF DATABASE EXISTS AND IF YES CHANGE DATABASE_PREFIX UNTIL NEW DB CAN BE CREATED):

db_prefix_length=1
db_name_status=0
while [ "$db_name_status" -eq 0 ]; do

#4.1 GET DATABASE NAME PREFIX:

  db_prefix_length=$((db_prefix_length+1))
  db_prefix_value=$( echo "$domain_name" | cut -c 1-"$db_prefix_length" )

#4.2 REMOVE ALL INSTANCES OF '.' IN DATABASE NAME:

  db_name=${cpanel_user}_${db_prefix_value}
  db_name=${db_name//./}

#4.3 CREATE THE DATABASE:
  if [ "$current_user" = 'root' ]; then

    db_name_status=$( uapi --user="$cpanel_user" Mysql create_database name="$db_name" | grep 'status:' | cut -d ' ' -f 4 )

  else

    db_name_status=$( uapi Mysql create_database name="$db_name" | grep 'status:' | cut -d ' ' -f 4 )

  fi

done

printf "%sDATABASE CREATED.%s\\n" "$GREEN_COLOR" "$DEFAULT_COLOR"

db_pass='4eYJEq3KyZr5r1'

#5.CREATE DATABASE USER, ADD PRIVILIGES AND OUTPUT IF USER IS CREATED SUCCESSFULLY:

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

#6.CHECK APPLICATION AND DECLARE APPLICATION SPECIFIC VALUES:

separator=4
if [ -f wp-config.php ]; then

  application='WordPress'
  db_host_line='DB_HOST'
  db_name_line='DB_NAME'
  db_user_line='DB_USER'
  db_pass_line='DB_PASSWORD'
  default_db_line="define('DB_PASSWORD', '4eYJEq3KyZr5r1');"
  declare -a config_file=('wp-config.php')

elif [ -f config.php ] && [ -f admin/config.php ]; then

  application='OpenCart'
  db_host_line='DB_HOSTNAME'
  db_name_line='DB_DATABASE'
  db_user_line='DB_USERNAME'
  db_pass_line='DB_PASSWORD'
  default_db_line="define('DB_PASSWORD', '4eYJEq3KyZr5r1');"
  declare -a config_file=('config.php' 'admin/config.php')

elif [ -f configuration.php ]; then

  application='Joomla'
  db_host_line='public \$host ='
  db_name_line='public \$db ='
  db_user_line='public \$user ='
  db_pass_line='public \$password'
  default_db_line="        public \$password = '4eYJEq3KyZr5r1';"
  declare -a config_file=('configuration.php')
  separator=2

elif [ -f app/etc/local.xml ]; then

  application='Magento1'
  db_host_line='<host>'
  db_name_line='<dbname>'
  db_user_line='<username>'
  db_pass_line='<password>'
  default_db_line="                    <password><![CDATA[4eYJEq3KyZr5r1]]  ></password>"
  declare -a config_file=('app/etc/local.xml')

elif [ -f app/etc/env.php ]; then

  application='Magento2'
  db_host_line='host'
  db_name_line='dbname'
  db_user_line='username'
  db_pass_line='password'
  default_db_line="        'password' => '4eYJEq3KyZr5r1',"
  declare -a config_file=('app/etc/env.php')

elif [ -f config/settings.inc.php ]; then

  application='PrestaShop1.6'
  db_host_line='_DB_NAME_'
  db_name_line='_DB_NAME_'
  db_user_line='_DB_USER_'
  db_pass_line='_DB_PASSWD_'
  default_db_line="define('_DB_PASSWD_', '4eYJEq3KyZr5r1');"
  declare -a config_file=('config/settings.inc.php')

elif [ -f app/config/parameters.php ]; then

  application='PrestaShop1.7'
  db_host_line='database_host'
  db_name_line='database_name'
  db_user_line='database_user'
  db_pass_line='database_password'
  default_db_line="    'database_password' => '4eYJEq3KyZr5r1',"
  declare -a config_file=('app/config/parameters.php')

else

  application='Other'

  printf "%sAPPLICATION IS NOT RECOGNIZED. CONFIGURATION FILE NEEDS TO BE EDITED MANUALLY!%s\\n" "$RED_COLOR" "$DEFAULT_COLOR"
  printf "%sDATABASE DETAILS:%s\\n" "$PURPLE_COLOR" "$DEFAULT_COLOR"
  printf "%sDATABASE NAME: %s%s\\n" "$PURPLE_COLOR" "$db_name" "$DEFAULT_COLOR"
  printf "%sDATABASE USER: %s%s\\n" "$PURPLE_COLOR" "$db_name" "$DEFAULT_COLOR"
  printf "%sDATABASE PASS: %s%s\\n" "$PURPLE_COLOR" "$db_pass" "$DEFAULT_COLOR"

fi

function Update_Config_File_Details
{

   n=0

  while [ "$n" != "${#config_file[@]}" ]; do

#GET OLD DB DETAILS:

    if [ "$application" = 'Magento1' ]; then

      old_db_host=$( < "${config_file[$n]}" grep -m 1 "$db_host_line" | cut -d '[' -f 3 | cut -d ']' -f 1 )
      old_db_name=$( < "${config_file[$n]}" grep -m 1 "$db_name_line" | cut -d '[' -f 3 | cut -d ']' -f 1 )
      old_db_user=$( < "${config_file[$n]}" grep -m 1 "$db_user_line" | cut -d '[' -f 3 | cut -d ']' -f 1 )

    else

      old_db_host=$( < "${config_file[$n]}" grep -m 1 "$db_host_line" | cut -d \' -f "$separator" )
      old_db_name=$( < "${config_file[$n]}" grep -m 1 "$db_name_line" | cut -d \' -f "$separator" )
      old_db_user=$( < "${config_file[$n]}" grep -m 1 "$db_user_line" | cut -d \' -f "$separator" )

    fi

      db_pass_line_num=$(grep -n "$db_pass_line" "${config_file[$n]}" | cut -f1 -d:)

#MAKE A COPY OF ORIGINAL CONFIG FILE:

    cp "${config_file[$n]}" "${config_file[$n]}.bk"

#REPLACE DATABASE NAME USER AND HOSTNAME:

    sed -i "s/$old_db_name\\b/$db_name/g;s/$old_db_user\\b/$db_name/g;s/$old_db_host/localhost/g" "${config_file[$n]}"

#DELETE DB_PASS LINE AND REPLACE IT WITH PREDEFIEND.

    sed -e "${db_pass_line_num}d" -i "${config_file[$n]}"
    sed -i "${db_pass_line_num}i\\$default_db_line" "${config_file[$n]}"

    ((n++))

  done

}

if [ "$application" != 'Other' ]; then

  Update_Config_File_Details

fi

#7. ADDITIONAL APPLICATION SPECIFIC STEPS:

if [ "$application" = 'WordPress' ]; then

#7.1 FIX PATHS IN wp-config.php, wordfence-waf.php, .user.ini AND .htaccess FILES:

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

    old_path=$( < .htaccess grep -m 1 RewriteBase | sed 's/^ *//' | cut -d ' ' -f 2 | sed 's_/_\\/_g' )

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

elif [ "$application" = 'OpenCart' ]; then

#7.2 GET OLD DIRECTORY PATH:

  old_doc_root=$( < config.php grep -m 1 DIR_APPLICATION | cut -d \' -f 4 | rev | cut -d '/' -f 3- | rev | sed 's_/_\\/_g' )
  new_doc_root=${doc_root//\//\\/}

#8.5.REPLACE DIRECTORY PATH IN CONFIG FILES:

  sed -i "s/$old_doc_root/$new_doc_root/g" config.php admin/config.php

# IV.MAGENTO 2 SPECIFIC STEPS:

#8.4.ADD CRON JOBS:

  if [ "$current_user" = 'root' ]; then

    {
    echo "2,17,32,55 * * * * /usr/local/bin/php ${doc_root}/update/cron.php >> ${doc_root}/var/log/update.cron.log >/dev/null 2>&1"
    echo "7,27,40,49 * * * * cd ${doc_root}/bin && ./magento setup:cron:run >> ${doc_root}/var/log/setup.cron.log >/dev/null 2>&1"
    echo "13,21,36,56 * * * * cd ${doc_root}/bin && ./magento cron:run | grep -v 'Ran jobs by schedule' >> ${doc_root}/var/log/magento.cron.log >/dev/null 2>&1"
    } >> /var/spool/cron/"$cpanel_user"

  else

    crontab -l > mycrons
    {
    echo "2,17,32,55 * * * * /usr/local/bin/php ${doc_root}/update/cron.php >> ${doc_root}/var/log/update.cron.log >/dev/null 2>&1"
    echo "7,27,40,49 * * * * cd ${doc_root}/bin && ./magento setup:cron:run >> ${doc_root}/var/log/setup.cron.log >/dev/null 2>&1"
    echo "13,21,36,56 * * * * cd ${doc_root}/bin && ./magento cron:run | grep -v 'Ran jobs by schedule' >> ${doc_root}/var/log/magento.cron.log >/dev/null 2>&1"
    } >> mycrons
    crontab mycrons
    rm -rf mycrons

  fi

#V JOOMLA SPECIFIC STEPS:

elif [ "$application" = 'Joomla' ]; then

#8.4.GET OLD DIRECTORY PATH:

  old_doc_root=$( < configuration.php grep "public \$tmp_path =" | cut -d \' -f 2 | rev | cut -d '/' -f 2- | rev | sed 's_/_\\/_g' )
  new_doc_root=${doc_root//\//\\/}

#7.5.REPLACE DIRECTORY PATH IN CONFIG FILES:

  sed -i "s/$old_doc_root/$new_doc_root/g" configuration.php

fi

#9.SEARCH FOR DATABASE DUMPS IN CURRENT DIRECTORY AND ASK WHICH DUMP TO IMPORT IF MORE THAN ONE:

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

#9.1.CHECK IF SQL FILE EXISTS AND ASK FOR INPUT UNTIL EXISTING SQL FILE IS PROVIDED:

  while [ ! -f "$db_dump" ]; do

    if [ ! -z "$db_dump" ]; then

      printf "%sINVALID SQL FILE!%s\\n" "$RED_COLOR" "$DEFAULT_COLOR"

    fi

    read -e -r -p $'\e[36mTYPE THE NAME OF THE SQL FILE:\e[0m ' db_dump;

  done
fi

#10.CHECK IF CREATE DATABASE LINE EXISTS AND REMOVE IT:

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

#10.IMPORT DATABASE AND SHOW IF DATABASE HAS BEEN IMPORTED SUCCESSFULLY:

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

#11.MOVE FILES TO ROOT DIRECTORY OF THE DOMAIN AND SHOW WHERE THE FILES WERE MOVED:

current_path=$( pwd )

if [ "$current_path" != "$doc_root" ]; then

  if [ ! -d "$doc_root" ]; then

    if [ "$current_user" = 'root' ]; then

      sudo -u $cpanel_user mkdir -p "$doc_root"

    else

      mkdir -p "$doc_root"

    fi
  fi

  mv ./* .[^.]* "$doc_root"

  printf "%sFILES MOVED TO: %s%s\\n" "$GREEN_COLOR" "$doc_root" "$DEFAULT_COLOR"

  cd "$doc_root" || exit

fi

#12.FIX OWNDERSHIP AND PERMISSIONS AND PRINT WHEN PERMISSIONS ARE FIXED:

if [ "$current_user" = 'root' ]; then

  chown "${cpanel_user}": ./* .[^.]* -R

fi

printf "%sFIXING PERMISSIONS.%s\\n" "$YELLOW_COLOR" "$DEFAULT_COLOR"

find . -type d -print0 | xargs -0 chmod 0755 && find . -type f -print0 | xargs -0 chmod 0644

if [ -f bin/magento ]; then

  chmod 755 bin/magento

fi

printf "%sPERMISSIONS FIXED.%s\\n" "$GREEN_COLOR" "$DEFAULT_COLOR"

#13.CHECK IF CURRENT DOMAIN IN DATABASE IS DIFFERENT FROM INPUT DOMAIN AND ASK IF SEARCH AND REPLACE SHOULD BE PERFORMED:

www_input_domain=www."$input_domain"

#I.WORDPRESS SPECIFIC STEPS:

#13.1. CHECK IF WP CLI IS INSTALLED AND INSTALL IT IF NEEDED:

if [ "$application" = 'WordPress' ] && [ "$current_user" = 'root' ] && [ ! -f /user/local/bin/wp ]; then

  curl -s -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar 2>/dev/null && chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp

  if [ -f /user/local/bin/wp ]; then

    printf "%sWP CLI INSTALLED.%s\\n" "$GREEN_COLOR" "$DEFAULT_COLOR"

  fi
fi

#13.2.CHECK IF WP CLI IS WORKING:

if [ "$application" = 'WordPress' ] && [ "$number_of_sql_files" != 0 ] && [ -z "$import_error" ] ; then

  db_table_prefix=$( < wp-config.php grep -m 1 table_prefix | cut -d \' -f 2 )

  if [ "$current_user" = 'root' ]; then

    db_table_prefix_cli=$( wp db prefix --allow-root )

  else

    db_table_prefix_cli=$( wp db prefix )

  fi

  wp_cli_working='yes'

  if [ "$db_table_prefix" != "$db_table_prefix_cli" ]; then

    wp_cli_working='no'
    printf "%sWP CLI IS NOT WORKING!%s\\n" "$RED_COLOR" "$DEFAULT_COLOR"

  fi
fi

#13.3.CHECK IF SQL FILE WAS FOUND AND IF DB WAS SUCCESSFULLY IMPORTED:
if [ "$application" = 'WordPress' ] && [ "$number_of_sql_files" != 0 ] && [ -z "$import_error" ] && [ "$wp_cli_working" = 'yes' ]; then

  if [ "$current_user" = 'root' ]; then

    old_domain=$( wp option get siteurl --allow-root | cut -d '/' -f 3- )

  else

    old_domain=$( wp option get siteurl | cut -d '/' -f 3- )

  fi

  old_domain_www=$( echo "$old_domain" | cut -d '.' -f 1 )

  if [ "$old_domain_www" = 'www' ]; then

    input_domain=$www_input_domain

  fi

#13.4.CHECK IF INPUT DOMAIN MATCHES THE DOMAIN IN THE DATABASE:
  if [ "$input_domain" != "$old_domain" ] && [ ! -z "$old_domain" ]; then

    printf "%sOLD DOMAIN: %s IS DIFFERENT FROM CURRENT DOMAIN: %s!%s\\n" "$RED_COLOR" "$old_domain" "$input_domain" "$DEFAULT_COLOR"

    while [[ "$replace_db" != 'y' && "$replace_db" != 'n' ]]; do

      read -e -r -p $'\e[36mWould you like to perform search and replace? (y/n):\e[0m ' replace_db;

      replace_db="${replace_db,,}"

    done

    if [ "$replace_db" = 'y' ]; then

       printf "%sPERFORMING SEARCH AND REPLACE.%s\\n" "$YELLOW_COLOR" "$DEFAULT_COLOR"

      if [ "$current_user" = 'root' ]; then

        replace=$( wp search-replace "$old_domain" "$input_domain" --allow-root | grep Success: | cut -d ' ' -f 3 )

      else

        replace=$( wp search-replace "$old_domain" "$input_domain" | grep Success: | cut -d ' ' -f 3 )

      fi

      old_url=${old_domain//\//\\/}
      new_url=${input_domain//\//\\/}

      sed -i "s/$old_url\\b/$new_url/g" wp-config.php

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

# 13.1.CHECK IF SQL FILE WAS FOUND AND IF DB WAS SUCCESSFULLY IMPORTED:

if [ "$number_of_sql_files" != 0 ] && [ -z "$import_error" ] && [ "$application" = 'OpenCart' ]; then

old_domain=$( < config.php grep HTTP_SERVER | cut -d '/' -f 3- | rev | cut -d '/' -f 2- | rev )

old_domain_www=$( echo "$old_domain" | cut -d '.' -f 1 )

  if [ "$old_domain_www" = 'www' ]; then

   input_domain=$www_input_domain

  fi

  if [ "$input_domain" != "$old_domain" ] && [ ! -z "$old_domain" ]; then

#13.3.CHECK IF INPUT DOMAIN MATCHES THE DOMAIN IN THE CONFIG FILE:

    printf "%sOLD DOMAIN: %s IS DIFFERENT FROM CURRENT DOMAIN: %s!%s\\n" "$RED_COLOR" "$old_domain" "$input_domain" "$DEFAULT_COLOR"

    while [[ "$replace_db" != 'y' && "$replace_db" != 'n' ]]; do

      read -e -r -p $'\e[36mWould you like for the Domain value in the config files to be replaced? (y/n):\e[0m ' replace_db;

      replace_db="${replace_db,,}"

    done

    if [ "$replace_db" = 'y' ]; then

      old_url=${old_domain//\//\\/}
      new_url=${input_domain//\//\\/}

      sed -i "s/$old_url/$new_url/g" config.php admin/config.php

      replaced_URL=$( < config.php grep HTTP_SERVER | cut -d '/' -f 3- | rev | cut -d '/' -f 2- | rev )

      if [ "$replaced_URL" = "$input_domain" ]; then

        printf "%sDOMAIN VALUE SUCCESSFULLY REPLACED.%s\\n" "$GREEN_COLOR" "$DEFAULT_COLOR"

      else

        printf "%sDOMAIN VALUE WAS NOT REPLACED!%s\\n" "$RED_COLOR" "$DEFAULT_COLOR"

      fi

    else

      printf "%sDOMAIN VALUE WAS NOT REPLACED!%s\\n" "$RED_COLOR" "$DEFAULT_COLOR"

    fi
  fi
fi

#14.GET SERVER HOSTNAME AND IP_ADDRESS:

ip_address=$(/bin/hostname -i)
hostname=$(/bin/hostname)

#15.WGET PROPAGATION AND TEMPLATE FILES:

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

#16. PRINT HOSTS FILE LINE, PROPAGATION AND REPLY TEMPLATE LINKS:

printf "%sHOSTS FILE LINE:%s\\n" "$CYAN_COLOR" "$DEFAULT_COLOR"
printf "%s%s %s www.%s%s\\n" "$PURPLE_COLOR" "$ip_address" "$domain_name" "$domain_name" "$DEFAULT_COLOR"

if [ -f propagation.txt ] && [ -f template.txt ]; then

  printf "%sLINK TO propagation.txt FILE:%s\\n" "$CYAN_COLOR" "$DEFAULT_COLOR"
  printf "%s%s/propagation.txt%s\\n" "$PURPLE_COLOR" "$input_domain" "$DEFAULT_COLOR"

  replace_old_domain=${old_domain//\//\\/}
  replace_input_domain=${input_domain//\//\\/}
  sed -i "s/OLDURL/$replace_old_domain/g;s/NEWURL/$replace_input_domain/g;s/DOMAIN/$domain_name/g;s/HOSTNAME/$hostname/g;s/IP_ADDRESS/$ip_address/g" template.txt

  printf "%sLINK TO TEMPLATE:%s\\n" "$CYAN_COLOR" "$DEFAULT_COLOR"
  printf "%s%s/template.txt%s\\n" "$PURPLE_COLOR" "$input_domain" "$DEFAULT_COLOR"

fi

printf "%sTHE DEPLOYMENT OF THE WEBSITE HAS BEEN COMPLETED.%s\\n" "$GREEN_COLOR" "$DEFAULT_COLOR"

#17.DELETE TEMPORARY FILES:

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
