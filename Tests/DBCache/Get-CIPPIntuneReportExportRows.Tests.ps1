# Pester tests for Get-CIPPIntuneReportExportRows.
# The helper streams an Intune report export straight off its download URL: zip -> JSON entry ->
# one row of the "values" array at a time. A local HttpListener serves real export-shaped zips so
# the download, unzip and parse path all run.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneReportExportRows.ps1')
    Add-Type -AssemblyName System.IO.Compression

    function New-ExportZip ([string]$EntryName, [string]$Content) {
        $Buffer = [System.IO.MemoryStream]::new()
        $Zip = [System.IO.Compression.ZipArchive]::new($Buffer, [System.IO.Compression.ZipArchiveMode]::Create, $true)
        $Writer = [System.IO.StreamWriter]::new($Zip.CreateEntry($EntryName).Open(), [System.Text.UTF8Encoding]::new($true))
        $Writer.Write($Content)
        $Writer.Dispose(); $Zip.Dispose()
        , $Buffer.ToArray()
    }

    # Serves each registered path's bytes; runs on its own runspace so the helper can call it.
    $script:Port = Get-Random -Minimum 20000 -Maximum 40000
    $script:Files = [hashtable]::Synchronized(@{})
    $script:Listener = [System.Net.HttpListener]::new()
    $script:Listener.Prefixes.Add("http://localhost:$script:Port/")
    $script:Listener.Start()
    $script:Server = [powershell]::Create().AddScript({
            param($Listener, $Files)
            while ($Listener.IsListening) {
                try { $Context = $Listener.GetContext() } catch { break }
                $Bytes = $Files[$Context.Request.Url.AbsolutePath]
                if ($Bytes) { $Context.Response.OutputStream.Write($Bytes, 0, $Bytes.Length) } else { $Context.Response.StatusCode = 404 }
                $Context.Response.Close()
            }
        }).AddArgument($script:Listener).AddArgument($script:Files)
    $null = $script:Server.BeginInvoke()

    # Intune's own layout: one row per line inside "values", with a BOM.
    $script:Files['/export.zip'] = New-ExportZip 'AppInvRawData_1.json' (@(
            '{'
            '"columns": ["ApplicationKey","ApplicationName","InstalledDeviceCount"],'
            '"values": ['
            '{"ApplicationKey":"k1","ApplicationName":"App \"One\"","InstalledDeviceCount":3},'
            '{"ApplicationKey":"k2","ApplicationName":"App Two","InstalledDeviceCount":0}'
            ']'
            '}'
        ) -join "`r`n")
    $script:Files['/empty.zip'] = New-ExportZip 'AppInvRawData_2.json' "{`"columns`": [`"A`"],`r`n`"values`": [`r`n]`r`n}"
    $script:Files['/nojson.zip'] = New-ExportZip 'AppInvRawData_3.csv' '"A"'
}

AfterAll {
    $script:Listener.Stop()
    $script:Server.Dispose()
}

Describe 'Get-CIPPIntuneReportExportRows' {
    It 'emits each row of the values array in order, typed as JSON types' {
        $Rows = @(Get-CIPPIntuneReportExportRows -Url "http://localhost:$script:Port/export.zip")
        $Rows.Count | Should -Be 2
        $Rows[0].ApplicationKey | Should -Be 'k1'
        $Rows[0].ApplicationName | Should -Be 'App "One"'
        $Rows[0].InstalledDeviceCount | Should -Be 3
        $Rows[0].InstalledDeviceCount | Should -BeOfType [long]
        $Rows[1].ApplicationKey | Should -Be 'k2'
    }

    It 'emits nothing for an export with no rows' {
        @(Get-CIPPIntuneReportExportRows -Url "http://localhost:$script:Port/empty.zip").Count | Should -Be 0
    }

    It 'throws when the archive has no JSON entry' {
        { Get-CIPPIntuneReportExportRows -Url "http://localhost:$script:Port/nojson.zip" } | Should -Throw '*No JSON entry*'
    }

    It 'throws when the download fails' {
        { Get-CIPPIntuneReportExportRows -Url "http://localhost:$script:Port/missing.zip" } | Should -Throw
    }
}
