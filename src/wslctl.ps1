###############################################################################
# Author: Seres
#
#  This is a PowerShell wrapper around the inbuilt WSL CLI.
#  It simplifies the calls to wsl, by just allowing you  to call commands with
#  a simple "wslctl" call.
#  Best used with the path to the script in your PATH.
#
#  Building Executable:
#    > Install-Module -Name ps2exe -Scope CurrentUser
#    > ps2exe wslctl.ps1
#
###############################################################################


$version = "1.0.1"
$username = "$env:UserName"
$wsl = 'c:\windows\system32\wsl.exe'

# Registry Properties
$endpoint = '\\qu1-srsrns-share.seres.lan\delivery\wsl\images'
$registryEndpoint = "$endpoint\register.json"
$registryEndpoint = "$PSScriptRoot\register.json" # TODO: remove

# Local Properties
$installLocation = "$env:LOCALAPPDATA/Wslctl"      # Installation User Directory
$wslLocaltion = "$installLocation/Instances"    # Wsl instances location storage
$cacheLocation = "$installLocation/Cache"       # Cache Location (Storage of distribution packages)
$backupLocation = "$installLocation/Backups"    # Backups Location (Storage of distribution packages)

$cacheRegistryFile = "$cacheLocation/register.json"    # Local copy of reistry endpoint
$backupRegistryFile = "$backupLocation/register.json"  # Local backup register



## ----------------------------------------------------------------------------
## Display Help informations
## ----------------------------------------------------------------------------
function Show-Help {
    Write-Host
    Write-Host  "Usage:" -ForegroundColor Yellow
    Write-Host "   wslctl COMMAND [ARG...]"
    Write-Host "   wslctl [ --help | --version ]"
    Write-Host
    # Wsl management
    Write-Host "Wsl managment commands:"  -ForegroundColor Yellow
    Write-Color -Text "   create  <wsl_name> [<distro_name>] [--v1] ", "Create a named wsl instance from distribution" -Color Green, White
    Write-Color -Text "   rm      <wsl_name>                        ", "Remove a wsl instance by name" -Color Green, White
    Write-Color -Text "   sh      <wsl_name>                        ", "Start a shell console on wsl instance by names" -Color Green, White
    Write-Color -Text "   ls                                        ", "List all created wsl instance names" -Color Green, White
    Write-Color -Text "   start   <wsl_name>                        ", "Start an instance by name" -Color Green, White
    Write-Color -Text "   stop    <wsl_name>                        ", "Stop an instance by name" -Color Green, White
    Write-Color -Text "   status [<wsl_name>]                       ", "List all or specified wsl Instance status" -Color Green, White
    Write-Color -Text "   halt                                      ", "Shutdown all wsl instances" -Color Green, White
    Write-Host

    # wsl distributions registry management
    Write-Host "Wsl distribution registry commands:"  -ForegroundColor Yellow
    Write-Color -Text "   registry update                           ", "Pull distribution registry (to cache)" -Color Green, White
    Write-Color -Text "   registry purge                            ", "Remove all local registry content (from cache)" -Color Green, White
    Write-Color -Text "   registry search <distro_pattern>          ", "Extract defined distributions from local registry" -Color Green, White
    Write-Color -Text "   registry ls                               ", "List local registry distributions" -Color Green, White
    Write-Host

    # Wsl backup management
    Write-Host "Wsl backup managment commands:"  -ForegroundColor Yellow
    Write-Color -Text "   backup create  <wsl_name> [<message>]     ", "Create a new backup for the specified wsl instance" -Color Green, White
    Write-Color -Text "   backup rm      <backup_name>              ", "Remove a backup by name" -Color Green, White
    Write-Color -Text "   backup restore <backup_name> [--force]    ", "Restore a wsl instance from backup" -Color Green, White
    Write-Color -Text "   backup ls                                 ", "List all created backups" -Color Green, White
    Write-Color -Text "   backup purge                              ", "Remove all created backups" -Color Green, White
    Write-Host
}


## ----------------------------------------------------------------------------
## Verify all installation environment
## ----------------------------------------------------------------------------
function Install-WorkingEnvironment {
    # Check install directories
    if (-Not (Test-Path -Path $cacheLocation)) {
        New-Item -ItemType Directory -Force -Path $cacheLocation | Out-Null
    }
    if (-Not (Test-Path -Path $wslLocaltion)) {
        New-Item -ItemType Directory -Force -Path $wslLocaltion | Out-Null
    }
    if (-Not (Test-Path -Path $backupLocation)) {
        New-Item -ItemType Directory -Force -Path $backupLocation | Out-Null
    }
}



###############################################################################
##
##                          GENERIC FUNCTIONS
##
###############################################################################


