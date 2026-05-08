
using module "..\Application\ServiceLocator.psm1"
using module "..\Service\RegistryService.psm1"
using module "..\Service\WslService.psm1"
using module "..\Tools\FileUtils.psm1"
using module "..\Model\DockerFile.psm1"


Class BuilderService
{
    BuilderService()
    {

    }

    [void] build ([String]$dockerFile)
    {
        $this.build($dockerFile, $null, $false)
    }


    [void] build([String] $dockerFile, [String] $tag)
    {
        $this.build($dockerFile, $tag, $false)
    }


    [void] build([String] $dockerFile, [String] $tag, [Boolean] $dryRun)
    {
        if ((Get-Item $DockerFile) -is [System.IO.DirectoryInfo])
        {
            $DockerFile = [FileUtils]::joinPath($DockerFile, "Dockerfile")
        }

        if (-Not (Test-Path $DockerFile -PathType leaf))
        {
            throw "Dockerfile '$DockerFile' not found"
        }

        # Check input file is a DockerFile
        $fileName = [System.IO.Path]::GetFileName($DockerFile)
        $fileExtension = [System.IO.Path]::GetExtension($DockerFile)
        if (-not (("Dockerfile" -eq $fileName) -or (".dockerfile" -eq $fileExtension)) )
        {
            throw "'$DockerFile' is not a dockerfile"
        }

        if (-not $tag)
        {
            # if file is Dockerfile => parent directory name
            if ("Dockerfile" -eq $fileName) { $tag = (Get-Item $DockerFile).Directory.Name }
            # if file format <tag>.dockerfile => extract tag
            else { $tag = [System.IO.Path]::GetFileNameWithoutExtension($DockerFile) }
        }

        $wslService = [WslService]([ServiceLocator]::getInstance().get('wsl-wrapper'))
        $registryService = [RegistryService]([ServiceLocator]::getInstance().get('registry'))

        # Parse Dockerfile/Wslfile and Generate bash commands
        Write-Host "Parsing file ..."
        $File = [DockerFile]::new($dockerFile)
        $bashCmds = $File.toBash()

        if ($dryRun)
        {
            Write-Host "From  : $($File.from)"
            Write-Host "Tag   : $tag"
            Write-Host ""
            Write-Host "--------------Generated Script File --------------------"
            $bashCmds | ForEach-Object { Write-Host $_ }
            Write-Host "--------------------------------------------------------"
            return
        }


        # create the target distribution
        $distroName = $($File.from) -replace ":", "-"
        $wslName = $tag -replace ":", "-"
        $wslVersion = $wslService.getDefaultVersion()

        Write-Host "Check import requirements ..."
        $wslService.checkBeforeImport($wslName)

        Write-Host "Download distribution '$distroName' ..."
        $archive = $registryService.pull($distroName)

        Write-Host "Create wsl instance '$wslName' (wsl-version: $wslVersion)..."
        $wslService.import(
            $wslName,
            $File.from,
            $archive,
            $wslVersion,
            $false
        )
        Write-Host "* $wslName created"

        # Generate bash temp file
        $tempFile = Get-ChildItem ([IO.Path]::GetTempFileName()) | `
            Rename-Item -NewName { [IO.Path]::ChangeExtension($_, ".sh") } -PassThru

        # Write Unix UTF8 files (no BOM)
        $Utf8WithoutBom = New-Object System.Text.UTF8Encoding $false
        $w = New-Object System.IO.StreamWriter @($tempFile, $false, $Utf8WithoutBom)
        foreach ($line in $bashCmds) {
            # normalize line breaks
            $line = $line.Replace("`r`n", "`n").Replace("`r", "`n")
            $w.Write($line)
            $w.Write("`n")
        }
        $w.Close()

        # Call exec
        $wslService.invoke(@{
            distribution = $wslName
            script = $tempFile
            output = $true
        })

        # remove temp file
        Remove-Item $tempFile
    }

}
