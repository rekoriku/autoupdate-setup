## Quick start: run autoupdate.sh safely (Linux/WSL)
1) Place the script on a Linux-owned path (avoid /mnt/c):  
   ```bash
   sudo cp /mnt/c/tools/TEST/autoupdate.sh /usr/local/sbin/autoupdate.sh
   sudo chown root:root /usr/local/sbin/autoupdate.sh
   sudo chmod 755 /usr/local/sbin/autoupdate.sh   # no group/other write
   ```
2) Run it:  
   ```bash
   sudo /usr/local/sbin/autoupdate.sh
   ```
3) Verify success:  
   - Logs: `sudo tail -n 50 /var/log/unattended-upgrades/setup.log`  
   - Dry-run log: `/var/log/unattended-upgrades/dryrun.log`  
   - Configs: `/etc/apt/apt.conf.d/50unattended-upgrades`, `/etc/apt/apt.conf.d/20auto-upgrades`  
   - Sudoers (if NOPASSWD enabled): `sudo visudo -cf /etc/sudoers.d/autoupdate`  
   - Recent installs: `grep -hE "upgrade |install " /var/log/dpkg.log* | tail -n 20`  
   - Service/timers: `systemctl status unattended-upgrades` and `systemctl list-timers '*apt*'`
   - Check `ytl-linux-digabi2`:  
     - Version: `apt-cache policy ytl-linux-digabi2` and `dpkg -s ytl-linux-digabi2 | grep -E '^(Package|Version)'`  
     - Recent actions: `grep -h "ytl-linux-digabi2" /var/log/dpkg.log* | tail -n 5`  
     - If candidate > installed (from `apt-cache policy`), an update is pending.
4) Optional test run:  
   - Manual dry-run: `sudo unattended-upgrade --dry-run --debug | head -n 50`  
   - Check logs after the script:  
     `sudo tail -n 50 /var/log/unattended-upgrades/setup.log`  
     `sudo tail -n 50 /var/log/unattended-upgrades/dryrun.log`  
4) Check timers in local time:  
   - `systemctl list-timers --all --no-pager` (NEXT column is local time)  
   - `systemctl list-timers '*apt*'` (APT-related timers)  
   - `timedatectl` (shows local TZ)  
   - For a specific TZ: `TZ=Europe/Helsinki systemctl list-timers --all --no-pager`
5) Adjust the unattended upgrade time:  
   - Automatic reboot time (already set by the script): edit `REBOOT_TIME` and rerun the script, or edit `/etc/apt/apt.conf.d/50unattended-upgrades` `Unattended-Upgrade::Automatic-Reboot-Time "HH:MM";`  
   - To change the apt upgrade timer itself, create a systemd override:  
     ```bash
     sudo systemctl edit apt-daily-upgrade.timer
     # Add under [Timer], e.g.:
     # OnCalendar=*-*-* 03:30
     # RandomizedDelaySec=30m
     sudo systemctl daemon-reload
     sudo systemctl restart apt-daily-upgrade.timer
     ```

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

### Helper script
You can automate the above with `scripts/gh_push_template.sh`. Fill or export the placeholders (`PROJECT_DIR`, `REPO_NAME`, `GIT_USER_NAME`, `GIT_USER_EMAIL`) and run it from WSL.

### Same commands invoked from Windows shell via WSL
If you run these from PowerShell/CMD and want WSL to execute them in the project root (adjust the path as needed):

```
wsl --cd /mnt/c/tools/TEST sudo apt-get update && sudo apt-get install -y gh
wsl --cd /mnt/c/tools/TEST env BROWSER='cmd.exe /C start' gh auth login -w --hostname github.com --git-protocol https
wsl --cd /mnt/c/tools/TEST git init
wsl --cd /mnt/c/tools/TEST git config user.name "YourName"
wsl --cd /mnt/c/tools/TEST git config user.email "you@example.com"
wsl --cd /mnt/c/tools/TEST git add autoupdate.sh tests/test_autoupdate.py OHJE.md
wsl --cd /mnt/c/tools/TEST git commit -m "Add autoupdate script, doc, and tests"
wsl --cd /mnt/c/tools/TEST gh repo create autoupdate-setup --public --source . --remote origin --push
```