## ----------------------------------------------------------------------------
## Write-Host with multicolor on same line
## ----------------------------------------------------------------------------
function Write-Color {
    [CmdletBinding()]
    # @see: https://github.com/EvotecIT/PSWriteColor
    param (
        [String[]]$Text,
        [ConsoleColor[]]$Color = [ConsoleColor].White,
        [int] $StartTab = 0,
        [int] $LinesBefore = 0,
        [int] $LinesAfter = 0,
        [string] $LogFile = "",
        [string] $TimeFormat = "yyyy-MM-dd HH:mm:ss",
        [switch] $ShowTime,
        [switch] $NoNewLine
    )
    $DefaultColor = $Color[0]
    # Add empty line before
    if ($LinesBefore -ne 0) {
        for ($i = 0; $i -lt $LinesBefore; $i++) { Write-Host "`n" -NoNewline }
    }
    # Add Time before output
    if ($ShowTime) {
        Write-Host "[$([datetime]::Now.ToString($TimeFormat))]" -NoNewline
    }
    # Add TABS before text
    if ($StartTab -ne 0) {
        for ($i = 0; $i -lt $StartTab; $i++) { Write-Host "`t" -NoNewLine }
    }

    # Real deal coloring
    if ($Color.Count -ge $Text.Count) {

        for ($i = 0; $i -lt $Text.Length; $i++) {
            Write-Host $Text[$i] -ForegroundColor $Color[$i] -NoNewLine
        }
    }
    else {
        for ($i = 0; $i -lt $Color.Length ; $i++) {
            Write-Host $Text[$i] -ForegroundColor $Color[$i] -NoNewLine
        }
        for ($i = $Color.Length; $i -lt $Text.Length; $i++) {
            Write-Host $Text[$i] -ForegroundColor $DefaultColor -NoNewLine
        }
    }

    # Support for no new line
    if ($NoNewLine -eq $true) { Write-Host -NoNewline } else { Write-Host }

    # Add empty line after
    if ($LinesAfter -ne 0) {
        for ($i = 0; $i -lt $LinesAfter; $i++) { Write-Host "`n" }
    }
}

## ----------------------------------------------------------------------------
## Show-Progress displays the progress of a long-running activity, task,
## operation, etc. It is displayed as a progress bar, along with the
## completed percentage of the task. It displays on a single line (where
## the cursor is located). As opposed to Write-Progress, it doesn't hide
## the upper block of text in the PowerShell console.
## ----------------------------------------------------------------------------
function Show-Progress {
    Param(
        [Parameter()][string]$Activity = "Current Task",
        [Parameter()][ValidateScript({ $_ -ge 0 })][long]$Current = 0,
        [Parameter()][ValidateScript({ $_ -gt 0 })][long]$Total = 100
    )

    # Compute percent
    $Percentage = ($Current / $Total) * 100

    # Continue displaying progress on the same line/position
    $CurrentLine = $host.UI.RawUI.CursorPosition
    $WindowSizeWidth = $host.UI.RawUI.WindowSize.Width
    $DefaultForegroundColor = $host.UI.RawUI.ForegroundColor

    # Width of the progress bar
    if ($WindowSizeWidth -gt 70) { $Width = 50 }
    else { $Width = ($WindowSizeWidth) - 20 }
    if ($Width -lt 20) { "Window size is too small to display the progress bar"; break }

    # Default values
    $ProgressBarForegroundColor = $DefaultForegroundColor
    $ProgressBarInfo = "$Activity`: $Percentage %, please wait"

    # Adjust final values
    if ($Percentage -eq 100) {
        $ProgressBarForegroundColor = "Green"
        $ProgressBarInfo = "$Activity`: $Percentage %, complete"
    }

    # Compute ProgressBar Strings
    $ProgressBarItem = ([int]($Percentage * $Width / 100))
    $ProgressBarEmpty = $Width - $ProgressBarItem
    $EndOfLineSpaces = $WindowSizeWidth - $Width - $ProgressBarInfo.length - 3

    $ProgressBarItemStr = "=" * $ProgressBarItem
    $ProgressBarEmptyStr = " " * $ProgressBarEmpty
    $EndOfLineSpacesStr = " " * $EndOfLineSpaces

    # Display
    Write-Host -NoNewline -ForegroundColor Cyan "["
    Write-Host -NoNewline -ForegroundColor $ProgressBarForegroundColor "$ProgressBarItemStr$ProgressBarEmptyStr"
    Write-Host -NoNewline -ForegroundColor Cyan "] "
    Write-Host -NoNewline "$ProgressBarInfo$EndOfLineSpacesStr"

    if ($Percentage -eq 100) { Write-Host }
    else { $host.UI.RawUI.CursorPosition = $CurrentLine }
}


