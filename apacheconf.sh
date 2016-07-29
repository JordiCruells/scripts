#!/bin/bash
cp /etc/apache2/apache2.conf ${HOME}/.backups/apache2.conf
vim ${HOME}/.backups/apache2.conf
git_path="--git-dir=/home/jordi/.backups/.git --work-tree=//home/jordi/.backups/"
git $git_path update-index -q --refresh
CHANGES=$(git $git_path diff-index --name-only HEAD --)
if [ -n "$CHANGES" ]; then
    read -p 'Commit message: ' message
    git $git_path add .
    git $git_path commit -m "$message | $CHANGES at $(date +%Y-%m-%d-%H:%M:%S.%N)"
    sudo cp ${HOME}/.backups/apache2.conf /etc/php5/apache2/apache2.conf
    read -p "Restart Apache ? (y|n) " restart
    if [[ "$restart" =~ ^[yY]{1,1}$ ]];then
       sudo service apache2 restart
    fi
fi
