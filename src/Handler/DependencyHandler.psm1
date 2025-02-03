using module Microsoft.PowerShell.Security
using module "..\Application\ServiceLocator.psm1"
using module "..\Application\AppConfig.psm1"


Class DependencyHandler
{
    [bool]$dependenciesResolved=$false
    [System.Collections.Hashtable]$PowerScriptVersionTable

    DependencyHandler ([System.Collections.Hashtable]$PowerScriptVersionTable)
    {
        $appConfig = ([AppConfig][ServiceLocator]::getInstance().get('config'))
        if ($appConfig.ContainsKey("dependenciesResolved"))
        {
            $this.dependenciesResolved = appConfig.dependenciesResolved
        }
        $this.PowerScriptVersionTable = $PowerScriptVersionTable
    }

    [void] handle ()
    {

        if (-not $this.dependenciesResolved) {
            if (($this.PowerScriptVersionTable.PSVersion.Major) -lt 5) {
                Write-Host 'PowerShell 5 or later is required' -ForegroundColor 'DarkRed'
                Write-Host "Upgrade PowerShell: 'https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-windows?view=powershell-7.1'" -ForegroundColor 'DarkRed'
                exit 1
            }

            if ([Environment]::OSVersion.Version.Major -lt 10) {
                Write-Host  'Upgrade to Windows 10+ before running this script' -ForegroundColor 'DarkRed'
                exit 2
            }

            if ((Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ReleaseId -lt 1803) {
                Write-Host 'You need to run Windows Update and install Feature Updates to at least version 1803' -ForegroundColor 'DarkRed'
                exit 3
            }

            if (('Unrestricted', 'RemoteSigned') -notcontains (Get-ExecutionPolicy)) {
                Write-Host  'The execution policy on your machine is Restricted, but it must be opened up for this' -ForegroundColor 'DarkRed'
                Write-Host  'installer with:' -ForegroundColor 'DarkRed'
                Write-Host  'Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force' -ForegroundColor 'DarkRed'
                exit 4
            }

            if (!(Get-Command 'wsl' -ErrorAction SilentlyContinue)) {
                Write-Host 'You need Windows Subsystem for Linux setup before the rest of this script can run.' -ForegroundColor 'DarkRed'
                Write-Host 'See https://docs.microsoft.com/en-us/windows/wsl/install-win10 for more information' -ForegroundColor 'DarkRed'
                Write-Host "or use the '$PSScriptRoot\files\wslctl-setup.ps1" -ForegroundColor 'DarkRed'
                Write-Host 'PowerShell script.' -ForegroundColor 'DarkRed'
                exit 4
            }
            ([AppConfig][ServiceLocator]::getInstance().get('config')).Add("dependenciesResolved", $true)
        }
    }
}