## ----------------------------------------------------------------------------
## Copy files (possible remote) with progress bar
## ----------------------------------------------------------------------------
function Copy-File {
    [CmdletBinding()]
    [OutputType('bool')]
    Param( [string]$from, [string]$to)
    $result = $true

    Write-Host  "Copy file $from -> $to"
    try {
        $ffile = [io.file]::OpenRead($from)
        $tofile = [io.file]::OpenWrite($to)

        Show-Progress -Activity "Copying file"

        [byte[]]$buff = new-object byte[] 4096
        [long]$total = [int]$count = 0
        do {
            $count = $ffile.Read($buff, 0, $buff.Length)
            $tofile.Write($buff, 0, $count)
            $total += $count
            if ($total % 1mb -eq 0) {
                Show-Progress -Activity "Copying file" -Current ([long]($total * 100 / $ffile.Length))
            }
        } while ($count -gt 0)

        Show-Progress -Activity "Copying file" -Current 100
        $ffile.Dispose()
        $tofile.Dispose()
    }
    catch {
        Write-Warning $Error[0]
        $result = $false
    }
    finally {
        if ($null -ne $ffile) { $ffile.Close() }
        if ($null -ne $tofile) { $tofile.Close() }
    }
    return $result
}


## ----------------------------------------------------------------------------
## Convert Serialized hastable to Object (recursive)
## ----------------------------------------------------------------------------
function Convert-ObjectToHashtable {
    [CmdletBinding()]
    [OutputType('hashtable')]
    Param (
        [Parameter(ValueFromPipeline)]
        $InputObject
    )
    process {
        # Return null if the input is null. This can happen when calling the function
        # recursively and a property is null
        if ($null -eq $InputObject) {
            return $null
        }

        # Check if the input is an array or collection. If so, we also need to convert
        # those types into hash tables as well. This function will convert all child
        # objects into hash tables (if applicable)
        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            $collection = @(
                foreach ($object in $InputObject) {
                    Convert-ObjectToHashtable -InputObject $object
                }
            )
            # Return the array but don't enumerate it because the object
            # may be pretty complex
            Write-Output $collection -NoEnumerate

        }
        elseif ($InputObject -is [psobject]) {
            # If the object has properties that need enumeration
            # Convert it to its own hash table and return it
            $hash = @{}
            foreach ($property in $InputObject.PSObject.Properties) {
                $hash[$property.Name] = Convert-ObjectToHashtable -InputObject $property.Value
            }
            $hash
        }
        else {
            # If the object isn't an array, collection, or other object, it's already a hash table
            # So just return it.
            $InputObject
        }
    }
}

## ----------------------------------------------------------------------------
## Validate specified argument array has number of item between min and max
## ----------------------------------------------------------------------------
function Assert-ArgumentCount {

    Param (
        [Parameter(Mandatory = $true)][string[]] $array,
        [Parameter(Mandatory = $true)][int] $minLength,
        [Parameter(Mandatory = $false)][int] $maxLength
    )
    if ($maxLength -lt $minLength) {
        $maxLength = $minLength
    }
    if ($array.count -lt $minLength) {
        Write-Host "Error: too few arguments" -ForegroundColor Red
        exit 1
    }
    if ($array.count -gt $maxLength) {
        Write-Host "Error: too many arguments" -ForegroundColor Red
        exit 1
    }
}



###############################################################################
##
##                    SIMPLE JSON FILE MANIPULATION
##
###############################################################################

## ----------------------------------------------------------------------------
## Download json file content as hashtable
## ----------------------------------------------------------------------------
function Convert-JsonToHashtable {
    [OutputType('hashtable')]
    Param( [Parameter(Mandatory = $true)][string]$jsonFile )
    $hashtable = @{}
    if (Test-Path -Path $jsonFile) {
        $hashtable = Get-Content -Path $jsonFile -Raw | ConvertFrom-JSON  | Convert-ObjectToHashtable
    }
    return $hashtable
}

## ----------------------------------------------------------------------------
## Set json file content with hashtable
## ----------------------------------------------------------------------------
function Convert-JsonFromHashtable {
    Param(
        [Parameter(Mandatory = $true)][string]$jsonFile,
        [Parameter(Mandatory = $true)][hashtable]$hashtable
    )
    $hashtable | ConvertTo-JSON | Set-Content -Path $jsonFile
}


## ----------------------------------------------------------------------------
## Test Set a key value pair to jsonfile (root key)
## ----------------------------------------------------------------------------
function Test-JsonHasKey {
    [OutputType('bool')]
    Param(
        [Parameter(Mandatory = $true)][string]$jsonFile,
        [Parameter(Mandatory = $true)][string]$key
    )
    $result = $false
    $hashtable = [hashtable](Convert-JsonToHashtable $jsonFile)
    if ($hashtable.ContainsKey($key)) { $result = $true }
    return $result
}

