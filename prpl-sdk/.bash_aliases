parse_git_branch() {
  [ -d .git ] && git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/(\1)/';
}

if [ -n "$(which git)" ];
then
  export PS1='\u@\h:\[\e[32m\]\w \[\e[91m\]$(parse_git_branch)\[\e[00m\]'$'\n$ ';
else
  export PS1='\u@\h:\[\e[32m\]\w \[\e[91m\]\[\e[00m\]'$'\n$ ';
fi

alias h='history';
alias git-pull='git pull --recurse-submodules';
alias vi='vim';
alias dist-upgrade='apt update && apt -y dist-upgrade && apt -y autopurge && apt -y autoclean';
alias cls='clear';
alias md='mkdir -p';

cd "${HOME}";
