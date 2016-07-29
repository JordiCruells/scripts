#!/bin/bash

tmp_dir=$(echo "$HOME/scripts/.wpinstall/tmp/")
backup_dir=$(echo "$HOME/scripts/.wpinstall/backups/$(date +%Y-%m-%d-%H:%M:%S.%N)/")
wordpress_file='latest.tar.gz'
wordpress_url='https://wordpress.org/'
salts='https://api.wordpress.org/secret-key/1.1/salt/'
str_db='database_name_here'
str_wordpress_user='username_here'
str_wordpress_password='password_here'
str_server='localhost'
str_charset='utf8'
str_collation="'DB_COLLATE', ''"
str_repl_collation="'DB_COLLATE', '${collation}'"
msg_log=""

source "$HOME/scripts/.wpinstall/options"

function replace() {
    sed -i -e "s/$1/$2/g" $3
}

if [ "$1" = "" ];then
 config_file="$HOME/scripts/.wpinstall/local"
else
 config_file=".wpinstall/${1}"
fi

if [ -f $config_file ];then
  echo -e "Creating a new Wordpress site using the following configuration from ${config_file}:"

  source "$config_file"
  message=""
  echo -e "****************************************"
  for cfg_var in "${config_vars[@]}"
  do
    eval val="\${$cfg_var}"
    echo -e "   $cfg_var : $val"
    if [ -z ${val+x} ]; then
       message="${message}\n  --> ${cfg_var} is unset"
    fi
  done
  echo -e "****************************************"

  if [ "$message" != "" ];then
    echo -e "\nSome parameters were unset:${message}"
    exit
  else
   while true; do
    read -p "Proceed ? (y|n) " proceed
    case "$proceed" in
        y|Y)
            break
            ;;
        n|N)
            exit
            ;;
    esac
   done
  fi
else
  echo -e "\nFile ${config_file} is missing. The process is aborted."
  exit;
fi

while true; do
    read -p "Enter database name: " db_name
    if [[ $db_name =~ $regex_db ]]; then
       break;
    else
       echo "Wrong database name. Must match: $regex_db";
    fi
done

while true; do

    while true; do
      echo -e "Web server subdirectory. Options:\n - dot ('.') =>  no subdirectory\n - ENTER => '$db_name'\n - a text containing a-z, 0-9 or _ characters "
      read dir
      case "$dir" in
         .)
           dir=""
           break
           ;;
         "")
           dir="$db_name"
           break
           ;;
         *)
           if [[ $dir =~ $regex_dir ]]; then
              break
           else
              echo "Wrong directory name. Must match: $regex_dir";
           fi
      esac
    done

    #advice when a directory exists and is not empty
    if [ -d $working_dir$dir ] && [ "$(ls -A $working_dir$dir)" != "" ];then
        while true; do
          read -p "The directory $working_dir$dir is not empty. The existing files would be removed and backed up, do you want to continue ? (y|n) " overwrite_folder
          case "$overwrite_folder" in
            y|Y)
              break 2
              ;;
            n|N)
              break
          esac
        done
    else
      break
    fi

done

read -p "Site name (default is ${dir} ): " site_name
if [ "$site_name" == "" ];then
  site_name=$dir
fi

if [ -f $apache_vhosts_file ];then
  read -p "Site url (default is www.${dir}.local): " site_url
  if [ "$site_url" == "" ];then
    site_url="www.${dir}.local"
  fi
fi

echo -e "\nCreting database $prefix_database$db_name ...";
query="CREATE DATABASE ${prefix_database}${db_name} CHARACTER SET $charset COLLATE $collation; GRANT ALL PRIVILEGES ON ${prefix_database}${db_name}.* TO ${db_wp_user}@localhost; FLUSH PRIVILEGES;"
mysql_cmd="mysql --user=\"$db_user\" --password=\"$db_password\" --execute=\"$query\" 2>&1"
eval mysql_msg="\$($mysql_cmd)"


if [ "$mysql_msg" == "" ];then
   echo "Done."
