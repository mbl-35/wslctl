v2.3.4:
* Allow to set WSLCTL environment variable to set Wslctl Data Path
* Add upgrade command

v2.3.2:
* #27: [FONC] Change password policy
* #25: Restore: error Could not set /lib/init/wsl-distro-name.sh
* #26: Create: alpine user creation error when no password specified
* #19: Display error wslctl ls when no distribution (no changes)
* #10: [BUILD] missing ADD shell command
* #9: [BUILD] Copy should set recusive

v2.3.1:
* #25 : restore error on setting wsl-distro-name

v2.3.0:
* Allow to set user password on creation (vs hard coded default) - option `--pwd=`
* Remove build option (unused) from help

v2.2.5:
* Alpine: init_user bug, sudo group not created
* Alpine: init_user pref : install only if requiered shadow/sudo
* Alpine: remove message 'WARNING: Ignoring https://dl-cdn.alpinelinux.org/alpine/v3.16/main: No such file or directory'

v2.2.4:
* [ISSUE#24] Rename existing instance
* Change hostname on rename
* Add internal exec as root (after instance creation)

v2.2.3:
* [ISSUE#22] Optimize subprocess wsl result (new instance not found)
* Adjust wsl instance name not valid ([a-z0-9-]*)
* [ISSUE#23] Display help when no command set

v2.2.2:
* [BUG] wsl host name truncated on unspecified instance name creation
* [optim] Optimize subprocess wsl result
* [BUG] add 'No instance set' when nothing in wsl lists

v2.2.1:
* [OPTIM] Mark system requierements (check once)

v2.2.0:
* [ISSUE#18] Default user creation error on Alpine
* [BUG] start action on alpine not working
* [EvVOL] Manage wsl output list as object (no more strings)
* [ISSUE#19] Display error wslctl ls when no distributions
* [EVOL] Auto-detect connect shell (i.e. allowing alpine)
* [EVOL] Provide wsl-setup.ps1 script to install/update wsl kernel
* [EVOL] Add wslctl requirements check before all
* [EVOL] Fedup with PS module cache: refactor to build a single file script for runtime
* [EVOL] move resource files to ~/files and get a FileUtils method to find them
* [EVOL] remove Invoque-Build usage and generate a make.ps1 builder
* [REVERT] src/bootstrap.ps1 to src/wslctl.ps1
* [EVOL] Changes Github CI

v2.1.7:
* [BUG] init_val is CRLF after build production: assert wsl file is LF only
* [BUG] !/usr/bin/env sh not interpreted on ubuntu => !/bin/sh

v2.1.6:
* [EVOL] /usr/local/bin/ini_val to manage /etc/wsl.conf properties
* [EVOL] Set the wsl hostname with the wsl instance name on creation
* [ISSUE#15] Default User creation error on ubuntu 22.04
* [ISSUE#17] Custom custom module refresh on each execution (dynamic manage module names cache)
* [EVOL] Add editor config
* [ISSUE#8] logout on wsl required Ctrl+C to exit - not reproduced

v2.1.5:
* [ISSUE#8] logout on wsl required Ctrl+C to exit
* [ISSUE#14] check cached archive uptodate by computing with registry referenced hash (eg latest tag)
* [BUG] typo Dowload -> Download

v2.1.4:
* [EVOL] allow to have remote archive file defined in registries

v2.1.3:
* [BUG] display error with instance list when only one (string array)

v2.1.2:
* [EVOL] ability to create from archive file (for wslctl)
* [ISSUE#12] setting default distribution

v2.1.1:
* [EVOL] download does not return boolean

v2.1.0:
* [EVOL] add creation date and image to wsl list
* [EVOL] create switch distrib and name from cli
* [EVOL] remove message"Could be started with command xxx" because external distributions support
* [BUG] error when directory not exists for wsl-distro-name.sh
* [EVOL] registry manage multi repositories
* [EVOL] dispatch configuration to services
* [EVOL] appconfig inherit from jsonHashtableFile
* [BUILD] Copy should set recusive #9

v2.0.5:
* [EVOL] add file size to backup create report
* [BUG] registry update broke registry file #6
* [BUG] Dockerfile parser misinterpret arg command #7