## ----------------------------------------------------------------------------
## Get key value from jsonfile (root key)
## ----------------------------------------------------------------------------
function Get-JsonKeyValue {
    Param(
        [Parameter(Mandatory = $true)][string]$jsonFile,
        [Parameter(Mandatory = $true)][string]$key
    )
    $result = $null
    $hashtable = [hashtable](Convert-JsonToHashtable $jsonFile)
    if ($hashtable.ContainsKey($key)) { $result = $hashtable.$key }
    return $result
}

## ----------------------------------------------------------------------------
## Set a key value pair to jsonfile (root key)
## ----------------------------------------------------------------------------
function Set-JsonKeyValue {
    Param(
        [Parameter(Mandatory = $true)][string]$jsonFile,
        [Parameter(Mandatory = $true)][string]$key,
        [Parameter(Mandatory = $true)]$value
    )
    $hashtable = [hashtable](Convert-JsonToHashtable $jsonFile)
    if ($hashtable.ContainsKey($key)) { $hashtable.Remove($key) }
    $hashtable.Add($key, $value)
    Convert-JsonFromHashtable $jsonFile $hashtable
}

## ----------------------------------------------------------------------------
## Set a key value pair to jsonfile (root key)
## ----------------------------------------------------------------------------
function Remove-JsonKey {
    Param(
        [Parameter(Mandatory = $true)][string]$jsonFile,
        [Parameter(Mandatory = $true)][string]$key
    )
    $hashtable = [hashtable](Convert-JsonToHashtable $jsonFile)
    if ($hashtable.ContainsKey($key)) {
        $hashtable.Remove($key)
        Convert-JsonFromHashtable $jsonFile $hashtable
    }
}

## ----------------------------------------------------------------------------
## List of jsonfile root keys
## ----------------------------------------------------------------------------
function Get-JsonKeys {
    [OutputType('array')]
    Param(
        [Parameter(Mandatory = $true)][string]$jsonFile
    )
    $hashtable = [hashtable](Convert-JsonToHashtable $jsonFile)
    return $hashtable.keys
}


###############################################################################
##
##                         WSL WRAPPER FUNCTIONS
##
###############################################################################

