BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    function Get-PrivateStatic([type]$Type, [string]$Name) {
        $Type.GetField($Name, [System.Reflection.BindingFlags]'NonPublic,Static').GetValue($null)
    }
}

Describe 'CIPPSharp static holders' {
    It 'does not remember report image names that do not ship' {
        foreach ($i in 1..1000) {
            [CIPP.Reporting.ReportComponents]::DecodeImage("/reportImages/missing$i.png", $true) | Should -BeNullOrEmpty
        }
        (Get-PrivateStatic ([CIPP.Reporting.ReportComponents]) 'ReportImageCache').Count | Should -BeLessOrEqual 20
    }

    It 'caps the per-host request counts' {
        [CIPP.CIPPRestClient]::ResetDiagnostics()
        $Track = [CIPP.CIPPRestClient].GetMethod('TrackPoolSelection', [System.Reflection.BindingFlags]'NonPublic,Static')
        foreach ($i in 1..5) { $null = $Track.Invoke($null, @('graph', 'graph.microsoft.com')) }
        foreach ($i in 1..3000) { $null = $Track.Invoke($null, @('spo', "tenant$i.sharepoint.com")) }
        foreach ($i in 1..5) { $null = $Track.Invoke($null, @('graph', 'graph.microsoft.com')) }
        (Get-PrivateStatic ([CIPP.CIPPRestClient]) '_hostSelections').Count | Should -BeLessOrEqual 501
        $Top = ([CIPP.CIPPRestClient]::GetDiagnostics() | ConvertFrom-Json).PoolUsage.TopHosts
        $Top.Where({ $_.Host -eq 'graph.microsoft.com' }).Requests | Should -Be 10
        [CIPP.CIPPRestClient]::ResetDiagnostics()
        $null = $Track.Invoke($null, @('spo', 'tenant1.sharepoint.com'))
        (Get-PrivateStatic ([CIPP.CIPPRestClient]) '_hostSelections').Count | Should -Be 1
    }
}
