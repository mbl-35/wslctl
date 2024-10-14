
using module "..\Application\ServiceLocator.psm1"
using module "..\Application\AppConfig.psm1"
using module "..\Application\AbstractController.psm1"
using module "..\Service\RegistryService.psm1"
using module "..\Service\BuilderService.psm1"
using module "..\Service\WslService.psm1"
using module "..\Tools\FileUtils.psm1"
using module "..\Tools\ExtendedConsole.psm1"


Class DefaultController : AbstractController {

    DefaultController() : base() {
    }

    [void] create([Array] $Arguments) {
        $this._assertArgument( $Arguments, 0, 4 )
        $wslService = [WslService][ServiceLocator]::getInstance().get('wsl-wrapper')
        $registryService = [RegistryService][ServiceLocator]::getInstance().get('registry')

        $wslName = $null
        $from = $null
        $archive = $null
        $wslVersion = $wslService.getDefaultVersion()
        $createUser = $true

        # Parse Arguments
        $NoOptionsArguments = @()
        foreach ($element in $Arguments) {
            switch -regex ($element) {
                --no-user { $createUser = $false }
                --v1 { $wslVersion = 1 }
                --v2 { $wslVersion = 2 }
                Default {
                    if ( $NoOptionsArguments.Count -lt 2 ) { $NoOptionsArguments += $element }
                    else { throw "Invalid parameter" }
                }
            }
        }

        $this._assertArgument( $NoOptionsArguments, 1, 2 )
        if ($NoOptionsArguments[0] -cmatch '.*(.tar.gz|.tgz|.tar)$') {
            $archive, $NoOptionsArguments = $NoOptionsArguments
            if ( $null -eq $NoOptionsArguments ) { throw "Invalid parameter: wslName mandatory" }
            if (-Not ($NoOptionsArguments -match '[^:]+:[^:]+')) { throw "Invalid parameter: wslName need version for import" }
        }
        $from, $wslName = $NoOptionsArguments
        if ( $null -eq $wslName) { $wslName = ($from -creplace '^[^/]*/', '') -creplace ':[^:]*$', '' }
        if (-not ($wslName -cmatch '^[a-z0-9-]+$')) { throw "$wslName instance name is not valid" }


        Write-Host "* Create $wslName from $from"

        Write-Host "Check import requirements ..."
        $wslService.checkBeforeImport($wslName)

        if ( $null -eq $archive) {
            Write-Host "Download distribution '$from' ..."
            $archive = $registryService.pull($from)
        }

        Write-Host "Create wsl instance '$wslName' (wsl-version: $wslVersion)..."
        $wslService.import(
            $wslName,
            $from,
            $archive,
            $wslVersion,
            $createUser
        )

        Write-Host "* $wslName created"
    }


    [void] status([Array] $Arguments) {
        $this._assertArgument( $Arguments, 0, 1 )
        $wslService = [WslService][ServiceLocator]::getInstance().get('wsl-wrapper')

        if ($Arguments.count -eq 0) {
            # List all wsl instance status
            # Remove wsl List header and display own
            Write-Host "Wsl instances status:" -ForegroundColor Yellow
            $wslList = $wslService.list()
            if ($wslList.Count -eq 0 ) {
                throw "No instance set"
            }
            $wslList.GetEnumerator() | ForEach-Object {
                [ExtendedConsole]::WriteColor( @(
                        $("{0,1} " -f "$(If ($($_.default)) {"*"} Else {" "})"),
                        $("{0,-23} " -f "$($_.name)"),
                        $("{0,-15} " -f "$(If ($($_.running)) {"Running"} Else {"Stopped"})"),
                        $("{0,1}" -f "$($_.wslVersion)")
                    ),
                    @("White", "Green", "White", "White"))
            }
        }
        else {
            # List status for specific wsl instance
            $wslName = $Arguments[0]
            if (-Not $wslService.exists($wslName)) {
                throw "No instance named '$wslName' found"
            }
            [ExtendedConsole]::WriteColor($wslService.status($wslName), "White")
        }
    }

    [void] start([Array] $Arguments) {
        $this._assertArgument( $Arguments, 1)

        $wslName = $Arguments[0]
        $wslService = [WslService][ServiceLocator]::getInstance().get('wsl-wrapper')

        if (-Not $wslService.exists($wslName)) {
            throw "No instance named '$wslName' found"
        }

        if ($wslService.start($wslName) -eq 0) {
            Write-Host "*  $wslName started"
        }
    }

    [void] stop([Array] $Arguments) {
        $this._assertArgument( $Arguments, 1 )

        $wslName = $Arguments[0]
        $wslService = [WslService][ServiceLocator]::getInstance().get('wsl-wrapper')

        if (-Not $wslService.exists($wslName)) {
            throw "No instance named '$wslName' found"
        }

        if ($wslService.terminate($wslName) -eq 0) {
            Write-Host "*  $wslName stopped"
        }
    }


    [void] rename ([Array] $Arguments) {
        $this._assertArgument( $Arguments, 2 )

        $wslCurrentName = $Arguments[0]
        $wslNewName = $Arguments[1]
        $wslService = [WslService][ServiceLocator]::getInstance().get('wsl-wrapper')

        if (-Not $wslService.exists($wslCurrentName)) {
            throw "No instance named '$wslCurrentName' found"
        }
        if ($wslService.exists($wslNewName)) {
            throw "Could not rename, instance '$wslNewName' already exists"
        }
        Write-Host ('-' * 79) -ForegroundColor Yellow
        Write-Host "WARNING: This functionalite require to shutdown all WSL Instances."  -ForegroundColor Yellow
        Write-Host ('-' * 79)  -ForegroundColor Yellow
        'Press any key to continue...'
        [System.Console]::ReadKey()

        if ($wslService.rename($wslCurrentName, $wslNewName) -eq 0) {
            Write-Host "*  $wslCurrentName renamed to $wslNewName"
        }
    }

    [void] remove ([Array] $Arguments) {
        $this._assertArgument( $Arguments, 1 )

        $wslName = $Arguments[0]
        $wslService = [WslService][ServiceLocator]::getInstance().get('wsl-wrapper')

        if (-Not $wslService.exists($wslName)) {
            throw "No instance named '$wslName' found"
        }

        if ($wslService.remove($wslName) -eq 0) {
            Write-Host "*  $wslName removed"
        }
    }

    [void] list ([Array] $Arguments) {
        $this._assertArgument( $Arguments, 0)

        Write-Host "Wsl instances:" -ForegroundColor Yellow
        $wslService = [WslService][ServiceLocator]::getInstance().get('wsl-wrapper')
        $wslList = $wslService.list()
        if ($wslList.Count -eq 0 ) {
            throw "No instance set"
        }
        $wslList.GetEnumerator() | ForEach-Object {
            [ExtendedConsole]::WriteColor( @(
                    $("{0,1} " -f "$(If ($($_.default)) {"*"} Else {" "})"),
                    $("{0,-23} " -f "$($_.name)"),
                    $("{0,-20} " -f "$($_.creation)"),
                    $("{0}" -f (' ' * 4) + "$($_.from)")
                ),
                @("White", "Green", "White", "White"))
        }
    }

    [void] exec ([Array] $Arguments) {
        $this._assertArgument( $Arguments, 1, 50)

        ([string]$wslName, [array]$commandline) = $Arguments
        if ($null -eq $commandline ) { $commandline = @() }
        $wslService = [WslService][ServiceLocator]::getInstance().get('wsl-wrapper')

        if ($Arguments.Count -eq 1) {
            # No commands: connect to distribution
            Write-Host "Connect to $wslName ..." -ForegroundColor Yellow
            $wslService.connect($wslName)
            return
        }

        # Script file execution
        if (Test-Path $commandline[0] -PathType leaf) {
            ([string]$script, [array]$scriptArgs) = $commandline
            $scriptNoPath = Split-Path $script -Leaf
            Write-Host "Execute $scriptNoPath on $wslName ..." -ForegroundColor Yellow
            if ($wslService.exec($wslName, $script, $scriptArgs) -ne 0) {
                throw "Command result with errors"
            }
            return
        }

        # Inline Script execution
        Write-Host "Execute command '$commandline' on $wslName ..." -ForegroundColor Yellow
        if ($wslService.exec($wslName, $commandline) -ne 0) {
            throw "Command result with errors"
        }
    }

    [void] build ([Array] $Arguments) {
        $this._assertArgument( $Arguments, 0, 4)

        $dryRun = $false
        # Default file name in directory
        $wslFilePath = (Get-Location).Path
        $tag = $null
        $tagTxt = $dryRunTxt = ""
        # Parse arguments
        for ($index = 0; $index -lt $Arguments.length; $index++) {
            switch -regex ($Arguments[$index]) {
                --dry-run {
                    $dryRun = $true
                    $dryRunTxt = "DryRun - "
                }

                '--tag=[^ ]+' {
                    $tag = ($Arguments[$index] -Split ("="))[1]
                    #$index++
                    $tagTxt = " '$tag' with"
                }
                Default {
                    if ($Arguments[$index].StartsWith("--")) {
                        throw "Invalid option $($Arguments[$index])"
                    }
                    $wslFilePath = $Arguments[$index]
                }
            }
        }

        Write-Host "$($dryRunTxt)Building$($tagTxt) $wslFilePath" -ForegroundColor Yellow
        $builder = [BuilderService][ServiceLocator]::getInstance().get('builder')
        $builder.build($wslFilePath, $tag, $dryRun)
        Write-Host "* Wsl built"
    }


    [void] halt ([Array] $Arguments) {
        $this._assertArgument( $Arguments, 0)

        $wslService = [WslService][ServiceLocator]::getInstance().get('wsl-wrapper')
        $wslService.shutdown()
        Write-Host "* Wsl halted"
    }

    [void] upgrade ([Array] $Arguments) {
        $this._assertArgument( $Arguments, 0)

        $wslService = [WslService][ServiceLocator]::getInstance().get('wsl-wrapper')
        $wslService.upgrade()
    }

    [void] default([Array] $Arguments) {
        $this._assertArgument( $Arguments, 0, 1)
        $wslService = [WslService][ServiceLocator]::getInstance().get('wsl-wrapper')

        if ($Arguments.count -eq 0) {
            Write-Host $wslService.getDefaultDistribution()
        }
        else {
            $wslName = $Arguments[0]
            if (-Not $wslService.exists($wslName)) {
                throw "No instance named '$wslName' found"
            }

            if (  $wslService.setDefaultDistribution($wslName) -ne 0) {
                throw "Unable to set wsl default distribution to $wslName"
            }
            Write-Host "* wsl default distribution set to $wslName"
        }
    }


    [void] version([Array] $Arguments) {
        $this._assertArgument( $Arguments, 1, 2)
        $wslService = [WslService][ServiceLocator]::getInstance().get('wsl-wrapper')

        if ($Arguments.count -eq 1) {
            # default : display wsl default version
            # not default: display wsl name instance version
            if ('default' -eq $Arguments[0]) {
                Write-Host $wslService.getDefaultVersion()
            }
            else {
                $wslName = $Arguments[0]
                if (-Not $wslService.exists($wslName)) {
                    throw "No instance named '$wslName' found"
                }
                Write-Host $wslService.version($wslName)
            }
        }
        else {
            # args: default + wslversion to set
            $wslDefaultVersion = $Arguments[1]
            if ( $wslService.setDefaultVersion($wslDefaultVersion) -ne 0) {
                throw "Unable to set wsl default version to $wslDefaultVersion"
            }
            Write-Host "* wsl default version set to $wslDefaultVersion"
        }


    }

    [void] convert ([Array] $Arguments) {
        $this._assertArgument( $Arguments, 2)
        $wslService = [WslService][ServiceLocator]::getInstance().get('wsl-wrapper')

        $wslName = $Arguments[0]
        $versionToSet = [int32]$Arguments[1]

        Write-Host "Convert '$wslName' to version $versionToSet"
        Write-Host "Checking instance exists ..."
        if (-Not $wslService.exists($wslName)) {
            throw "No instance named '$wslName' found"
        }

        $actualVersion = $wslService.version($wslName)
        Write-Host "Checking instance version ..."
        if ($actualVersion -eq $versionToSet) {
            Write-Host "* wsl inscance '$wslName' already set with version $versionToSet"
            return
        }

        Write-Host "Converting '$wslName' from version $actualVersion to $versionToSet ..."
        if ($wslService.convert($wslName, $versionToSet) -ne 0) {
            throw "Enable to convert instance '$wslName' to version $versionToSet ..."
        }
        Write-Host "* wsl instance '$wslName' converted to $versionToSet"
    }

    [void] __version([Array] $Arguments) {
        $this._assertArgument( $Arguments, 0)
        # display software version
        $version = ([AppConfig][ServiceLocator]::getInstance().get('config')).version
        [ExtendedConsole]::WriteColor($version)
    }

    [void] __help([Array] $Arguments) {
        $this.help($Arguments)
    }

    [void] help([Array] $Arguments) {
        $this._assertArgument( $Arguments, 0)

        $titleColor = "Yellow"
        $highlightColor = "Green"
        $foregroundColor = "White"

        [ExtendedConsole]::WriteColor()
        [ExtendedConsole]::WriteColor("Usage:", $titleColor)
        [ExtendedConsole]::WriteColor("   wslctl COMMAND [ARG...]", $foregroundColor)
        [ExtendedConsole]::WriteColor("   wslctl [ --help | --version ]", $foregroundColor)

        # Wsl management
        [ExtendedConsole]::WriteColor()
        [ExtendedConsole]::WriteColor("Wsl managment commands:", $titleColor)
        @(
            @("   create  <distro_name> [<wsl_name>] [--v[1|2]     ", "Create a named wsl instance from distribution"),
            @("   convert <wsl_name> <version>                     ", "Concert instance to specified wsl version"),
            @("   rename  <wsl_name> <wsl_name>                    ", "Rename a wsl instance"),
            @("   rm      <wsl_name>                               ", "Remove a wsl instance by name"),
            @("   exec    <wsl_name> [|<file.sh>|<cmd>]            ", "Execute specified script|cmd on wsl instance by names"),
            @("   ls                                               ", "List all created wsl instance names"),
            @("   start   <wsl_name>                               ", "Start an instance by name"),
            @("   stop    <wsl_name>                               ", "Stop an instance by name"),
            @("   status [<wsl_name>]                              ", "List all or specified wsl Instance status"),
            @("   halt                                             ", "Shutdown all wsl instances"),
            @("   upgrade                                          ", "Upgrade wsl engine"),
            @("   version [|<wsl_name>|default [|<version>]]       ", "Set/get default version or get wsl instances version"),
            @("   default [|<wsl_name>]                            ", "Set/get default distribution name")
            #@("   build   [<Wslfile>] [--tag=<distro_name>]       ", "Build an instance (docker like)")
        ) | ForEach-Object { [ExtendedConsole]::WriteColor($_, @($highlightColor, $foregroundColor)) }


        # wsl distributions registry management
        [ExtendedConsole]::WriteColor()
        [ExtendedConsole]::WriteColor("Wsl distribution registry commands:", $titleColor)
        @(
            @("   registry add    <name> <remote_url>              ", "Add a registry repository to list"),
            @("   registry rm     <name>                           ", "Remove the registry repository from the list"),
            @("   registry update                                  ", "Update distribution dictionary from registry repositories"),
            @("   registry pull   <distro>                         ", "Pull remote distribution to local registry"),
            @("   registry purge                                   ", "Remove all local registry content"),
            @("   registry search <distro_pattern>                 ", "Extract defined distributions from local registry"),
            @("   registry ls                                      ", "List available distributions"),
            @("   registry repositories                            ", "List defined registry repositories")
        ) | ForEach-Object { [ExtendedConsole]::WriteColor($_, @($highlightColor, $foregroundColor)) }


        # Wsl backup management
        [ExtendedConsole]::WriteColor()
        [ExtendedConsole]::WriteColor("Wsl backup managment commands:", $titleColor)
        @(
            @("   backup create  <wsl_name> <description>          ", "Create a new backup for the specified wsl instance"),
            @("   backup rm      <backup_name>                     ", "Remove a backup by name"),
            @("   backup restore <backup_name> [--force]           ", "Restore a wsl instance from backup"),
            @("   backup search  <backup_pattern>                  ", "Find a created backup with input as pattern"),
            @("   backup ls                                        ", "List all created backups"),
            @("   backup purge                                     ", "Remove all created backups")
        ) | ForEach-Object { [ExtendedConsole]::WriteColor($_, @($highlightColor, $foregroundColor)) }

        [ExtendedConsole]::WriteColor()

    }

}