else
   arr=($mysql_msg)
   #if database already exists request confirmation and make a dump of existing database
   if [ "${arr[1]}" == "1007" ];then
     query="DROP DATABASE ${prefix_database}${db_name}; $query"
     while true; do
       read -p "Database $prefix_database$db_name already exists. Do you want to overwrite it (the current data will be backed up and deleted) ? (y|n) " overwrite_db
        case "$overwrite_db" in
          y|Y)
             mkdir -p "$backup_dir"
             mysqldump --user="$db_user" --password="$db_password" $prefix_database$db_name > "${backup_dir}${prefix_database}${db_name}.sql"
             exit_code=$?
	     if [ $exit_code -ne 0 ] ; then
                echo "The mysql dump of database ${prefix_database}${db_name} failed with exit code $exit_code. You should remove this database manually before continuing."
                exit
             else
                msg_log="${msg_log}\n * The mysql dump of database ${prefix_database}${db_name} has been stored into the file ${backup_dir}${prefix_database}${db_name}.sql"
             fi
             mysql --user="$db_user" --password="$db_password" --execute="$query"
             if [ "$?" -eq 0 ];then
                 echo "Done."
                 break
              else
                 exit
              fi
              ;;
          n|N)
              exit
              ;;
        esac
     done
   else
     echo "$mysql_msg"
     exit
   fi
fi


#* DOWNLOAD WORDPRESS AND CHANGE COFIG IN wp-config
echo -e "\nDownloading Wordpress ...";
rm ${tmp_dir}{.,}* 2> /dev/null
rm -rf ${tmp_dir}wordpress
wget $wordpress_url$wordpress_file --directory-prefix=$tmp_dir
tar -xzf $tmp_dir$wordpress_file -C $tmp_dir
rm $tmp_dir$wordpress_file
echo "Done."

echo -e '\nWriting configuration file ...'
config_sample="${tmp_dir}wordpress/wp-config-sample.php"
config="${tmp_dir}wordpress/wp-config.php"
cp $config_sample $config
replace $str_db $prefix_database$db_name $config
replace $str_wordpress_user $db_wp_user $config
replace $str_wordpress_password $db_wp_password $config
replace $str_server $server $config
replace $str_charset $charset $config
replace "$str_collation" "$str_repl_collation" $config
SALT=$(curl -L https://api.wordpress.org/secret-key/1.1/salt/)
STRING='put your unique phrase here'
printf '%s\n' "g/$STRING/d" a "$SALT" . w | ed -s $config
echo "Done."

echo -e '\nCreating default .htaccess file'
cp "$HOME/scripts/.wpinstall/wp-htaccess" ${tmp_dir}wordpress/.htaccess
echo 'Done'

# Add special folders (.design, .backups)
mkdir ${tmp_dir}wordpress/design
mkdir ${tmp_dir}wordpress/backups

# INSTALLING WORDPRESS CORE (db)
#wp db create --path="$dir" (already created using mysql)
echo -e '\nInstalling Wordpress...'
wp core install --url="http://localhost/$dir" --title="$site_name" --admin_user="$wp_user" --admin_password="$wp_password" --admin_email="$wp_email" --path="${tmp_dir}wordpress"
echo "Done."

# INSTALLING PLUGINS
echo -e "\nSelect which plugins you want to add."
plugins=()
for plugin in "${plugins_ask[@]}"
do
  while true
  do
    read -p "Install $plugin ? (y|n) " install
    case $install in
      y|Y)
         plugins=(${plugins[@]} $plugin)
         break;
         ;;
      n|N)
         break;
         ;;
    esac
  done
done

echo -e "Installing plugins..."
for plugin in "${plugins[@]}"
do
  wp plugin install $plugin --activate --path="${tmp_dir}wordpress"
done

# INSTALLING A THEME
count=0
echo -e "\nSelect a theme to install from the following list:"
for theme in "${themes_ask[@]}";do
   echo "(${count}) ${theme}: ${themes_desc[$count]}"
   (( count ++ ))
done
while true;do
  read -p "Enter the theme number (or hit ENTER to bypass): " theme_n
  if [[ "$theme_n" =~ ^[0-9]$ ]] && [ $theme_n -lt $count ];then
    break;
  fi
  if [ "$theme_n" == "" ];then
    theme_num=-1
    break
  fi
