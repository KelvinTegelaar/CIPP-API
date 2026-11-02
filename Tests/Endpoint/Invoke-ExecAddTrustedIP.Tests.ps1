BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Get-Tenants { param($TenantFilter) [pscustomobject]@{ defaultDomainName = 'contoso.com' } }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = [string]$Exception.Exception.Message } }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/ConvertTo-CIPPIPRange.ps1')
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecAddTrustedIP.ps1' | Select-Object -First 1).FullName

    function New-Request {
        param($TenantFilter = 'contoso.com', $Body)
        [pscustomobject]@{
            Params  = [pscustomobject]@{ CIPPEndpoint = 'ExecAddTrustedIP' }
            Headers = $null
            Query   = [pscustomobject]@{ tenantfilter = $TenantFilter }
            Body    = [pscustomobject]$Body
        }
    }
}

Describe 'Invoke-ExecAddTrustedIP' {
    BeforeEach { Mock Add-CIPPAzDataTableEntity { } }

    It 'stores a blocked CIDR range under a key-safe RowKey with the range alongside' {
        $Response = Invoke-ExecAddTrustedIP -Request (New-Request -TenantFilter 'AllTenants' -Body @{ IP = '203.0.113.0/24'; State = 'Blocked'; Note = 'AiTM kit' }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter {
            $Entity.PartitionKey -eq 'AllTenants' -and $Entity.RowKey -eq '203.0.113.0_24' -and $Entity.Range -eq '203.0.113.0/24' -and $Entity.state -eq 'Blocked' -and $Entity.Note -eq 'AiTM kit'
        }
    }

    It 'accepts several addresses in one call, as an array or a separated string, and dedupes them' {
        $null = Invoke-ExecAddTrustedIP -Request (New-Request -Body @{ IP = @('198.51.100.7', '198.51.100.8, 198.51.100.7'); State = 'Trusted' }) -TriggerMetadata $null
        Should -Invoke Add-CIPPAzDataTableEntity -Times 2 -ParameterFilter { $Entity.PartitionKey -eq 'contoso.com' -and $Entity.state -eq 'Trusted' }
    }

    It 'rejects an invalid address or state without writing anything' {
        (Invoke-ExecAddTrustedIP -Request (New-Request -Body @{ IP = 'not-an-ip'; State = 'Trusted' }) -TriggerMetadata $null).StatusCode | Should -Be 400
        (Invoke-ExecAddTrustedIP -Request (New-Request -Body @{ IP = '198.51.100.7'; State = 'Maybe' }) -TriggerMetadata $null).StatusCode | Should -Be 400
        (Invoke-ExecAddTrustedIP -Request (New-Request -Body @{ IP = ''; State = 'Trusted' }) -TriggerMetadata $null).StatusCode | Should -Be 400
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }
}
