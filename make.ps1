# Independent Make (vs. InvokeBuild which cannot
param (
    [string] $cmd = $null
)


$Settings = @{

    AppName = "wslctl"

    # List of files to concat (in order)
    AppFilesOrderList = @(
        "Model\JsonHashtableFile.psm1",
        "Application\AbstractController.psm1",
        "Application\AppConfig.psm1",
        "Handler\DependencyHandler.psm1",
        "Application\ControllerManager.psm1",
        "Application\ControllerResolver.psm1",
        "Application\ServiceLocator.psm1",
        "Controller\BackupController.psm1",
        "Controller\DefaultController.psm1",
        "Controller\RegistryController.psm1",
        "Model\DockerFile.psm1",
        "Model\Registry.psm1",
        "Model\WslElement.psm1",
        "Service\BackupService.psm1",
        "Service\BuilderService.psm1",
        "Service\RegistryService.psm1",
        "Service\WslService.psm1",
        "Tools\Downloader.psm1",
        "Tools\ExtendedConsole.psm1",
        "Tools\FileUtils.psm1",
        "wslctl.ps1"
    )

    # Where to find source files
    SourceFolder = "$PSScriptRoot\src"
    # Test Folder
    TestFolder = "$PSScriptRoot\tests"
    # Building Output Folder
    BuildFolder = "$PSScriptRoot\build"
    # Forder where to place files to archive the release
    ArchSourceFolder = "$PSScriptRoot\build\tmp"
    # Distribution Folder (.zip files)
    DistFolder = "$PSScriptRoot\build\dist"
    # Resource folder
    ResourceFolder = "$PSScriptRoot\files"

    # Test Module/Package dependencies to install
    TestDependency = @(
        'Pester',
        'PsScriptAnalyzer'
    )
    BuildDependency = @(  )
}


# --------------------  CLEAN TASK -------------------------

function Clean_Task
{
    Set-BuildHeader "clean"
    if (Test-Path -Path $Settings.BuildFolder) {
        "Removing existing files and folders in $($Settings.BuildFolder)"
        Get-ChildItem $Settings.BuildFolder | Remove-Item -Force -Recurse
    }
    else {
        "$($Settings.BuildFolder) is not present, nothing to clean up."
        Assert-BuildFolder
    }
}


# --------------------  Install_Dependencies TASK -------------------------

function Install_Dependencies_Task ([String]$conf)
{
    Set-BuildLine "install_Dependencies"
    Write-Host "dependencies conf: $conf"
    switch ($conf) {
        tests { $Dependencies = $Settings.TestDependency }
        release { $Dependencies = $Settings.BuildDependency }
        all { $Dependencies = ($Settings.TestDependency + $Settings.BuildDependency) | Select-Object -Unique }
    }
    Foreach ( $Depend in $Dependencies ) {
        "Installing test dependency : $Depend"
        if ( $Depend -eq 'Selenium.WebDriver' ) {
            Install-Package $Depend -Source nuget.org -Force
        }
        else {
            if (-not(Get-Module -Name  $Depend -ListAvailable)) {
                Install-Module $Depend -Scope CurrentUser -Force -SkipPublisherCheck
            }
            Import-Module $Depend -Force
        }
    }
}

# ---------------------- TEST TASKS ----------------------------

function Unit_Tests_Task
{
    Set-BuildLine 'Unit Tests'
    # Launch Pester Unit test Suite
    $UnitTestSettings =  @{
        Script = "$($Settings.TestFolder)\unit"
        OutputFormat = 'NUnitXml'
        OutputFile = "$($Settings.BuildFolder)\UnitTestsResult.xml"
        PassThru = $True
    }

    if (-Not(Test-Path $UnitTestSettings.Script -PathType Container)) {
        Write-Warning "No unit tests defined - skip"
        $Script:UnitTestsResult = @{ FailedCount = 0}
    }
    else {
        Assert-BuildFolder
        $Script:UnitTestsResult = Invoke-Pester @UnitTestSettings
        $FailureMessage = '{0} Unit test(s) failed. Aborting build' -f $UnitTestsResult.FailedCount
        Assert-Build ($UnitTestsResult.FailedCount -eq 0) $FailureMessage
    }
}

function Integration_Tests_Task
{
    Set-BuildLine 'Integration Tests'
    $IntegrationTestSettings =  @{
        Script = "$($Settings.TestFolder)\integration"
        OutputFile = "$($Settings.BuildFolder)\IntegrationTestsResult.xml"
        PassThru = $True
    }
    if (-Not(Test-Path $IntegrationTestSettings.Script -PathType Container)) {
        Write-Warning "No integration tests defined - skip"
        $Script:IntegrationTestsResult = @{ FailedCount = 0}
    }
    else {
        Assert-BuildFolder
        $Script:IntegrationTestsResult = Invoke-Pester @IntegrationTestSettings
        $FailureMessage = '{0} Integration test(s) failed. Aborting build' -f $IntegrationTestsResult.FailedCount
        Assert-Build ($IntegrationTestsResult.FailedCount -eq 0) $FailureMessage
    }
}

function Tests_Task
{
    Set-BuildHeader "Tests"
    Install_Dependencies_Task tests
    Unit_Tests_Task
    Integration_Tests_Task
}

# ---------------------- ANALYSIS TASKS -----------------------------------

