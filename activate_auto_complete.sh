#!/bin/bash
#echo "Your script args ($#) are: $@"

# Enable bash completion in zsh
if [[ -n $ZSH_VERSION ]]; then
  echo "Enabling bash completion in zsh"
  autoload -U +X compinit && compinit
  autoload -U +X bashcompinit && bashcompinit
fi

_release_completions() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    opts="--help --debug --source --target --gate --version --build --apply --keep --forceddl"

    case "${prev}" in
        --source|--target|--gate)
            local branches=$(git branch --format='%(refname:short)')
            COMPREPLY=( $(compgen -W "${branches}" -- ${cur}) )
            return 0
            ;;
        --version)
            local versions="major minor patch current"
            COMPREPLY=( $(compgen -W "${versions}" -- ${cur}) )
            return 0
            ;;
        *)
            COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
            return 0
            ;;
    esac
}

_release_completions_zsh() {
    compadd `_release_completions`
} 
if [[ -n $ZSH_VERSION ]]; then
  complete -C _release_completions_zsh ./release.sh
else
  complete -F _release_completions ./release.sh
fi