done

if [ $theme_n -ge 0 ];then
  wp theme install ${themes_url[$theme_n]} --activate --path="${tmp_dir}wordpress"
fi


# COPYING TO WORKING DIRECTORY AN LINKING TO SERVER DIRECTORY
echo -e '\nCopying files to working directory and linking to the server directory'
if [ -n ${overwrite_folder} ];then
  if [ "$overwrite_folder" == "Y" ] || [ "$overwrite_folder" == "y" ]; then
    # make a backup of the final before removing it
    mv ${working_dir}${dir} ${backup_dir}${dir}
    msg_log="${msg_log}\n * All files in directory ${working_dir}${dir} have been backed up into ${backup_dir}${dir}"
  fi
fi
mkdir -p $working_dir$dir
mv ${tmp_dir}wordpress/{.,}* $working_dir$dir 2>/dev/null
rmdir ${tmp_dir}wordpress
ln -s $working_dir$dir $server_dir$dir
echo "Done."

echo -n -e "\n\e[32mFinished OK"
if [ "$msg_log" != "" ];then
  echo " with some warnings:"
  echo -e "$msg_log"
else
  echo "."
fi
echo -e "\e[39m"

echo -e '\nGiving permissions to special directories ...'
uploads_dir="${working_dir}${dir}/wp-content/uploads"
plugins_dir="${working_dir}${dir}/wp-content/plugins"
wp_admin_dir="${working_dir}${dir}/wp-admin"
sudo chmod 775 $uploads_dir --silent
sudo chmod 775 $plugins_dir --silent
sudo chown $web_user $uploads_dir --silent
sudo chown $web_user $plugins_dir --silent
sudo chown $web_user -R $wp_admin_dir --silent
sudo chown $web_user ${working_dir}${dir}/.htaccess --silent
echo "Done."

# CONFIGURE AND INIT GIT
echo -e "\nCreating git repository"
# Create .gitignore
cp "$HOME/scripts/.wpinstall/wp-gitignore" ${working_dir}${dir}/.gitignore
#Append installed plugins to .gitignore
for plugin in "${plugins[@]}"
do
  echo "wp-content/plugins/${plugin}" >> ${working_dir}${dir}/.gitignore
done
git_path="--git-dir=${working_dir}${dir}/.git --work-tree=${working_dir}${dir}"

git init ${working_dir}${dir} &> /dev/null
git ${git_path} add .gitignore &> /dev/null
git ${git_path} commit -m "Added .gitignore" &> /dev/null
git $git_path add . &> /dev/null
git $git_path commit -m "New Wordpress install" &> /dev/null
echo 'Done'

# CONFIGURE VIRTUAL HOST
if [ -f $apache_vhosts_file ];then

  echo -e "\nChanging file $apache_vhosts_file, adding lines: "
  sudo tee --append $apache_vhosts_file <<EOF
# Auto-configuration generated by wpinstall.sh at $(date +%Y-%m-%d-%H:%M:%S)
<VirtualHost *:80>
  DocumentRoot "/var/www/html/$dir"
  ServerName ${site_url}
</VirtualHost>
# End of auto-configuration
EOF
  echo -e "\nChanging file $hosts_file, adding line:"
  sudo tee --append $hosts_file <<EOF
127.0.0.1	${site_url}
EOF
  echo 'Done'
  echo -e "\nRestarting Apache ..."
  sudo service apache2 restart
  url="http://${site_url}"

else
  url="http://$ip/$dir"
fi

# RESUME INSTALLATION
echo -e "\nProject publicated at $url"
read -p "Do you want to open a browser ? (y|n) " open
if [[ "$open" =~ ^[yY]{1,1}$ ]];then
  if which gnome-open > /dev/null; then
    gnome-open $url
  elif which xdg-open > /dev/null; then
    xdg-open $url
  elif [ -n $BROWSER ]; then
    $BROWSER $url
  else
    echo "Could not detect the web browser to use."
  fi
fi
