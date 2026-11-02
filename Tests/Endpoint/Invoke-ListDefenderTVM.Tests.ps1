# Pester tests for Invoke-ListDefenderTVM.
# The endpoint folds the streamed TVM export (Get-DefenderTvmRaw -Stream) into one row per CVE. Each
# row keeps the lowest non-null value per property (arrays flattened), counts every record and lists
# every device name as { deviceName } objects - the shape the grouped implementation returned.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Endpoint/MEM/Invoke-ListDefenderTVM.ps1')

    function Get-DefenderTvmRaw { param($TenantId, [switch]$Stream) }
    function Get-NormalizedError { param($Message) $Message }
    if (-not ('HttpResponseContext' -as [type])) {
        Add-Type -TypeDefinition 'public class HttpResponseContext { public object StatusCode; public object Body; public string ContentType; public object Headers; }'
    }
    if (-not ('HttpStatusCode' -as [type])) {
        [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
}

Describe 'Invoke-ListDefenderTVM' {
    BeforeEach {
        Mock Get-DefenderTvmRaw {
            [pscustomobject]@{ cveId = 'CVE-B'; deviceName = 'PC1'; cvssScore = 7.1; osPlatform = 'Windows11'; diskPaths = @('D:\b', 'C:\z') }
            [pscustomobject]@{ cveId = 'CVE-A'; deviceName = 'PC2'; cvssScore = 9.8; osPlatform = $null; diskPaths = $null }
            [pscustomobject]@{ cveId = 'CVE-A'; deviceName = 'PC1'; cvssScore = 9.1; osPlatform = 'Windows10'; diskPaths = @('E:\a') }
        }
        $script:Request = [pscustomobject]@{ Query = [pscustomobject]@{ tenantFilter = 'contoso.com' } }
    }

    It 'streams the TVM export and returns one row per CVE' {
        $Rows = @((Invoke-ListDefenderTVM -Request $script:Request).Body)
        Should -Invoke Get-DefenderTvmRaw -Times 1 -Exactly -ParameterFilter { $Stream.IsPresent }
        $Rows.cveId | Should -Be @('CVE-A', 'CVE-B')
    }

    It 'counts records, lists devices and keeps the lowest non-null value per property' {
        $A = @((Invoke-ListDefenderTVM -Request $script:Request).Body)[0]
        $A.customerId | Should -Be 'contoso.com'
        $A.affectedDevicesCount | Should -Be 2
        $A.affectedDevices.deviceName | Should -Be @('PC2', 'PC1')
        $A.cvssScore | Should -Be 9.1
        $A.osPlatform | Should -Be 'Windows10'
        $A.diskPaths | Should -Be 'E:\a'
    }

    It 'flattens array values before taking the lowest' {
        $B = @((Invoke-ListDefenderTVM -Request $script:Request).Body)[1]
        $B.diskPaths | Should -Be 'C:\z'
    }
}