function Analyze_Code_Task
{
    Set-BuildLine 'Analyzing code'
    $AnalyzeSettings =  @{
        Path = "$($Settings.SourceFolder)"
        Severity = @('ParseError', 'Error', 'Warning', 'Information')
        Recurse = $True
        ExcludeRule = @('PSAvoidUsingWriteHost')
    }
    if ($ciMode) { $AnalyzeSettings.Severity = @('ParseError', 'Error') }
    Assert-BuildFolder
    Invoke-ScriptAnalyzer @AnalyzeSettings -Outvariable AnalyzeFindings | Out-Null
    $Script:AnalyzeFindings = $AnalyzeFindings
    if ( $AnalyzeFindings ) {
        $FindingsString = $AnalyzeFindings | Out-String
        Write-Warning $FindingsString
        $FailureMessage = 'PSScriptAnalyzer found {0} issues. Aborting build' -f $AnalyzeFindings.Count
        Assert-Build ( -not($AnalyzeFindings) ) $FailureMessage
    }
}

function Analyse_Task
{
    Set-BuildHeader "Analyse"
    Install_Dependencies_Task tests
    Analyze_Code_Task
}


# ---------------------- BUILD TASKS -----------------------------------

function Build_Concat_Task
{
    Set-BuildLine 'Concat: build onefile Powershell Script'
    Assert-BuildFolder

    # The path (relative or absolute) of the output file
    [string]$output = "$($Settings.ArchSourceFolder)/$($Settings.AppName).ps1"

    # Setup new file (even if already exist)
    New-Item -ItemType file $output -force | Out-Null

    # Add the content of each file to the output file
    foreach ($afile in $Settings.AppFilesOrderList) {
        if($afile) {
            $fileInfo = Get-Item -Path "$($Settings.SourceFolder)/$afile"
            Write-Host " + $afile"
            # Add a file path separator to the file
            Add-Content $output ("## $afile" )
            # Add the file content of the output file
            Add-Content $output (Get-Content $fileInfo.FullName | Where { $_ -notmatch "^using module" } | Where { $_ } )
            # Add a line break to the end
            Add-Content $output "`n"
        }
    }
}

function Build_CopyResources_Task
{
    Set-BuildLine 'Copy Resource & Cmd files'
    Assert-ArchSourceFolder
    # copy the resource folder'
	Copy-Item $Settings.ResourceFolder $Settings.ArchSourceFolder -Recurse -Force

    # copy the .cmd file
    Copy-Item "$($Settings.SourceFolder)/$($Settings.AppName).cmd"  $Settings.ArchSourceFolder -Force
}


function Build_Archive_Task
{
    Assert-ArchSourceFolder
    $Version = ((cmd /c powershell "$($Settings.SourceFolder)\$($Settings.AppName).ps1" --version) `
        -replace '\[[0-9;]*m' -replace '\s{2,}',' ' | 
        Select-String -Pattern $($Settings.AppName)).Line.Trim().Split(' ')[1]
    # check return version format:
    $versionPattern = '([0-9])+\.([0-9])+\.([0-9])+\-?(.*)?'
    $semVersion = $Version -match $versionPattern

    if (!$semVersion)
    {
        throw "Unvalid Semver version: $Version"
    }


    $ArchiveFile = "$($Settings.DistFolder)\$($Settings.AppName)-v$Version.zip"

    Write-Output "Compress Release $Version File $ArchiveFile"
    Get-ChildItem -Path $Settings.ArchSourceFolder -Exclude *.json |
        Compress-Archive -DestinationPath $ArchiveFile -Update

    $FailureMessage = 'Archive has compress issue(s). Aborting build'
    Assert-Build ( Test-Path $ArchiveFile ) $FailureMessage
}

function Build_Task
{
    Set-BuildHeader "build"
    Install_Dependencies_Task build
    Build_Concat_Task
    Build_CopyResources_Task
}

function Build_Release_Task
{
    Set-BuildHeader "build-release"
    Install_Dependencies_Task build
    Build_Concat_Task
    Build_CopyResources_Task
    Build_Archive_Task
}

# ---------------------- Functions/Main --------------------------------

function Assert-BuildFolder
{
    #New-Item -Path "$($Settings.DistFolder)" -ItemType Directory -ErrorAction Stop | Out-Null
    [System.IO.Directory]::CreateDirectory("$($Settings.DistFolder)") | Out-Null
}

function Assert-ArchSourceFolder
{
    #New-Item -Path "$($Settings.ArchSourceFolder)" -ItemType Directory -ErrorAction Stop | Out-Null
    [System.IO.Directory]::CreateDirectory("$($Settings.ArchSourceFolder)") | Out-Null
}

function Assert-Build ([Parameter()]$Condition, [string]$Message)
{
    if (!$Condition) {
        throw "Assertion failed.$(if ($Message) {" $Message"})" 
    }
}

function Set-BuildHeader ($taskName){
    Set-BuildLine "Task $taskName"
    "`n" + ('-' * 79) + "`n" + "`t`t`t $($taskName.ToUpper()) `n" + ('-' * 79) + "`n"
}

function Set-BuildLine ($text){
    [ConsoleColor]$Color=[ConsoleColor]::Cyan
    $i = $Host.UI.RawUI
    $_ = $i.ForegroundColor
    try { $i.ForegroundColor = $Color; "$text" }
    finally { $i.ForegroundColor = $_ }
}

[switch]$ciMode=$false

if (-not $cmd) { $cmd = "all" }
# Activate CI mode options
if ($cmd.EndsWith("-ci")){
    $ciMode = $true
    $cmd = "$($cmd -replace '.{3}$')"
}

switch ($cmd)
{
    "clean" {
        Clean_Task
    }
    "tests" {
        Tests_Task
    }
    "analyze" {
        Analyse_Task
    }
    "qa-tests" {
        Tests_Task
        Analyse_Task
    }
    "build" {
        Build_Task
    }
    "release" {
        Build_Release_Task
    }
    "all" {
        Clean_Task
        Install_Dependencies_Task all
        Tests_Task
        Analyse_Task
        Build_Release_Task
    }
    default { 'Unknown make command' }
}

