BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPUserLicense.ps1')

    function Get-CippTable { param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $Sev) }
    function New-GraphBulkRequest { param($tenantid, $Requests) }

    function New-LicenseRequest([string]$UserId) {
        [PSCustomObject]@{ UserId = $UserId; UserPrincipalName = "$UserId@contoso.com"; AddLicenses = @('sku-1'); RemoveLicenses = @(); IsReplace = $false }
    }
}

Describe 'Set-CIPPUserLicense' {
    BeforeEach {
        Mock New-GraphBulkRequest {
            foreach ($Request in $Requests) {
                if ($Request.id -eq 'bad') { [pscustomobject]@{ id = 'bad'; status = 400; body = @{ error = @{ message = 'License unavailable' } } } }
                else { [pscustomobject]@{ id = $Request.id; status = 200; body = @{} } }
            }
        }
    }

    It 'returns a countable result per user in bulk mode' {
        $Requests = [System.Collections.Generic.List[object]]::new()
        $Requests.Add((New-LicenseRequest 'good'))
        $Requests.Add((New-LicenseRequest 'bad'))
        $Results = @(Set-CIPPUserLicense -LicenseRequests $Requests -TenantFilter 'contoso.com')

        $Results.Count | Should -Be 2
        ($Results | Where-Object UserId -EQ 'good').state | Should -Be 'success'
        $Failed = $Results | Where-Object UserId -EQ 'bad'
        $Failed.state | Should -Be 'error'
        $Failed.resultText | Should -Be 'Failed to assign licenses for user bad@contoso.com: License unavailable'
    }

    It 'still returns a plain string for a single user' {
        $Result = Set-CIPPUserLicense -UserId 'bad' -UserPrincipalName 'bad@contoso.com' -AddLicenses @('sku-1') -TenantFilter 'contoso.com'
        $Result | Should -BeOfType [string]
        $Result | Should -Be 'Failed to assign licenses for user bad@contoso.com: License unavailable'
    }
}
