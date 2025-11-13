# wslctl

The main goal of this project is to provide a single command `wslctl` to create, backup and manage
WSL (Windows Subsystem for Linux) instances on a windows 10 host.

It can deal with WSL1 and WSL2 instances (only if system is configured).

> There no exe building, only powershell scripts (OOP). Thus, everything is reviewable and auditable.


## Features

- [x] manage (set/get) default wsl version
- [x] halt wsl windows service (shutdown all instances)
- [x] create/remove/list wsl instances (extended infos)
- [x] default user creation on new instance with sudo capabilities (username/pwd configurable)
- [x] start/stop/status wsl instance (backgroud)
- [x] instance version convertion (v1 <-> v2)
- [x] manage default distribution
- [x] remote execute commands/script
- [x] bash to wsl instance
- [x] build distribution from Dockerfile
- [x] custom configuration file
- [x] rename instance
- [x] shrink instance
- [ ] clone instance

Registry Management

- [x] configurable endpoint (local or remote public url(read))
- [x] local cache of distributions (pull)
- [x] list/search of available distributions
- [x] distributions informations (size, date, description)
- [x] download integrity (sha256)
- [x] local cache cleanup
- [x] multi repository management
* [ ] accept .tar.xz (SquashFS) files (@see https://github.com/Biswa96/WSLInstall/blob/master/docs/Make_RootFS.md)


Backup Management

- [x] local backups informations (sha256, size, date, description, wsl name)
- [x] list/search of available local backups
- [x] remove backup by name
- [x] restore backup by name
- [x] restore confirmation when wsl instance already exists
- [ ] restore with another name

## Requirements

This tool manage the wsl processus and wsl distribution instances.
`wsl.exe` need to be installed first.

You can use the `./files/wsl-setup.ps1` script (need admin privileges) to setup everithings.


## Install

There are many options :

- clone this repository (updatable via git tags)
- download a specific version from gitlab releases and extract to a directory of your choice (manualy updatable)
- **prefered**: install via scoop.sh (non admin) with my buckets ([mbl-35/scoop-srsrns](https://github.com/mbl-35/scoop-srsrns))

> Remember to add the resulting directory to your windows `%PATH%` for a non scoop installation

### Configuration

The tool has no default configuration set. We need first to add repositories to the registry.
You should at least change that value with the following command:

```bash
PS> wslctl registry add <name> <registry-base-endpoint>
```

Example

```bash
PS> wslctl registry add yours https://your.repository.target
```


The custom configuration file is a json file named `wslctl.json` located next to the cmd file.

Supported configuration parameters :

| Name    | Description                | Default Value                    |
| ------- | -------------------------- | -------------------------------- |
| wsl     | wsl binary location        | "c:\\windows\\system32\\wsl.exe" |
| appData | where to store everythings | "`{$env:LOCALAPPDATA}`\\Wslctl"  |

> Note: The previous `appData` configuration parameter can be set as user windows environment variable named `WSLCTL`. 

The specified directory (in `appData` or `WSLCTL`) will have the following structure:
```bash
.
├── Backups
│   ├── backups.json                        # Backup dictionary (wsl name, hash, descriptions..)
│   ├── xxx-bkp.yy-amd64-wsl-rootfs.tar.gz  # yy-th backup for wsl named xxx
│   └── ...
├── Instances
│   ├── xxx                                 # Base directory for wsl instance named xxx
│   │   └── ext4.vhdx                       # Filesystem for wsl instance (v2)
│   └── ...
├── Registry
│   ├── <registry_alias>
│   │   └── register.json                   # Instances dictionary for that registry alias
│   │   └── <wsl-sha>.tar.gz                # Downloaded cache file (rootfs wsl) needed for creation
│   │   └── ...
│   └── ...
├── registry-buckets.json                   # List of configured registry buckets
├── wsl-instances.json                      # Dictionaly of installed wsl instances
```

## Quick start

Get the registry URL and type folloging commands:

```powershell
# get metadata from registry:
PS> wslctl registry add main https://raw.githubusercontent.com/mbl-35/wslctl-main/main
PS> wslctl registry update
# optionnal
PS> wslctl version default 2
# create wsl instance
PS> wslctl create ubuntu:20.04
```

> You will have a fresh ubuntu focal named `ubuntu-20.04` install with your windows user name as default user

More commands to demonstrate the backup / restore functionalities :

```powershell
# connect to the previously created instance
PS> wslctl exec ubuntu-20.04
# Do Stuff
$ echo "toto"
toto
...
$ exit

# backup your instance
PS> wslctl backup ubuntu-20.04 "Saving my stuff"
backup name is ubuntu-20.04-bkp.00

# connect to the instance
PS> wslctl exec ubuntu-20.04
# Do something stupid ...
$ sudo rm -rf /etc
...
$ exit

# Restore the instance (removing actual broken instance)
PS> wslctl backup restore ubuntu-20.04-bkp.00 --force

```

## Usage

`wslctl` coul be used from windows shell prompt (powershell or cmd), but also from a wsl instance
(if the bash `$PATH` environment variable contains the `wslctl` directory).

Use the `--help` option to get the tool usage :
```bash
PS> wslctl --help
   wslctl COMMAND [ARG...]
   wslctl [ --help | --version ]
```

### Wsl managment commands
```bash
   create  <distro_name> [<wsl_name>] [--v[1|2]]    Create a named wsl instance from distribution
   convert <wsl_name> <version>                     Concert instance to specified wsl version
   rename  <wsl_name> <wsl_name>                    Rename a wsl instance
   rm      <wsl_name>                               Remove a wsl instance by name
   shrink  <wsl_name> [<true|false>]                Shrink a wsl instance by name with optionnal wslops call
   exec    <wsl_name> [|<file.sh>|<cmd>]            Execute specified script|cmd on wsl instance by names
   ls                                               List all created wsl instance names
   start   <wsl_name>                               Start an instance by name
   stop    <wsl_name>                               Stop an instance by name
   status [<wsl_name>]                              List all or specified wsl Instance status
   halt                                             Shutdown all wsl instances
   upgrade                                          Upgrade wsl engine
   version [|<wsl_name>|default [|<version>]]       Set/get default version or get  wsl instances version
   default [|<wsl_name>]                            Set/get default distribution name
```

> Notes on shrink command. Right now:
> 1. Using Optimize-VHD (Recommended for Windows Pro/Enterprise) requires elevated privileges (not the target)
> 1. Using `diskpart` on the wsl virtual disk also require elevated privileges
> 1. In September, 2023, a pre-release of WSL (2.0.0) enabled a new "sparse" mode to automatically 
     shrink the image when files are removed. But it is still **experimental**, and lot of user report
     problems using it.
> 1. That's why the `shrink` implemented method use an old way : export instance, remove and restore it.
     It's simple, it works and it's safe (waiting for the stable sparse mode).
     That method can automaticly call the `/usr/local/bin/wslops` script with operations set to cleanup
     (by setting the extra method parameter to `true` - cf. help).
     User can extend that script by writing a `/usr/local/bin/wslctl-customize` script (it will never be 
     erased by wslctl, just called if exists).


### Wsl distribution registry commands
```bash
   registry add    <name> <remote_url>              Add a registry repository to list
   registry rm     <name>                           Remove the registry repository from the list
   registry update                                  Update distribution dictionary from registry repositories
   registry pull   <distro>                         Pull remote distribution to local registry
   registry purge                                   Remove all local registry content
   registry search <distro_pattern>                 Extract defined distributions from local registry
   registry ls                                      List local registry distributions
   registry repositories                            List defined registry repositories
```

### Wsl backup managment commands
```bash
   backup create  <wsl_name> <description>          Create a new backup for the specified wsl instance
   backup rm      <backup_name>                     Remove a backup by name
   backup restore <backup_name> [--force]           Restore a wsl instance from backup
   backup search  <backup_pattern>                  Find a created backup with input as pattern
   backup ls                                        List all created backups
   backup purge                                     Remove all created backups
```

> Note: Because of `powershell` remove quotes from command line, we have to pay attention to the escape character sequence in arguments.
>  Here is an example :
>    ```powershell
>    PS> ./src/wslctl.ps1 backup create ubuntu-20.04 "focal backup"
>    ok
>    PS> powershell ./src/wslctl.ps1 backup create ubuntu-20.04 "focal backup"
>    ok
>    PS> powershell ./src/wslctl.ps1 backup create ubuntu-20.04 "'focal backup'"
>    Error: too few arguments
>    ```



## Usage example: Instance creation/removal/connection

```powershell
# create wsl instance named 'my-ubuntu' with release 'ubuntu-18.04'
# default wsl version
PS1> .\src\wslctl.cmd create my-ubuntu ubuntu-18.04
* Import my-ubuntu
Check import requirements ...
Download distribution 'ubuntu-18.04' ...
Create wsl instance 'my-ubuntu' (wsl-version: 2)...
Adding group `me` (GID 1000) ...
Done.
* my-ubuntu created
  Could be started with command: wslctl start my-ubuntu

# remove it
PS1> .\src\wslctl.cmd rm my-ubuntu
*  my-ubuntu removed

# same creation with specific wsl version
PS1> .\src\wslctl.cmd create my-ubuntu ubuntu-18.04 --v1
* Import my-ubuntu
Check import requirements ...
Download distribution 'ubuntu-18.04' ...
Create wsl instance 'my-ubuntu' (wsl-version: 1)...
Adding group `me` (GID 1000) ...
Done.
* my-ubuntu created
  Could be started with command: wslctl start my-ubuntu

# connect to it
> .\src\wslctl.cmd exec my-ubuntu
Connect to my-ubuntu ...
To run a command as administrator (user "root"), use "sudo <command>".
See "man sudo_root" for details.

me@host:/mnt/c/Users/me/home/github/wslctl$
```


## Usage Example: Remote Execution

```powershell
# Call remote command
PS1> .\src\wslctl.cmd exec ubuntu-14.04.5 echo "toto tata"
Execute command 'echo toto tata' on ubuntu-14.04.5 ...
toto tata

 PS1> .\src\wslctl.cmd exec ubuntu-18.04 "echo tata; echo toto"
Execute command 'echo tata; echo toto' on ubuntu-18.04 ...
tata
toto

PS1>  .\src\wslctl.cmd exec ubuntu-18.04 "ls -lrt /tmp"
Execute command 'ls -lrt /tmp' on ubuntu-18.04 ...
total 141920
drwx------ 1 root     root         4096 Jul 31  2020 tmp5lkby6kk
drwx------ 1 root     root         4096 Sep 24  2020 pulse-CcctT9RwKSB1
drwx------ 1 root     root         4096 Dec 10  2020 tmp6g20k01_
...

PS1> .\src\wslctl.cmd exec ubuntu-18.04 ls -lrt /tmp
Execute command 'ls -lrt /tmp' on ubuntu-18.04 ...
total 141920
drwx------ 1 root     root         4096 Jul 31  2020 tmp5lkby6kk
drwx------ 1 root     root         4096 Sep 24  2020 pulse-CcctT9RwKSB1
drwx------ 1 root     root         4096 Dec 10  2020 tmp6g20k01_
...

# Call local script with args
PS1> .\src\wslctl.cmd exec ubuntu-18.04 .\tests\test-called-script.sh arg1 arg2
Execute test.sh on ubuntu-18.04 ...
SCRIPT_WINPATH=/mnt/c/Users/me/home/github/wslctl/tests/test-called-script.sh
hello from script file !
arg: arg1
arg: arg2

# Connect to wsl
PS1>  .\src\wslctl.cmd exec ubuntu-18.04
Connect to ubuntu-18.04 ...
me@host:/mnt/c/Users/me/home/github/wslctl$
```


# Registry

The registry is a list of remote or local repository to store retrivable distributions archives, and distributions metadatas.
There is no public registry repository (right now), because of probably sensitive informations stored in
customized entity (or business) resulting distributions.


The registry `endpoint` represents the registry base Url (ability to be in the local filesystem). Under that endpoint,
we have the metadata file definition (named `register.json`), and all the downloadable distributions files.

`wslctl` manage a local cache of all downloaded file from registry endpoints (stored in the `Registry` subdirectory
of the user configuration parameter `appData`).

## Registry Metadatas

Content of the `register.json` file: a hashtable of named distribution associated with its properties.

Distributions properties :

| Field      | Description                                               | Example                                                          |
| ---------- | --------------------------------------------------------- | ---------------------------------------------------------------- |
| date       | Date of distribution production                           | 2021/09/04 14:09:00                                              |
| desciption | Distribution description                                  | Official Archived Version",                                      |
| archive    | Name of the distribution archive in the registry endpoint | ubuntu-14.04.5-server-cloudimg-amd64-wsl.rootfs.tar.gz           |
| sha256     | Archive integrity checksum (sha256)                       | 93ac63df1badf4642e0d6074ca3d31866b8fc2a7ed386460db0b915eaf447b94 |
| size       | Archive size (human readable format)                      | 230,10 MB                                                        |


## Endpoint Implementation Example

Lets see a private repository endpoints `<domain>/canonical` and `<domain>/extras`

- Remote Filesystem Structure

    ```bash
    .
    ├── canonical
    │   ├── ms-ubuntu
    │   │   ├── 14.04
    │   │   │   ├── ms-ubuntu-14.04.5.3-server-cloudimg-amd64-wsl-rootfs.tar.gz
    │   │   │   └── ms-ubuntu-14.04.6-server-cloudimg-amd64-wsl-rootfs.tar.gz
    │   │   ├── 16.04
    │   │   │   └── release-2019.523
    │   │   │       └── ms-ubuntu-16.04.2-server-cloudimg-amd64-wsl-rootfs.tar.gz
    │   │   ├── 18.04
    │   │   │   └── ms-ubuntu-18.04.2-server-cloudimg-amd64-wsl-rootfs.tar.gz
    │   │   └── 20.04
    │   │       └── ms-ubuntu-20.04-server-cloudimg-amd64-wsl-rootfs.tar.gz
    │   ├── register.json
    │   └── ubuntu
    │       ├── 16.04
    │       │   ├── release-20210429
    │       │   │   └── ubuntu-16.04-server-cloudimg-amd64-wsl.rootfs.tar.gz
    │       │   └── release-20211001
    │       │       └── ubuntu-16.04-server-cloudimg-amd64-wsl.rootfs.tar.gz
    │       ├── 18.04
    │       │   └── release-20211122
    │       │       └── ubuntu-18.04-server-cloudimg-amd64-wsl.rootfs.tar.gz
    │       ├── 20.04
    │       │   └── release-20211118
    │       │       └── ubuntu-20.04-server-cloudimg-amd64-wsl.rootfs.tar.gz
    │       └── url.txt
    └─ extras
        ├── register.json
        └── wsl-vpnkit
            └── 0.2.4
                └── wsl-vpnkit-0.2.4.tar.gz
    ```

- **The corresponding `~/extras/register.json` file**

    ```json
    {
        "extras/wsl-vpnkit:0.2.4": {
            "source":       "https://github.com/sakai135/wsl-vpnkit/releases/download/v0.2.4/wsl-vpnkit.tar.gz",
            "date":         "2021/11/29 13:35:00",
            "description":  "Official VPN-Kit Cisco Bridge (sakai135)",
            "note":         "See: https://github.com/sakai135/wsl-vpnkit",
            "archive":      "wsl-vpnkit/0.2.4/wsl-vpnkit-0.2.4.tar.gz",
            "sha256":       "d4fbf1e7ae57b28a046b0515adbdab06914cd7a80d1ecd0b4a0b06c2b14743ad",
            "size":         "11.50 MB"
        }
    }
    ```


- **The corresponding `~/canonical/register.json` file**

    ```json
    {
    "ms-ubuntu:14.04.5": {
        "source": "https://wsldownload.azureedge.net/14.04.5.3-server-cloudimg-amd64-root.tar.gz",
        "date": "2021/06/11 07:53:00",
        "description": "Official Microsoft Archived Ubuntu Server 14.04 LTS (Trusty Tahr) release",
        "note": "Issues with initctl, policy-rc.d and tail",
        "archive": "ms-ubuntu/14.04/ms-ubuntu-14.04.5.3-server-cloudimg-amd64-wsl-rootfs.tar.gz",
        "sha256": "ff38b4c393260d1a282c0987005de5d2704d94979f247c90d548e85badcff673",
        "size": "181.80 MB"
    },
    "ms-ubuntu:14.04.6": {
        "source": "Updated from ms-ubuntu:14.04.5",
        "date": "2021/09/04 14:09:00",
        "description": "Official Microsoft Archived Ubuntu Server 14.04 LTS (Trusty Tahr) Patched release",
        "note": "Patched and updated",
        "archive": "ms-ubuntu/14.04/ms-ubuntu-14.04.6-server-cloudimg-amd64-wsl-rootfs.tar.gz",
        "sha256": "16daf3303bd416349daff2120b4a53ffedea18b490c217944f9f08777bafeca6",
        "size": "228.63 MB"
    },
    "ms-ubuntu:16.04.2": {
        "source": "https://wsldownload.azureedge.net/16.04.2-server-cloudimg-amd64-root.tar.gz",
        "date": "2021/06/11 07:53:00",
        "description": "Official Microsoft Archived Ubuntu Server 16.04 (Xenial Xerus) release",
        "note": "",
        "archive": "ms-ubuntu/16.04/release-2019.523/ms-ubuntu-16.04.2-server-cloudimg-amd64-wsl-rootfs.tar.gz",
        "sha256": "247314273c421a9c9ab11951ca4543ca2297d2fb557887a9a8948d1295794a91",
        "size": "225.82 MB"
    },
    "ms-ubuntu:18.04.2": {
        "source": "https://wsldownload.azureedge.net/Ubuntu_1804.2019.522.0_x64.appx",
        "date": "2019/05/22 12:00:00",
        "description": "Official Microsoft Ubuntu Server 18.04 (Bionic Beaver) release [2019.522]",
        "note": "Extracted from downloaded appx",
        "archive": "ms-ubuntu/18.04/ms-ubuntu-18.04.2-server-cloudimg-amd64-wsl-rootfs.tar.gz",
        "sha256": "7d220d798b75769d774358677b4cdb1ee556129f64005587dbe9ea8d50b38bd2",
        "size": "220.47 MB"
    },
    "ms-ubuntu:20.04": {
        "source": "https://wsldownload.azureedge.net/Ubuntu_2004.2020.424.0_x64.appx",
        "date": "2020/04/23 12:00:00",
        "description": "Official Microsoft Ubuntu Server 20.04 LTS (Focal Fossa) release [2020.424]",
        "note": "Extracted from downloaded appx",
        "archive": "ms-ubuntu/20.04/ms-ubuntu-20.04-server-cloudimg-amd64-wsl-rootfs.tar.gz",
        "sha256": "9d286bf63f963fbcea20ce6ffb56e8e81be8cd47e50d4aaeae717c18abe78066",
        "size": "431.57 MB"
    },
    "ubuntu:16.04.6": {
        "source": "https://cloud-images.ubuntu.com/releases/xenial/release-20210429/ubuntu-16.04-server-cloudimg-amd64-wsl.rootfs.tar.gz",
        "date": "2021/04/29 07:30:00",
        "description": "Official Ubuntu Server 16.04 LTS (Xenial Xerus) release [20210429]",
        "note": "",
        "archive": "ubuntu/16.04/release-20210429/ubuntu-16.04-server-cloudimg-amd64-wsl.rootfs.tar.gz",
        "sha256": "d26d46f5460cbd7bcdbd2a0676831bcd25773ef2f2fdf270aafd34bba2d0db00",
        "size": "243.69 MB"
    },
    "ubuntu:16.04.7": {
        "source": "https://cloud-images.ubuntu.com/releases/xenial/release-20211001/ubuntu-16.04-server-cloudimg-amd64-wsl.rootfs.tar.gz",
        "date": "2021/10/02 07:30:00",
        "description": "Official Ubuntu Server 16.04 LTS (Xenial Xerus) release [20211001]",
        "note": "",
        "archive": "ubuntu/16.04/release-20211001/ubuntu-16.04-server-cloudimg-amd64-wsl.rootfs.tar.gz",
        "sha256": "746bad563c891240c505c4955c4a134749db3ff9d9b0fa15ec6cab77518260ff",
        "size": "244.92 MB"
    },
    "ubuntu:18.04.6": {
        "source": "https://cloud-images.ubuntu.com/releases/bionic/release-20211122/ubuntu-18.04-server-cloudimg-amd64-wsl.rootfs.tar.gz",
        "date": "2021/11/23 07:00:00",
        "description": "Official Ubuntu Server 18.04 LTS (Bionic Beaver) release [20211122]",
        "note": "",
        "archive": "ubuntu/18.04/release-20211122/ubuntu-18.04-server-cloudimg-amd64-wsl.rootfs.tar.gz",
        "sha256": "d31c23cfbfbc1fae7f46d9d96db1c1c63666d739e28139b52766b3c22f2db6dc",
        "size": "278.78 MB"
    },
    "ubuntu:20.04.3": {
        "source": "https://cloud-images.ubuntu.com/releases/focal/release-20211118/ubuntu-20.04-server-cloudimg-amd64-wsl.rootfs.tar.gz",
        "date": "2021/11/08 22:42:00",
        "description": "Official Ubuntu Server 20.04 LTS (Focal Fossa) release [20211118]",
        "note": "",
        "archive": "ubuntu/20.04/release-20211118/ubuntu-20.04-server-cloudimg-amd64-wsl.rootfs.tar.gz",
        "sha256": "6b88c529f44d4b0804ebf3ce5c4504df61dc0b114b9b3b82a01b44a7e4c5c6b1",
        "size": "469.47 MB"
    }
    }
    ```

- Using that registry

    ```powershell
    # get metadata from registry:
    PS> wslctl registry add main https://<domain>/canonical
    PS> wslctl registry add extras https://<domain>/extras
    PS> wslctl registry update

    # list available distributions :
    PS> wslctl registry list
    Available distributions (installable):
    extras/wsl-vpnkit:0.2.4     [extras]       2021/11/29 13:35:00     11.50 MB   Official VPN-Kit Cisco Bridge (sakai135)
    ms-ubuntu:14.04.5           [main]         2021/06/11 07:53:00    181.80 MB   Official Microsoft Archived Ubuntu Server 14.04 LTS (Trusty Tahr) release
    ms-ubuntu:14.04.6           [main]         2021/09/04 14:09:00    228.63 MB   Official Microsoft Archived Ubuntu Server 14.04 LTS (Trusty Tahr) Patched release
    ms-ubuntu:16.04.2           [main]         2021/06/11 07:53:00    225.82 MB   Official Microsoft Archived Ubuntu Server 16.04 (Xenial Xerus) release
    ms-ubuntu:18.04.2           [main]         2019/05/22 12:00:00    220.47 MB   Official Microsoft Ubuntu Server 18.04 (Bionic Beaver) release [2019.522]
    ms-ubuntu:20.04             [main]         2020/04/23 12:00:00    431.57 MB   Official Microsoft Ubuntu Server 20.04 LTS (Focal Fossa) release [2020.424]
    ubuntu:16.04.6              [main]         2021/04/29 07:30:00    243.69 MB   Official Ubuntu Server 16.04 LTS (Xenial Xerus) release [20210429]
    ubuntu:16.04.7              [main]         2021/10/02 07:30:00    244.92 MB   Official Ubuntu Server 16.04 LTS (Xenial Xerus) release [20211001]
    ubuntu:18.04.6              [main]         2021/11/23 07:00:00    278.78 MB   Official Ubuntu Server 18.04 LTS (Bionic Beaver) release [20211122]
    ubuntu:20.04.3              [main]         2021/11/08 22:42:00    469.47 MB   Official Ubuntu Server 20.04 LTS (Focal Fossa) release [20211118]

    # create instance with available distribution
    PS> wslctl create ubuntu:20.04.3
    PS> wslctl create extras/wsl-vpnkit:0.2.4
    ```

# Backup / Restore

Once a wsl instance is created, we can save its state, and later restore it.


`wslctl` manage a local backup directory (stored in the `Backups` subdirectory of the user configuration parameter `appData`).
That directory has a backup metadata file named `backup.json`, storing all informations
(date, description, sha256, ...) of each realized backup, and all backup archives files in format
`{wsl-name}-bkp-{backup-index}-amd64-wsl-rootfs.tar.gz`.

## Backup Directory Example

Lets see a local user backup directory `%LOCALAPPDATA%\Wslctl\Backups`

```powershell
PS> dir C:\Users\me\AppData\Local\Wslctl\Backups

Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
-a----        27/10/2021     17:25           1161 backups.json
-a----        27/10/2021     09:06      241284793 ubuntu-14.04.5-bkp.00-amd64-wsl-rootfs.tar.gz
-a----        27/10/2021     17:24      241284381 ubuntu-14.04.5-bkp.01-amd64-wsl-rootfs.tar.gz
```


## Backup Metadatas

Content of the `backups.json` file: a hashtable of named distribution backuped, associated with its properties.

Distributions properties :

| Field       | Description                                               | Example                                                          |
| ----------- | --------------------------------------------------------- | ---------------------------------------------------------------- |
| date        | Date of backup production                                 | 2021/09/04 14:09:00                                              |
| description | Backup description                                        | Retest oop                                                       |
| archive     | Name of the distribution archive in the registry endpoint | ubuntu-14.04.5-bkp.01-amd64-wsl-rootfs.tar.gz                    |
| sha256      | Archive integrity checksum (sha256)                       | df6ef87d8b449d039d49d94d9daa8b14ad34d23ce39f3d5e927b39d699a160ed |
| size        | Archive size (human readable format)                      | 230,10 MB                                                        |
| wslname     | Instance name from wich the backup has been realized      | ubuntu-14.04.5                                                   |
| wslversion  | Wsl version of the backuped instance                      | 2                                                                |

The `backup list` command is based on that file :

```powershell
.\src\wslctl.cmd backup ls
Available Backups (recoverable):
ubuntu-14.04.5-bkp.00       - 2021/10/27 09:06:39 -       230,11 MB - test oop
ubuntu-14.04.5-bkp.01       - 2021/10/27 17:25:30 -       230,11 MB - Retest oop
```


# Building a wsl instance

Nothing pushed to registry nor backup.
> Only the wsl instance is created.

```powershell

# Create from Dockerfile set in directory (tag from dockerfile name)
> .\src\wslctl.cmd build .\tests\test.dockerfile
Building 'test' with .\tests\test.dockerfile
Parsing file ...
Warning: Unimplemented command 'expose' (ignored)
Warning: Unimplemented command 'expose' (ignored)
Warning: Unimplemented command 'cmd' (ignored)
From  : ubuntu:18.04
Tag   : test
...

# Create from directory (tag from directory name)
# used Dockerfile default name
> .\src\wslctl.cmd build .\tests
Building 'tests' with .\tests\Dockerfile
Parsing file ...
Warning: Unimplemented command 'expose' (ignored)
Warning: Unimplemented command 'expose' (ignored)
Warning: Unimplemented command 'cmd' (ignored)
From  : ubuntu:18.04
Tag   : tests
...


# Create wsl instance from specified Dockerfile and name it as specified tag name

> .\src\wslctl.cmd build .\tests\test.dockerfile --tag=ubuntu:18.04-mine --dry-run
DryRun - Building 'ubuntu:18.04-mine' with .\tests\test.dockerfile
Parsing file ...
Warning: Unimplemented command 'expose' (ignored)
Warning: Unimplemented command 'expose' (ignored)
Warning: Unimplemented command 'cmd' (ignored)
From  : ubuntu:18.04
Tag   : ubuntu:18.04-mine
...

# Using the --dry-run option (nothing created, just verbose what to do)
> .\src\wslctl.cmd build .\tests\test.dockerfile --tag=ubuntu:18.04-mine --dry-run
DryRun - Building 'ubuntu:18.04-mine' with .\tests\test.dockerfile
Parsing file ...
Warning: Unimplemented command 'expose' (ignored)
Warning: Unimplemented command 'expose' (ignored)
Warning: Unimplemented command 'cmd' (ignored)
From  : ubuntu:18.04
Tag   : ubuntu:18.04-mine

--------------Generated Script File --------------------
#!/usr/bin/env bash
# The script is generated from a Dockerfile via wslctl v1.0.5
# The Original DockerFile is from image : ubuntu:18.04
# Original DockerFile Maintainer: matsumotory

# -- Automatic change working directory:
cd /mnt/c/Users/me/home/github/wslctl/tests

# -- Converted commands:
apt-get -y update
apt-get -y install sudo openssh-server
apt-get -y install git
apt-get -y install curl
apt-get -y install rake
apt-get -y install ruby ruby-dev
apt-get -y install bison
apt-get -y install libcurl4-openssl-dev libssl-dev
apt-get -y install libhiredis-dev
apt-get -y install libmarkdown2-dev
apt-get -y install libcap-dev
apt-get -y install libcgroup-dev
apt-get -y install make
apt-get -y install libpcre3 libpcre3-dev
apt-get -y install libmysqlclient-dev
apt-get -y install gcc
cd /usr/local/src/ && git clone https://github.com/matsumotory/ngx_mruby.git
export NGINX_CONFIG_OPT_ENV="--with-http_stub_status_module --with-http_ssl_module --prefix=/usr/local/nginx --with-http_realip_module --with-http_addition_module --with-http_sub_module --with-http_gunzip_module --with-http_gzip_static_module --with-http_random_index_module --with-http_secure_link_module"
echo 'export NGINX_CONFIG_OPT_ENV="--with-http_stub_status_module --with-http_ssl_module --prefix=/usr/local/nginx --with-http_realip_module --with-http_addition_module --with-http_sub_module --with-http_gunzip_module --with-http_gzip_static_module --with-http_random_index_module --with-http_secure_link_module"'>> ~/.bashrc
cd /usr/local/src/ngx_mruby && sh build.sh && make install
--------------------------------------------------------
```



# Development Notes

Usage of `make.ps1` :

### ScriptAnalyzer

```powershell
PS> ./make.ps1 test

# Correct with PSScriptAnalyser
PS> Get-Help Get-ScriptAnalyzerRule -ShowWindow
```


### Create a release

1. Add changes to `./CHANGELOG.md`.
1. Change the version in `./src/wslctl.ps1` (just change the `major.minor.build` part for variable `$version`).
1. Push to upstream: `git add . && git commit -m "commit message" && git push origin master`.
1. Run `$Version=(cmd /c powershell.exe .\src\wslctl.ps1 --version)` to retreive the binary version.
1. Create the tag with `git tag $Version`.
1. Push to upstream: `git push --tags origin master`.


### Building Wslctl Distributions

```Powershell
PS> ./make.ps1
```

### Debug error

Copy paste th following function to your shell, and call it after a script failure.. 
```Powershell
function Resolve-Error ($ErrorRecord=$Error[0]) {
    $ErrorRecord | Format-List * -Force
    $ErrorRecord.InvocationInfo |Format-List *
    $Exception = $ErrorRecord.Exception
    for ($i = 0; $Exception; $i++, ($Exception = $Exception.InnerException))
    {   "$i" * 80
        $Exception |Format-List * -Force
    }
}
PS C:\Users\me> Resolve-Error
```

