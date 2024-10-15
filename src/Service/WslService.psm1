
using module "..\Application\AppConfig.psm1"
using module "..\Application\ServiceLocator.psm1"
using module "..\Tools\FileUtils.psm1"
using module "..\Model\JsonHashtableFile.psm1"
using module "..\Model\WslElement.psm1"


Class WslService {

    [String] $Binary
    [String] $Location
    [String] $File
    [String] $defaultUsername

    [JsonHashtableFile] $Instances
    [Array] $WslListCache


    WslService() {
        $Config = ([AppConfig][ServiceLocator]::getInstance().get('config'))

        $this.Binary = 'c:\windows\system32\wsl.exe'
        if ( $Config.ContainsKey("wsl")) { $this.Binary = $Config.wsl }
        $this.Location = [FileUtils]::joinPath($Config.appData, "Instances")
        $this.defaultUsername = "$env:UserName"

        $this.File = [FileUtils]::joinPath($Config.appData, "wsl-instances.json")
        $this._initialize()
    }

    [void] _initialize() {
        if (-Not (Test-Path -Path $this.Location)) {
            New-Item -ItemType Directory -Force -Path $this.Location | Out-Null
        }
    }

    [void] _loadFile() {
        if (-Not $this.Instances) {
            $this.Instances = [JsonHashtableFile]::new($this.File, @{})
        }
    }

    [String] getLocation([String] $name) {
        return  [FileUtils]::joinPath($this.Location, $name)
    }


    [void] checkBeforeImport([String] $name) { $this.checkBeforeImport($name, $false) }
    [void] checkBeforeImport([String] $name, [Boolean] $forced) {
        if (($this.exists($name)) -And (-Not $forced)) {
            throw "Instance '$name' already exists"
        }

        # Remove existing instance
        if ($this.exists($name) -and $this.remove($name) -ne 0) {
            throw "Can not destroy active $name"
        }
        $this.checkDirectory($name, $forced)
    }

    [void] checkDirectory([String] $name) { $this.checkDirectory($name, $false) }
    [void] checkDirectory([String] $name, [Boolean] $forced) {
        # Check target directory does not exists or is empty
        $dir = $this.getLocation($name)
        if (Test-Path -Path $dir) {
            $directoryInfo = Get-ChildItem $dir | Measure-Object
            if (-Not ($directoryInfo.count -eq 0)) {
                if (-not $forced) {
                    throw "Directory $dir already in use"
                }
                Remove-Item -LiteralPath $dir -Force -Recurse -ErrorAction Ignore | Out-Null
            }
        }
    }


    [Int32] import ([String] $name, [String] $from, [String] $archive) { return $this.import($name, $from, $archive, -1, $false) }
    [Int32] import ([String] $name, [String] $from, [String] $archive, [int] $version, [Boolean]$createDefaultUser) {
        if (($version -lt 1) -or ($version -gt 2)) {
            $version = -1
        }
        if ($version -eq -1) {
            $version = $this.getDefaultVersion()
        }

        $dir = $this.getLocation($name)
        if (Test-Path -Path $dir) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }

        & $this.Binary --import $name $dir $archive --version $version
        if ($LastExitCode -ne 0) {
            throw "Could not create '$name' instance"
        }

        # Adjust Wsl Distro Name
        & $this.Binary --distribution $name -u root sh -c "mkdir -p /lib/init && echo WSL_DISTRO_NAME=$name > /lib/init/wsl-distro-name.sh"
        if ($LastExitCode -ne 0) {
            throw "Could not set '$name' /lib/init/wsl-distro-name.sh"
        }
        $returnCode = 0

        $this._loadFile()
        $this.Instances.Add($name, @{
                image    = $from
                creation = Get-Date -Format "yyyy/MM/dd HH:mm:ss"
            })
        $this.Instances.commit()
        $this.WslListCache = $null

        # copy val_ini script (suppose /usr/local/bin on all OS)
        $iniValPath = [FileUtils]::getResourcePath("ini_val.sh")
        $iniUsrPath = [FileUtils]::getResourcePath("ini_user.sh")
        $this.copy($name, $iniValPath, "/usr/local/bin/ini_val", $true)
        $this.copy($name, $iniUsrPath, "/usr/local/bin/ini_usr", $true)

        # Assert *nix file format
        $commandLine = @(
            "sed -i 's/\r//' /usr/local/bin/ini_val"
            "chmod +x /usr/local/bin/ini_val"
            "sed -i 's/\r//' /usr/local/bin/ini_usr"
            "chmod +x /usr/local/bin/ini_usr"
        )

        # create default user
        if ($createDefaultUser) {
             $commandLine += @(
                "/usr/local/bin/ini_usr $($this.defaultUsername)"
                "/usr/local/bin/ini_val /etc/wsl.conf user.default $($this.defaultUsername)"
            )
        }

        # set the wsl instance hostname & cleanup
        $commandLine += @(
            "/usr/local/bin/ini_val /etc/wsl.conf network.hostname $($name)"
            "rm -f /usr/local/bin/ini_usr"
        )
        $commandLineTxt = $commandLine -Join ";"
        #Write-Verbose $commandLineTxt

        # execute all
        $returnCode = $this.exec($name, @( "$commandLineTxt" ))
        & $this.Binary --terminate $name
        return $returnCode
    }

    [System.Collections.Hashtable] export([String] $name, [String] $archiveName) {
        if ($this.isRunning($name)) {
            Write-Host "Stop instance '$name'"
            $this.terminate($name)
        }

        $backupTar = "$archiveName-amd64-wsl-rootfs.tar"
        $backupTgz = "$backupTar.gz"

        # Export WSL
        & $this.Binary --export $name $backupTar
        & $this.Binary --distribution $name --exec gzip $backupTar

        $backupHash = [FileUtils]::sha256($backupTgz)
        $backupSize = [FileUtils]::getHumanReadableSize($backupTgz).Size
        $version = $this.version($name)

        $this._loadFile()
        $image = $null
        $creation = $null
        if ($this.Instances.ContainsKey($name)) {
            $image = $this.Instances.$name.image
            $creation = $this.Instances.$name.creation
        }

        # Finally append backup to the register
        $backupdate = Get-Date -Format "yyyy/MM/dd HH:mm:ss"
        return @{
            wslname    = $name
            image      = $image
            wslversion = $version
            archive    = $backupTgz
            sha256     = $backupHash
            size       = $backupSize
            date       = $backupdate
            creation   = $creation
        }
    }

    [int] convert([String] $name, [int]$version) {
        if ($this.isRunning($name)) {
            Write-Host "Stop instance '$name'"
            $this.terminate($name)
        }

        &  $this.Binary --set-version $name $version
        return $LastExitCode
    }

    [int32] start([String] $name) {
        # warning: wsl binary always returns 0 even if no distribution exists
        &  $this.Binary --distribution $name -- nohup sleep 99999 `</dev/null `>/dev/null 2`>`&1 `& sleep 1
        return $LastExitCode
    }

    [Int32] terminate([String] $name) {
        & $this.Binary --terminate $name
        return $LastExitCode
    }

    [Int32] shutdown() {
        & $this.Binary --shutdown
        return $LastExitCode
    }

    [Int32] upgrade() {
        $prev = [Console]::OutputEncoding;
        [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
        $consoleResult = @( (& $this.Binary --update)  | Where-Object { $_ -ne "" } )
        [Console]::OutputEncoding = $prev
        write-Host $consoleResult -Separator "`n"
        return $LastExitCode
    }

    [Boolean] isRunning([String] $name) {
        return (@( $this.list() | Select-Object | Where-Object {
                    $_.name -eq $name -and $_.running -eq $true
                }).Length -ne 0)
    }


    [Boolean] exists([String] $name) {
        return (@( $this.list() | Select-Object | Where-Object {
                    $_.name -eq $name
                }).Length -ne 0)
    }

    [Array] list() { return $this.list($false) }
    [Array] list([Boolean] $force) {
        if ($force -Or $null -eq $this.WslListCache) { $this.WslListCache = @() }

        if ($this.WslListCache.Count -eq 0) {
            # Inexplicably, wsl --list verbose produces UTF-16LE-encoded
            # ("Unicode"-encoded) output rather than respecting the
            # console's (OEM) code page.
            $prev = [Console]::OutputEncoding;
            [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
            $consoleResult = @( (& $this.Binary --list --verbose | Select-Object -Skip 1) | Where-Object { $_ -ne "" } )
            [Console]::OutputEncoding = $prev


            #ISSUE-19: Display error wslctl ls when no distribution
            $hasDistribution = (@( $consoleResult | Select-Object | Where-Object {
                        $_ -like "https://aka.ms/wslstore"
                    }).Length -eq 0)

            if ($hasDistribution) {
                $this._loadFile()
                $consoleResult.GetEnumerator() | ForEach-Object {
                    $lineWords = [array]($_.split(" ") | Where-Object { $_ })
                    $element = [WslElement]::new()

                    if ($lineWords.Length -eq 4) {
                        # this is the default distribution
                        $element.default = $true
                        $null, $lineWords = $lineWords
                    }
                    $element.name, $status, $element.wslVersion = $lineWords
                    $element.running = $( $status -eq "Running" )
                    if ($this.Instances.ContainsKey($element.name)) {
                        $element.from = $this.Instances.$($element.name).image
                        $element.creation = $this.Instances.$($element.name).creation
                    }
                    $this.WslListCache += $element
                }
            }
        }
        return $this.WslListCache
    }


    [String] status([String] $name) {
        if (-Not $this.exists($name)) {
            return "* $name is not a wsl instance"
        }
        $running = ( $this.list() | Select-Object | Where-Object {
                $_.name -eq $name
            }).running
        return $(if ($running) { "Running" } else { "Stopped" } )
    }

    [int] version([String] $name) {
        if (-Not $this.exists($name)) {
            return -1
        }
        return ( $this.list() | Select-Object | Where-Object {
                $_.name -eq $name
            }).wslVersion

    }

    [String] getDefaultDistribution() {
        return ( $this.list() | Select-Object | Where-Object {
                $_.default -eq $true
            }).name
    }

    [String] setDefaultDistribution([String] $name) {
        if (-Not $this.exists($name)) {
            return -1
        }

        & $this.Binary --set-default $name
        return $LastExitCode
    }


    [Int32] rename([String] $currentName, [String] $newName) {

        $this.checkDirectory($newName, $true)
        Write-Host "Shutdown WSL..."
        $this.shutdown()

        # Search instance in regedit
        $RegPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss'
        $WantedRegInfo = Get-ItemProperty $RegPath\* -EA 0 | Select-Object DistributionName, PSChildName | Where-Object { $_.DistributionName -eq "$currentName" }
        if (-not $WantedRegInfo ) {
            throw 'No Regedit key found'
        }
        # Having regedit path
        $WantedRegPath = "$RegPath\" + $WantedRegInfo.PSChildName
        # compute new Path
        $BasePath = Get-ItemPropertyValue -Path $WantedRegPath -Name BasePath
        $newPath = (Split-Path -parent $BasePath) + "\$newName"

        # setting new values
        Set-ItemProperty -Path $WantedRegPath\ -Name DistributionName -Value "$newName" -ErrorAction Stop
        Set-ItemProperty -Path $WantedRegPath\ -Name BasePath -Value "$newPath" -ErrorAction Stop

        if ($LastExitCode -ne 0) {
            throw "Enable to rename '$currentName' instance"
        }
        $this._loadFile()
        if ($this.Instances.ContainsKey($currentName)) {
            write-host "Rename '$currentName'"
            $this.Instances.Add($newName, @{
                    image    = $this.Instances.$currentName.image
                    creation = $this.Instances.$currentName.creation
                })
            $this.Instances.Remove($currentName)
            $this.Instances.commit()
            $this.WslListCache = $null
        }

        $dir = $this.getLocation([String] $currentName)
        Rename-Item -Path $dir -NewName $newName | Out-Null

        # set the wsl instance hostname
        $commandLine += @(
            "[ -f /etc/wsl.conf ] && sed -i 's/hostname\s*=\s*.*/hostname = $($newName)/' /etc/wsl.conf"
            "sed -i 's/ $($currentName) */ $($newName) /' /etc/hosts"
        )
        $commandLineTxt = $commandLine -Join ";"

        # execute all
        $returnCode = $this.exec($newName, @( "$commandLineTxt" ), $true)
        & $this.Binary --terminate $newName
        return $returnCode
    }


    [Int32] remove([String] $name) {
        if (-Not $this.exists($name)) {
            throw "Instance '$name' not found"
        }

        & $this.Binary --unregister $name
        if ($LastExitCode -ne 0) {
            throw "Enable to remove '$name' instance"
        }
        $this._loadFile()
        if ($this.Instances.ContainsKey($name)) {
            write-host "Remove '$name'"
            $this.Instances.Remove($name)
            $this.Instances.commit()
            $this.WslListCache = $null
        }

        $dir = $this.getLocation([String] $name)
        Remove-Item -LiteralPath $dir -Force -Recurse -ErrorAction Ignore | Out-Null
        return $LastExitCode
    }

    [Int32] connect([string]$name) {
        $shellArray = @('/bin/zsh', '/bin/bash', '/bin/sh')
        $cmdTxt = (( $shellArray | ForEach-Object { "if [ -x $_ ]; then $_ --login;" } ) -Join " else ") + (" fi;" * $shellArray.Length) + ' exit $?'

        return $this.exec($name, @("$($cmdTxt)"))
    }

    [Int32] exec([string]$name, [string]$scriptPath, [array]$scriptArgs) { return $this.exec($name, $scriptPath, $scriptArgs, $false) }
    [Int32] exec([string]$name, [string]$scriptPath, [array]$scriptArgs, [Boolean]$asRoot) {
        if (-Not ([IO.Path]::GetExtension($scriptPath) -eq '.sh')) {
            throw "Script has to be a shell file (extension '.sh')"
        }
        if (-not (Test-Path $scriptPath -PathType leaf)) {
            throw "Script not found"
        }
        $winScriptFullPath = Resolve-Path -Path $scriptPath -ErrorAction Stop
        $wslScriptPath = $this.wslPath($winScriptFullPath)
        $scriptNoPath = Split-Path $scriptPath -Leaf
        $scriptTmpFile = "/tmp/$scriptNoPath"

        $commandLine = @(
            "cp $wslScriptPath $scriptTmpFile"
            "chmod +x $scriptTmpFile"
            "SCRIPT_WINPATH=$wslScriptPath $scriptTmpFile $scriptArgs"
            "return_code=`$?"
            "rm $scriptTmpFile"
            "exit `$return_code"
        ) -Join ";"
        return $this.exec($name, @( "$commandLine" ), $asRoot)
    }

    [Int32] exec([string]$name, [array]$commandline) { return $this.exec($name, $commandline, $false) }
    [Int32] exec([string]$name, [array]$commandline, [Boolean]$asRoot) {
        if ($null -eq $commandline ) { $commandline = @() }
        if (-Not $this.exists($name)) {
            throw "Instance '$name' not found"
        }

        $processArgs = "--distribution $name "
        if ($asRoot) { $processArgs += "-u root " }
        $processArgs += "-- $commandline"
        $process = Start-Process $this.Binary $processArgs -NoNewWindow -Wait -ErrorAction Stop -PassThru
        return $process.ExitCode
    }

    [int32] copy([string]$name, [string]$winSrcPath, [string]$wslDestPath){
        return $this.copy($name,$winSrcPath,$wslDestPath, $false)
    }
    [int32] copy([string]$name, [string]$winSrcPath, [string]$wslDestPath, [Boolean]$asRoot){
        # check file exists
        if (-not (Test-Path $winSrcPath -PathType leaf)) {
            throw "File not found"
        }

        # resolve windows full path
        $winSrcFullPath = Resolve-Path -Path $winSrcPath -ErrorAction Stop
        # get same file accessible from wsl
        $wslSrcFullPath = $this.wslPath($winSrcFullPath)
        $commandLine = @(
            "cp $wslSrcFullPath $wslDestPath"
            "return_code=`$?"
            "exit `$return_code"
        ) -Join ";"
        return $this.exec($name, @( "$commandLine" ),$asRoot)
    }

    [String] wslPath([String] $winPath) {
        return & $this.Binary wslpath -u $winPath.Replace('\', '\\')
    }


    [String] winPath([String] $wslPath) {
        return & $this.Binary wslpath -w $wslPath.Replace('\', '\\')
    }


    [Int32] setDefaultVersion([int] $version) {
        if (($version -lt 1) -or ($version -gt 2)) {
            throw "Invalid version number $version"
        }
        & $this.Binary --set-default-version $version
        return $LastExitCode
    }

    [String] getDefaultVersion() {
        # Get the default wsl version
        return Get-ItemPropertyValue `
            -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss `
            -Name DefaultVersion
    }
}