## ----------------------------------------------------------------------------
## Transform a windows path to a wsl access path
## ----------------------------------------------------------------------------
function ConvertTo-WslPath {
    [OutputType('string')]
    Param([Parameter(Mandatory = $true)][string]$path)
    wsl 'wslpath' -u $path.Replace('\', '\\');
}


## ----------------------------------------------------------------------------
## Check if a named wsl instance is Running
## ----------------------------------------------------------------------------
function Test-WslInstanceIsRunning {
    [OutputType('bool')]
    Param( [Parameter(Mandatory = $true)][string]$wslName )
    # Inexplicably, wsl --list --running produces UTF-16LE-encoded ("Unicode"-encoded) output
    # rather than respecting the console's (OEM) code page.
    $prev = [Console]::OutputEncoding; [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
    $isrunning = [bool](& $wsl --list --running | Select-String -Pattern "^$wslName *"  -quiet)
    [Console]::OutputEncoding = $prev
    if ($isRunning) { return $true; } else { return $false; }
}

## ----------------------------------------------------------------------------
## Check if a named wsl instance has been created
## ----------------------------------------------------------------------------
function Test-WslInstanceIsCreated {
    [OutputType('bool')]
    Param( [Parameter(Mandatory = $true, ValueFromPipeline = $true)][string]$wslName )
    # Inexplicably, wsl --list --running produces UTF-16LE-encoded ("Unicode"-encoded) output
    # rather than respecting the console's (OEM) code page.
    $prev = [Console]::OutputEncoding; [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
    $exists = [bool](& $wsl --list --verbose | Select-String -Pattern " +$wslName +" -quiet)
    [Console]::OutputEncoding = $prev
    if ($exists) { return $true; } else { return $false; }
}


## ----------------------------------------------------------------------------
## Array of installed distributions
## ----------------------------------------------------------------------------
function Get-WslInstances {
    [OutputType('array')]
    # Inexplicably, wsl --list --running produces UTF-16LE-encoded ("Unicode"-encoded) output
    # rather than respecting the console's (OEM) code page.
    $prev = [Console]::OutputEncoding; [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
    $result = (& $wsl --list | Select-Object -Skip 1) | Where-Object { $_ -ne "" }
    [Console]::OutputEncoding = $prev
    return $result
}


## ----------------------------------------------------------------------------
## Array of installed distribution with status
## ----------------------------------------------------------------------------
function Get-WslInstancesWithStatus {
    [OutputType('array')]
    # Inexplicably, wsl --list --running produces UTF-16LE-encoded ("Unicode"-encoded) output
    # rather than respecting the console's (OEM) code page.
    $prev = [Console]::OutputEncoding; [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
    $result = (& $wsl --list --verbose | Select-Object -Skip 1) | Where-Object { $_ -ne "" }
    [Console]::OutputEncoding = $prev
    return $result
}

## ----------------------------------------------------------------------------
## Get wsl instance status
## ----------------------------------------------------------------------------
function Get-WslInstanceStatus {
    #[OutputType('string')]
    Param( [Parameter(Mandatory = $true, ValueFromPipeline = $true)][string]$wslName )
    if (-Not (Test-WslInstanceIsCreated $wslName)) {
        return "* $wslName is not a wsl instance"
    }
    else {
        return ((Get-WslInstancesWithStatus | Select-String -Pattern " +$wslName +" | Out-String).Trim() -Split '[\*\s]+'  | Where-Object {$_})[1]
    }
}


## ----------------------------------------------------------------------------
## Remove a named wsl instance
## ----------------------------------------------------------------------------
function Remove-WslInstance {
    [OutputType('bool')]
    Param( [Parameter(Mandatory = $true, ValueFromPipeline = $true)][string]$wslName )
    if (-Not (Test-WslInstanceIsCreated $wslName)) {
        Write-Host "Error: Instance '$wslName' not found" -ForegroundColor Red
        return $false;
    }
    & $wsl --unregister $wslName
    if ($?) { return $true; } else { return $false; }
}

## ----------------------------------------------------------------------------
## Setup wsl instance default user
## ----------------------------------------------------------------------------
function Initialize-WslInstanceDefaultUser {
    [OutputType('bool')]
    Param( [Parameter(Mandatory = $true, ValueFromPipeline = $true)][string]$wslName )
    if (-Not (Test-WslInstanceIsCreated $wslName)) {
        Write-Host "Error: Instance '$wslName' not found" -ForegroundColor Red
        return $false;
    }
    & $wsl --distribution $wslName --exec /usr/sbin/addgroup --gid 1000 $username
    & $wsl --distribution $wslName --exec /usr/sbin/adduser --quiet --disabled-password --gecos `` --uid 1000 --gid 1000 $username
    & $wsl --distribution $wslName --exec /usr/sbin/usermod -aG sudo $username
    & $wsl --distribution $wslName --% /usr/bin/printf '\n[user]\ndefault=%s\n' $(/usr/bin/id -nu 1000) >> /etc/wsl.conf
    & $wsl --terminate $wslName
    return $true;
}


###############################################################################
##
##                           CACHE FUNCTIONS
##
###############################################################################


## ----------------------------------------------------------------------------
## Import wsl with cache management
## ----------------------------------------------------------------------------
function Import-Wsl {
    [OutputType('bool')]
    Param( [string]$wslName, [string]$distroName, [int]$wslVersion = 2)

    # Check wslname instance not already exists
    if (Test-WslInstanceIsCreated $wslName) {
        Write-Host "Error: Instance '$wslName' already exists" -ForegroundColor Red
        return $false
    }
    # Check target directory does not exists or is empty
    $wslNameLocation = "$wslLocaltion/$wslName"
    if (Test-Path -Path $wslNameLocation) {
        $directoryInfo = Get-ChildItem $wslNameLocation | Measure-Object
        if (-Not ($directoryInfo.count -eq 0)) {
            write-host "Error: Directory $wslNameLocation already in use" -ForegroundColor Red
            return $false
        }
    }
    # Get distroname definition
    $distroPackage = Get-JsonKeyValue $cacheRegistryFile $distroName
    if ($null -eq $distroPackage) {
        Write-Host "Error: Distribution '$distroName' not found in registry" -ForegroundColor Red
        Write-Host "  - Please use the 'update' command to refresh the registry."
        return $false
    }
    $distroEndpoint = "$endpoint\$distroPackage"
    $distroLocation = "$cacheLocation\$distroPackage"

    # Distribution Cache Management:
    if (-Not (Test-Path -Path $distroLocation)) {
        Write-Host "Dowload distribution '$distroName' ..."
        if (-Not (Copy-File $distroEndpoint $distroLocation)) {
            Write-Host "Error: Registry endpoint not reachable" -ForegroundColor Red
            return $false
        }
    }
    else {
        Write-Host "Distribution '$distroName' already cached ..."
    }

    # Instance creation
    Write-Host "Create wsl instance '$wslName'..."
    if (Test-Path -Path $wslNameLocation) {
        New-Item -ItemType Directory -Force -Path $wslNameLocation | Out-Null
    }
    & $wsl --import $wslName $wslNameLocation $distroLocation --version $wslVersion
    # Adjust Wsl Distro Name
    & $wsl --distribution $wslName sh -c "echo WSL_DISTRO_NAME=$wslName > /lib/init/wsl-distro-name.sh"
    return $true
}


###############################################################################
##
##                        BACKUP / RESTAURE FUNCTIONS
##
###############################################################################


## ----------------------------------------------------------------------------
## Backup wsl instance
## ----------------------------------------------------------------------------
function Backup-Wsl {
    [OutputType('bool')]
    Param( [string]$wslName, [string]$backupAnnotation)
    $backupdate = Get-Date -format "yyyyMMdd_HHmmss"
    $backupName = "$wslName-$backupdate"
    $backupTar = "$backupName-amd64-wsl-rootfs.tar"
    $backupTgz = "$backupTar.gz"

    # Check wslname instance already exists
    if (-Not (Test-WslInstanceIsCreated $wslName)) {
        Write-Host "Error: Instance '$wslName' does not exists" -ForegroundColor Red
        return $false
    }
    # Stop if required
    if (Test-WslInstanceIsRunning $wslName) {
        Write-Host "Stop instance '$wslName'"
        & $wsl --terminate $wslName
    }
    # Export WSL
    Write-Host "Export wsl '$wslName' to $backupTar..."
    & $wsl --export $wslName $backupTar
    Write-Host "Compress $backupTar to $backupTgz..."
    & $wsl --distribution $wslName --exec gzip $backupTar
    Write-Host "Move to backup directory..."
    Move-Item -Path $backupTgz -Destination "$backupLocation/$backupTgz" -Force

    # Finally append backup to the register
    Set-JsonKeyValue $backupRegistryFile "$wslName-$backupdate" @{
        wslname = $wslName
        message = $backupAnnotation
        archive = $backupTgz
        date    = $backupdate
    }
    return $true
}


## ----------------------------------------------------------------------------
## Restore a wsl instance
## ----------------------------------------------------------------------------
function Restore-Wsl {
    [OutputType('bool')]
    Param( [string]$backupName, [bool]$forced)

    # Read backup properties
    $backupProperties = Get-JsonKeyValue $backupRegistryFile $backupName
    if ($null -eq $backupProperties) {
        Write-Host "Error: Backup '$backupName' does not exists" -ForegroundColor Red
        return $false
    }
    $wslName = $backupProperties.wslname
    $backupTgz = $backupProperties.archive

    Write-Host "Check archive file..."
    $backupTgzLocation = "$backupLocation/$backupTgz"
    if (-Not (Test-Path -Path $backupTgzLocation)) {
        Write-Host "Error: File not found '$backupTgzLocation'" -ForegroundColor Red
        return $false
    }

    # Check if wsl instance exists and ask for confirmation if force parameter
    # is false
    if ((Test-WslInstanceIsCreated $wslName) -And (-Not $forced)) {
        Write-Host "*** WARNING ***" -ForegroundColor Yellow
        Write-Host "This action will replace the existing '$wslName' instance" -ForegroundColor Yellow
        Write-Host "with backup '$backupName'" -ForegroundColor Yellow
        While ($Selection -ne "Y" ) {
            $Selection = Read-Host "Proceed ? (Y/N)"
            Switch ($Selection) {
                Y { Write-Host "Continuing with validation" -ForegroundColor Green }
                N { Write-Host "Breaking out of script" -ForegroundColor Red; return $false ; }
                default { Write-Host "Only Y/N are Valid responses" }
            }
        }
    }

    # Remove existing instance
    if (Test-WslInstanceIsCreated $wslName) {
        Write-Host "Destroy existing '$wslName' instance..."
        if (-Not(Remove-WslInstance $wslName)) {
            return $false
        }
    }

    # Check target directory does not exists or is empty
    $wslNameLocation = "$wslLocaltion/$wslName"
    if (Test-Path -Path $wslNameLocation) {
        $directoryInfo = Get-ChildItem $wslNameLocation | Measure-Object
        if (-Not ($directoryInfo.count -eq 0)) {
            write-host "Error: Directory $wslNameLocation already in use" -ForegroundColor Red
            return $false
        }
    }

    # Instance creation
    Write-Host "Restore '$wslName' with $backupTgz..."
    if (Test-Path -Path $wslNameLocation) {
        New-Item -ItemType Directory -Force -Path $wslNameLocation | Out-Null
    }
    & $wsl --import $wslName $wslNameLocation $backupTgzLocation --version 2

    return $true
}




###############################################################################
##
##                                 MAIN
##
###############################################################################

# Patch ps2exe to keep un*x like syntax (issue #1)
# Warning: flag option only with one minus will be converted with 2 minus
if ( ($args | Where { $_ -is [bool] }) ) {
    $args = $args | Where {$_ -is [String]}                                 # Filter non string arguments
    $args = $args | ForEach-Object { $_ -replace "^-([^-].*)", "--`${1}" }  # Change -option to --option
    if ($args -is [string]) { $args = @( "$args" ) }                        # Assert args is array
}

$command = $args[0]
if ($null -eq $command -or [string]::IsNullOrEmpty($command.Trim())) {
    Write-Host 'No command supplied' -ForegroundColor Red
    exit 1
}

Install-WorkingEnvironment

# Switch Statement on input Command
switch ($command) {

    # -- WSL managment commands -----------------------------------------------

    create {
        # Instanciate new wsl instance
        Assert-ArgumentCount $args 2 5
        $wslName = $null
        $distroName = $null
        $wslVersion = 2
        $createUser = $true

        $null, $args = $args
        foreach ($element in $args) {
            switch ($element) {
                --no-user { $createUser = $false }
                --v1      { $wslVersion = 1 }
                Default {
                    if ( $null -eq $wslName ) { $wslName = $element }
                    elseif ( $null -eq $distroName ) { $distroName = $element }
                    else {
                        Write-Host "Error: Invalid parameter" -ForegroundColor Red
                        exit 1
                    }
                }
            }
        }

        if ( $null -eq $distroName) { $distroName = $wslName }

        Write-Host "* Import $wslName"
        if (-Not (Import-Wsl $wslName $distroName $wslVersion)) { exit 1 }

        # Create default wsl user
        if ($createUser) {
            Write-Host "* Create default wsl user"
            if (-Not (Initialize-WslInstanceDefaultUser $wslName )) { exit 1 }
        }

        # Restart instance
        Write-Host "* $wslName created"
        Write-Host "  Could be started with command: wslctl start $wslName"
    }

    { @("rm", "remove") -contains $_ } {
        # Remove the specified wsl instance
        Assert-ArgumentCount $args 2
        $wslName = $args[1]
        if (Remove-WslInstance $wslName) {
            Write-Host "*  $wslName removed"
        }
    }

    { @("ls", "list") -contains $_ } {
        # List all wsl installed
        Assert-ArgumentCount $args 1
        Write-Host "Wsl instances:" -ForegroundColor Yellow
        Get-WslInstances | ForEach-Object { (" " * 2) + $_ } | Sort-Object
    }

    start {
        # Starts wsl instance by starting a long bash background process in it
        Assert-ArgumentCount $args 2
        $wslName = $args[1]
        & $wsl --distribution $wslName bash -c "nohup sleep 99999 </dev/null >/dev/null 2>&1 & sleep 1"
        if ($?) { Write-Host "*  $wslName started" ; }
    }

    stop {
        # Stop wsl instances
        Assert-ArgumentCount $args 2
        $wslName = $args[1]
        & $wsl --terminate $wslName
        if ($?) { Write-Host "*  $wslName stopped" }
    }

    status {
        Assert-ArgumentCount $args 1 2
        if ($args.count -eq 1) {
            # List all wsl instance status
            # Remove wsl List header and display own
            Write-Host "Wsl instances status:" -ForegroundColor Yellow
            Get-WslInstancesWithStatus
        }
        else {
            # List status for specific wsl instance
            $wslName = $args[1]
            Get-WslInstanceStatus $wslName
        }
    }
    sh {
        Assert-ArgumentCount $args 2
        $wslName = $args[1]
        # Check wslname instance already exists
        if (-Not (Test-WslInstanceIsCreated $wslName)) {
            Write-Host "Error: Instance '$wslName' does not exists" -ForegroundColor Red
            exit 1
        }
        & $wsl --distribution $wslName
    }
    exec {
        Assert-ArgumentCount $args 3
        $wslName = $args[1]
        $script = $args[2]

        # Check wslname instance already exists
        if (-Not (Test-WslInstanceIsCreated $wslName)) {
            Write-Host "Error: Instance '$wslName' does not exists" -ForegroundColor Red
            exit 1
        }

        # Check script extension
        if (-Not ([IO.Path]::GetExtension($script) -eq '.sh')) {
            Write-Host "Error: script has to be a shell file (.sh)" -ForegroundColor Red
            exit 1
        }
        # Resolv windows full path to the script
        try { $winScriptFullPath = Resolve-Path -Path $script -ErrorAction Stop }
        catch {
            Write-Host "Error: script path not found" -ForegroundColor Red
            exit 1
        }
        $scriptInWslPath = ConvertTo-WslPath $winScriptFullPath
        $scriptNoPath = Split-Path $script -leaf
        $scriptTmpFile = "/tmp/$scriptNoPath"

        # Copy script file to instance
        Write-Host "Execute $scriptNoPath on $wslName ..." -ForegroundColor Yellow
        # pass Original path to the script
        & $wsl --distribution $wslName --exec cp $scriptInWslPath $scriptTmpFile
        & $wsl --distribution $wslName --exec chmod +x $scriptTmpFile
        & $wsl --distribution $wslName --exec SCRIPT_WINPATH=$scriptInWslPath $scriptTmpFile "$scriptInWslPath"
        & $wsl --distribution $wslName --exec rm $scriptTmpFile
    }

    halt {
        # stop all wsl instances
        Assert-ArgumentCount $args 1
        & $wsl --shutdown
        Write-Host "* Wsl halted"
    }


    # -- Wsl distribution registry commands ---------------------------------

    registry {
        Assert-ArgumentCount $args 2 3
        $subCommand = $args[1]

        switch ($subCommand) {

            update {
                # Update the cache registry file (in cache)
                Assert-ArgumentCount $args 2
                if (-Not (Copy-File $registryEndpoint $cacheRegistryFile)) {
                    Write-Host "Error: Registry endpoint not reachable" -ForegroundColor Red
                    exit 1
                }
                Write-Host "* Local registry updated"
            }

            purge {
                # remove the cache directory
                Assert-ArgumentCount $args 2
                Remove-Item -LiteralPath $cacheLocation -Force -Recurse -ErrorAction Ignore | Out-Null
                Write-Host "* Local registry cache cleared"
            }

            search {
                # Search available distribution by regexp
                Assert-ArgumentCount $args 3
                $pattern = $args[2]
                Write-Host "Available distributions from pattern '$pattern':" -ForegroundColor Yellow
                Get-JsonKeys $cacheRegistryFile | Select-String -Pattern ".*$pattern.*" | ForEach-Object { $_.Matches } | ForEach-Object { (" " * 2) + $_ } | Sort-Object
            }

            { @("ls", "list") -contains $_ } {
                # List register keys
                Assert-ArgumentCount $args 2
                Write-Host "Available Distributions (installable):" -ForegroundColor Yellow
                Get-JsonKeys $cacheRegistryFile | ForEach-Object { (" " * 2) + $_ } | Sort-Object
            }

            Default {
                Write-Host "Error: Command '$command $subCommand' is not defined" -ForegroundColor Red
                exit 1
            }
        }
    }

    # -- Wsl backup management commands ---------------------------------------

    backup {
        Assert-ArgumentCount $args 2 4
        $subCommand = $args[1]

        switch ($subCommand) {
            create {
                # Backup a existing wsl instance
                Assert-ArgumentCount $args 3 4
                $wslName = $args[2]
                if ($args.count -eq 3) { $backupAnnotation = "" }
                else { $backupAnnotation = $args[3] }

                Write-Host "* Backup '$wslName'"
                if (-Not (Backup-Wsl $wslName $backupAnnotation)) { exit 1 }
                Write-Host "* Backup complete"
            }

            restore {
                # Restore a previously backuped wsl instance
                Assert-ArgumentCount $args 3 4
                $backupName = $args[2]
                $forced = $false
                if ($args.count -eq 4) {
                    if ($args[3] -ne "--force") {
                        Write-Host 'Error: invalid parameter' -ForegroundColor Red
                        exit 1
                    }
                    $forced = $true
                }
                Write-Host "* Restore '$backupName'"
                if (-Not (Restore-Wsl $backupName $forced)) { exit 1 }
                Write-Host "* Restore complete"
            }

            purge {
                # Remove the backup directory
                Assert-ArgumentCount $args 2
                Remove-Item -LiteralPath $backupLocation -Force -Recurse -ErrorAction Ignore | Out-Null
                Write-Host "* Backup storage cleared"
            }

            { @("rm", "remove") -contains $_ } {
                # Remove a backup by name
                Assert-ArgumentCount $args 3
                $backupName = $args[2]

                $backupProperties = Get-JsonKeyValue $backupRegistryFile $backupName
                if ($null -eq $backupProperties) {
                    Write-Host "Error: Backup '$backupName' does not exists" -ForegroundColor Red
                    return $false
                }
                $backupTgz = $backupProperties.archive
                $backupTgzFile = "$backupLocation/$backupTgz"
                if (Test-Path -Path $backupTgzFile) {
                    Write-Host "Delete Archive $backupTgz..."
                    Remove-Item -Path $backupTgzFile -Force -ErrorAction Ignore | Out-Null
                }
                Write-Host "Delete backup registry entry..."
                Remove-JsonKey $backupRegistryFile $backupName
                Write-Host "* Backup '$backupName' removed"
            }

            { @("ls", "list") -contains $_ } {
                # List backup resister keys
                Assert-ArgumentCount $args 2
                Write-Host "Available Backups (recoverable):" -ForegroundColor Yellow
                $backupArray = Convert-JsonToHashtable $backupRegistryFile
                $backupArray.keys | ForEach-Object { "  {0}`t`t - {1}" -f $_, $backupArray.$_.message }
            }

            Default {
                Write-Host "Error: Command '$command $subCommand' is not defined" -ForegroundColor Red
                exit 1
            }
        }
    }


    # -- Others commands ------------------------------------------------------

    { @("--version", "version") -contains $_ } { Write-Host "$version" }

    { @("--help", "help") -contains $_ } { Show-Help }


    # -- Undefined commands ---------------------------------------------------
    Default {
        Write-Host "Error: Command '$command' is not defined" -ForegroundColor Red
        exit 1
    }
}
