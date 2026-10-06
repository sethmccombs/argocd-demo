#!/use/bin/bash

# used to obtain the latest ArgoCD manifest

# change this to modify the path to argocd's install YAML
manifest_path='https://github.com/argoproj/argo-cd/blob/stable/manifests/install.yaml'

# curl stuff from github

# if no version given, pull latest and extract tag

# if version given, pull that tag

# copy to version dir in ./argocd/$VERSION

