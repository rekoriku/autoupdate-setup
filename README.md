## How to push from WSL to GitHub with `gh`

Use this flow to publish from WSL without exposing personal data (replace placeholder values as needed):

1) Install GitHub CLI: `sudo apt-get update && sudo apt-get install -y gh`
2) Authenticate (opens Windows browser):  
   `env BROWSER='cmd.exe /C start' gh auth login -w --hostname github.com --git-protocol https`  
   Copy the code, press Enter to open the browser, paste code, approve.  
   If web auth is blocked, generate a GitHub PAT with `repo` and `read:org` scopes and run:  
   `gh auth login --with-token` (paste the token when prompted).  
   Token creation page: https://github.com/settings/tokens (choose “Classic”, add `repo` + `read:org`).
3) Initialize repo (inside your project):  
   `git init`  
   `git config user.name "YourName"`  
   `git config user.email "you@example.com"`
4) Stage and commit:  
   `git add autoupdate.sh tests/test_autoupdate.py OHJE.md`  
   `git commit -m "Add autoupdate script, doc, and tests"`
5) Create a public repo and push:  
   `gh repo create autoupdate-setup --public --source . --remote origin --push`

After this, future changes can be pushed with the usual `git add ...`, `git commit ...`, `git push`.

