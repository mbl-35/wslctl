
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
    [int] $LastExitCode = 0


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

    
    #    [string[]] invoke([string[]] $CommandArgs, [switch] $ShowOutput) {
    [string[]] invoke([string]$cmdArgs) {
        return $this.invoke(@{args = $cmdArgs })
    }
    [string[]] invoke([string]$cmdArgs, [boolean] $output) {
        return $this.invoke(@{
                args   = $cmdArgs
                output = $output
            })
    }
    [string[]] invoke([hashtable]$Parameters) {
        $ht = @{
            args         = $null
            output       = $false
            distribution = $null
            script       = $null
            script_args  = $null
            root         = $false
        }
        $Parameters.GetEnumerator() | ForEach-Object { $ht[$_.Key] = $_.Value }
        $processArgs = @()
        if ($ht.distribution) { $processArgs += "--distribution $($ht.distribution)" }
        if ($ht.root) { $processArgs += "-u root" }
        if ($ht.args) { $processArgs += "$($ht.args)" }
        if ($ht.script) { $processArgs += "-- $($ht.script)" }
        if ($ht.script_args) { $processArgs += "$($ht.script_args)" }
        if ($global:DEBUG) { Write-Host "[IO:$($ht.output)]> wsl $processArgs" }

        if ($ht.output) {
            $process = Start-Process $this.Binary $processArgs -NoNewWindow -Wait -ErrorAction Stop -PassThru
            $this.LastExitCode = $process.ExitCode
            return @()
        }

        # Save IO original Encoding
        $originalOutputEncoding = [Console]::OutputEncoding
        $originalInputEncoding = [Console]::InputEncoding
        $originalOutputEncodingPS = $OutputEncoding

        # Prepare processus 
        $output = [System.Collections.Generic.List[string]]::new()
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $this.Binary
        $psi.Arguments = $processArgs -join " "
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true

        try {
            # switch to UTF8 encoding
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [Console]::InputEncoding = $utf8NoBom
            [Console]::OutputEncoding = $utf8NoBom
            $OutputEncoding = $utf8NoBom

            $process = [System.Diagnostics.Process]::Start($psi)

            # capture outputs to final array
            while (!$process.StandardOutput.EndOfStream) {
                $line = $process.StandardOutput.ReadLine().Trim() -replace '\0|[\r\n]+', ''
                if ($line) { $output.Add($line) }
            }
            while (!$process.StandardError.EndOfStream) {
                $line = $process.StandardError.ReadLine().Trim()
                if ($line) { Write-Error $line }
            }
            $process.WaitForExit()
            $this.LastExitCode = $process.ExitCode
        }
        finally {
            # restaure original ecoding
            [Console]::InputEncoding = $originalInputEncoding
            [Console]::OutputEncoding = $originalOutputEncoding
            $OutputEncoding = $originalOutputEncodingPS
        }
        return $output
    }


    [bool] hasInstances() {
        $consoleResult = $this.invoke("--list --verbose")
        return -not ($consoleResult -match 'https://aka\.ms/wslstore|wsl\.exe')
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

        $this.invoke("--import $name $dir $archive --version $version", $true)
        if ($this.LastExitCode -ne 0) {
            throw "Could not create '$name' instance"
        }

        # Adjust Wsl Distro Name
        $this.invoke(@{
                distribution = $name
                script       = "mkdir -p /lib/init && echo WSL_DISTRO_NAME=$name > /lib/init/wsl-distro-name.sh"
                root         = $true
            })
        if ( $this.LastExitCode -ne 0 ) {
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
        $wslOpsPath = [FileUtils]::getResourcePath("wslops.sh")
        $this.copy(@{
                distribution = $name
                source       = $wslOpsPath
                destination  = "/usr/local/bin/wslops"
                root         = $true
            })

        # Assert *nix file format
        $commandLine = @(
            "sed -i 's/\r//' /usr/local/bin/wslops"
            "chmod +x /usr/local/bin/wslops"
        )

        $wslOps = @( "ini-cfg" )
        $wslOpsArgs = @(
            "--file=/etc/wsl.conf"
            "--ini-network-hostname=$($name)"
        )

        # create default user (should be replace with wsl-ops)
        if ($createDefaultUser) {
            $wslOps += @("user-account")
            $wslOpsArgs += @(
                "--username=$($this.defaultUsername)"
                "--ini-user-default=$($this.defaultUsername)"
            )
        }

        # set the wsl instance hostname & cleanup (should be replace with wsl-ops)
        $commandLine += @(
            "/usr/local/bin/wslops --operations={0} {1}" -f $($wslOps -Join "," ), $($wslOpsArgs -Join " ")
        )
        $commandLineTxt = $commandLine -Join ";"

        # execute all
        $this.invoke(@{
                distribution = $name
                script       = $commandLineTxt
                output       = $true
                root         = $true
            })
        $returnCode = $this.LastExitCode
        $this.invoke("--terminate $name")
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
        $this.invoke("--export $name $backupTar")
        $this.invoke(@{
                distribution = $name
                args         = "--exec gzip $backupTar"
            })

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

        $this.invoke("--set-version $name $version")
        return $this.LastExitCode
    }

    [int32] start([String] $name) {
        # warning: wsl binary always returns 0 even if no distribution exists
        $this.invoke(@{
                distribution = $name
                script       = "nohup sleep 99999 `</dev/null `>/dev/null 2`>`&1 `& sleep 1"
            })
        return $this.LastExitCode
    }
    [Int32] terminate([String] $name) {
        $this.invoque("--terminate $name", $true)
        return $this.LastExitCode
    }
    [Int32] shutdown() {
        $this.invoque("--shutdown", $true)
        return $this.LastExitCode
    }
    [Int32] upgrade() {
        $this.invoke("--update", $true)
        return $this.LastExitCode
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

    [String] getInstanceRegEditPath([String] $name) {
        $RegInfo = Get-ChildItem -Path "REGISTRY::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss" |
        Where-Object {
            (Get-ItemProperty -Path $_.PSPath -Name DistributionName).DistributionName -eq "$name"
        } | Select-Object -Property Name
        if (-not $RegInfo ) {
            throw 'No Regedit key found'
        }
        return "REGISTRY::" + $RegInfo.Name
    }

    [int64] getInstanceSize([String] $name) {
        $RegDInstancePath = $this.getInstanceRegEditPath($name)
        $instanceDir = Get-ItemPropertyValue -Path $RegDInstancePath -Name BasePath
        $instanceSize = (Get-ChildItem -Recurse -LiteralPath "$instanceDir" | Measure-Object -Property Length -sum).sum
        return $instanceSize
    }

    [Array] list() { return $this.list($false) }
    [Array] list([Boolean] $force) {
        if ($force -Or $null -eq $this.WslListCache) { $this.WslListCache = @() }

        if ($this.WslListCache.Count -eq 0) {
            #ISSUE-19: Display error wslctl ls when no distribution
            if ($this.hasInstances()) {
                $this._loadFile()
                $this.invoke("--list --verbose") | Select-Object -Skip 1 | ForEach-Object {
                    $lineWords = [array]($_.split(" ") | Where-Object { $_ })
                    $element = [WslElement]::new()
                    if ($lineWords.Length -eq 4) {
                        # this is the default distribution
                        $element.default = $true
                        $null, $lineWords = $lineWords
                    }
                    $element.name, $status, $element.wslVersion = $lineWords
                    $element.running = $( $status -eq "Running" )
                    $element.size = $this.getInstanceSize($element.name)
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

        $this.invoke("--set-default $name")
        return $this.LastExitCode
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
        $this.invoke(@{
                distribution = $newName
                script       = @(
                    "[ -f /etc/wsl.conf ] && sed -i 's/hostname\s*=\s*.*/hostname = $newName/' /etc/wsl.conf"
                    "sed -i 's/ $currentName */ $newName /' /etc/hosts"
                ) -Join ";"
                root         = $true
            })
        $returnCode = $this.LastExitCode
        $this.terminate($newName)
        return $returnCode
    }


    [Int32] remove([String] $name) {
        if (-Not $this.exists($name)) {
            throw "Instance '$name' not found"
        }

        $this.invoke("--unregister $name")
        if ($this.LastExitCode -ne 0) {
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
        # detect user defined shell inside instance
        $response = $this.invoke(@{
                distribution = $name
                script       = "getent passwd $env:USERNAME"
                root         = $true
            })

        $shellArray = @('/bin/zsh', '/bin/bash'; '/bin/sh')
        $shell = if ($response) { $response[0].Trim().Split(":")[-1] + " --login" } else {
            (( $shellArray | ForEach-Object { "if [ -x $_ ]; then $_ --login;" } ) -Join " else ") + 
            (" fi;" * $shellArray.Length) + ' exit $?'
        }

        $this.invoke(@{
                distribution = $name
                script       = "$shell"
                output       = $true
            })
        return $this.LastExitCode
    }

    [Int32] cleanup([string]$name) {
        if (-not $this.isRunning($name)) {
            $this.start($name)
        }
        $this.invoke({
                distribution = $name
                script = "if [ -f {0} ]; then {0} {1}; fi; exit `$?" -f 
                "/usr/local/bin/wslops", "--operations=cleanup --ignore-errors --yes"
                output = $true
                root = $true
            })
        return $this.LastExitCode
    }

    
    [int32] copy([hashtable]$Parameters) {
        $ht = @{
            distribution = $null
            source       = $null    # win
            destination  = $null    # wsl
            root         = $false
        }
        $Parameters.GetEnumerator() | ForEach-Object { $ht[$_.Key] = $_.Value }

        # check file exists
        if (-not (Test-Path $ht.source -PathType leaf)) {
            throw "File not found"
        }
        # resolve windows full path & get same file accessible from wsl
        $winFullPath = Resolve-Path -Path $ht.source -ErrorAction Stop
        $winSrcFullPathFromWsl = $this.wslPath($winFullPath)
        $this.invoke($ht + @{
                script = "cp $winSrcFullPathFromWsl $($ht.destination); exit `$?"
            })
        return $this.LastExitCode
    }


    [String] wslPath([String] $winPath) {
        return [FileUtils]::pathToUnix($winPath)
    }


    [String] winPath([String] $wslPath) {
        # NOTE: must have a wsl instance for this ! add check
        $escapedPath = $wslPath.Replace('\', '\\')
        return ($this.invoke("wslpath -w $escapedPath") | 
            Select-Object -First 1)
    }

    [String] getCoreVersion() {
return ($this.invoke("--version") | 
            Select-Object -First 1) -replace '[^.0-9]', ''
    }

    [Int32] setDefaultVersion([int] $version) {
        if (($version -lt 1) -or ($version -gt 2)) {
            throw "Invalid version number $version"
        }
        $this.invoke("--set-default-version $version")
        return $this.LastExitCode
    }

    [String] getDefaultVersion() {
        # Get the default wsl version
        return Get-ItemPropertyValue `
            -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss `
            -Name DefaultVersion
    }
}
