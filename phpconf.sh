#!/bin/bash
cp /etc/php5/apache2/php.ini ${HOME}/.backups/php.ini
vim ${HOME}/.backups/php.ini
git_path="--git-dir=/home/jordi/.backups/.git --work-tree=//home/jordi/.backups/"
git $git_path update-index -q --refresh
CHANGES=$(git $git_path diff-index --name-only HEAD --)
if [ -n "$CHANGES" ]; then
    read -p 'Commit message: ' message
    git $git_path add .
    git $git_path commit -m "$message | $CHANGES at $(date +%Y-%m-%d-%H:%M:%S.%N)"
    sudo cp ${HOME}/.backups/php.ini /etc/php5/apache2/php.ini
    read -p "Restart Apache ? (y|n) " restart
    if [[ "$restart" =~ ^[yY]{1,1}$ ]];then
       sudo service apache2 restart
    fi
fi
