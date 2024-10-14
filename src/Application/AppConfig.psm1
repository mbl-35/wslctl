using module "..\Model\JsonHashtableFile.psm1"
using module "..\Tools\FileUtils.psm1"


Class AppConfig : JsonHashtableFile
{

    AppConfig([String] $version) : base(
        [System.IO.Path]::ChangeExtension((Get-PSCallStack | Select-Object -Skip 1 -First 1 -ExpandProperty 'ScriptName'), "json"),
        @{})
    {
        $this.Add("version", $version)

        if (-Not $this.ContainsKey("appData"))
        {
            if (($null -ne $env:WSLCTL) -And (Test-Path -Path $env:WSLCTL)) { $this.Add("appData", $env:WSLCTL); }
            else  {
                $this.Add("appData", [FileUtils]::joinPath($env:LOCALAPPDATA, "Wslctl") )
            }
        }
     }

     [System.Collections.IDictionaryEnumerator] GetEnumerator()
     {
         $data = $this.Clone()
         $data.Remove('version')
         $data.Remove('File')
         return $data.GetEnumerator()
     }
}
