
using module "..\Application\ServiceLocator.psm1"
using module "..\Application\AppConfig.psm1"
using module "..\Service\WslService.psm1"

Class DockerFile
{

    [String] $path
    [String] $from
    [System.Collections.Hashtable[]] $commands
    [String[]] $bash

    DockerFile ([String] $path)
    {
        $this.path = Resolve-Path -Path $path -ErrorAction Stop
    }


    # Normalize DockerFile Build style commands to hash array of commands
    [System.Collections.Hashtable[]] parse()
    {
        # Supported Instructions
        $instructions = @(
            'maintainer', 'from', 'user', 'run', 'add', 'copy', 'arg', 'env', 'expose',
            'cmd', 'onbuild', 'workdir', 'entrypoint'
        )

        if ($this.commands) { return $this.commands }

        $this.commands = @{}
        Get-Content $this.path | ForEach-Object {
            # ignore blank and comment lines
            if ($_ -match "^\s*$") { Return }
            if ($_ -match "^\s*#") { Return }

            $segments = $_ -Split " ", 2
            if ($segments.length -lt 2 -Or -Not ($instructions -contains $segments[0].ToLower()))
            {
                Write-Host "Warning: Unsupported command '$_' (ignored)" -ForegroundColor Yellow
                Return
            }

            $segments[0] = $segments[0].ToLower()
            switch ($segments[0].ToLower())
            {
                { @('from') -contains $_ }
                {
                    $this.commands += @{ $segments[0] = $segments[1] }
                    $this.from = $segments[1]
                }
                { @('maintainer', 'user', 'run', 'add', 'copy', 'expose', 'workdir') -contains $_ }
                {
                    $this.commands += @{ $segments[0] = $segments[1] }
                }
                { @('entrypoint', 'cmd') -contains $_ }
                {
                    $this.commands += @{ $segments[0] = ($segments[1] | ConvertFrom-Json ) }
                }
                arg
                {
                    $commands_args = $segments[1] -Split "=", 2
                    if ($commands_args.length -eq 2) { $this.commands += @{ "arg" = $commands_args } }
                }
                env
                {
                    if ($segments[1] -match "^[a-zA-Z_].[a-zA-Z0-9_]+?=(`"|')[^`"']*?\1$" )
                    {
                        $this.commands += @{ "env" = $segments[1] }
                        Return
                    }

                    $env_array = $segments[1] -Split " "
                    $env_pattern = "^[a-zA-Z_].[a-zA-Z0-9_]+?=.+$"
                    switch ($env_array.length)
                    {
                        1
                        {
                            # env test=true
                            $this.commands += @{ "env" = $segments[1] }
                            Return
                        }
                        2
                        {
                            # env test=true
                            $invalid_members = $segments[1].Where( { $_ -notmatch $env_pattern })
                            if ($invalid_members.length -eq 0)
                            {
                                $this.commands += @{ "env" = $segments[1] }
                                Return
                            }
                            # env test true
                            $this.commands += @{ "env" = $env_array -Join "=" }
                        }
                        Default
                        {
                            # env test true OR
                            # env test=true key=value ... OR
                            # env test this is the string of the test env value
                            $invalid_members = $env_array.Where( { $_ -notmatch $env_pattern })
                            if ($invalid_members.length -eq 0)
                            {
                                # env test=true key=value ...
                                $this.commands += @{ "env" = $segments[1] }
                                Return
                            }
                            # env test this is the string of the test env value
                            # => env test="this is the string of the test env value"
                            $env_key, $env_string = $env_array
                            $this.commands += @{ "env" = (@(
                                        $env_key,
                                        ( '"' + ( $env_string -Join " " ) + '"')
                                    ) -Join "="
                                )
                            }
                        }
                    }
                }

            }
        }
        return $this.commands
    }

    [String[]] toBash()
    {
        if ($this.bash) { return $this.bash }

        $wslService = [WslService]([ServiceLocator]::getInstance().get('wsl-wrapper'))
        $version = ([AppConfig][ServiceLocator]::getInstance().get('config')).Version

        $pwdInWsl = $wslService.wslPath((Get-Item $this.path).Directory)

        $this.bash = @(
            "#!/usr/bin/env bash",
            "# The script is generated from a Dockerfile via wslctl v$version "
        )
        $bashEndOfHeader = @(
            "`n# -- Automatic change working directory:",
            "cd $pwdInWsl",
            "`n# -- Converted commands:"
        )

        $this.parse() | ForEach-Object {
            $key = $_.keys[0]
            $values = $_.values
            switch ($key)
            {
                "from" { $this.bash += "# The Original DockerFile is from image : $values" }
                "maintainer" { $this.bash += "# Original DockerFile Maintainer: $values" }
                "run" { $this.bash += $bashEndOfHeader + "$values" ; $bashEndOfHeader = @() }
                "arg" { $this.bash += $bashEndOfHeader + $values -Join "=" ; $bashEndOfHeader = @() }
                "env" { $this.bash += $bashEndOfHeader + "export $values" + "echo 'export $values'>> ~/.bashrc" ; $bashEndOfHeader = @() }
                "user" { $this.bash += $bashEndOfHeader + "su - $values" ; $bashEndOfHeader = @() }
                "copy" { $this.bash += $bashEndOfHeader + "cp $values" ; $bashEndOfHeader = @() }
                Default { Write-Host "Warning: Unimplemented command '$_' (ignored)" -ForegroundColor Yellow }
            }
        }
        return $this.bash
    }
}