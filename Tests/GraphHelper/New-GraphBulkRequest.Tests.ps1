BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    function Get-AuthorisedRequest { param($Uri, $TenantID) $true }
    function Get-GraphToken { param($tenantid, $scope, $AsApp) @{ Authorization = 'Bearer x' } }
    function Get-CippTable { param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) [pscustomobject]@{ RowKey = 't'; LastGraphError = '' } }
    function Update-AzDataTableEntity { param([switch]$Force, $Entity) }
    function Invoke-CIPPRestMethod { param($Uri, $Method, $Headers, $ContentType, $Body) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/New-GraphBulkRequest.ps1')
    function New-Ok { param($Requests) [pscustomobject]@{ responses = @($Requests | ForEach-Object { [pscustomobject]@{ id = $_.id; status = 200; body = [pscustomobject]@{ value = @() } } }) } }
}

Describe 'New-GraphBulkRequest' {
    BeforeEach {
        $script:Sent = [System.Collections.Generic.List[object]]::new()
        Mock Invoke-CIPPRestMethod { $Requests = @(($Body | ConvertFrom-Json).requests); $script:Sent.Add(@($Requests.id)); New-Ok $Requests }
    }

    It 'keeps the identity reports to their burst of 10 a batch and fills the rest up to 20' {
        $Requests = @(1..12 | ForEach-Object { @{ id = "s$_"; method = 'GET'; url = "auditLogs/signIns?`$filter=userId eq 'u$_'" } }) +
        @(1..3 | ForEach-Object { @{ id = "u$_"; method = 'GET'; url = "users/u$_" } })
        @(New-GraphBulkRequest -tenantid 'contoso.com' -asapp $true -Requests $Requests).Count | Should -Be 15
        @($script:Sent | ForEach-Object { $_ -join ',' }) | Should -Be @('s1,s2,s3,s4,s5,s6,s7,s8,s9,s10', 's11,s12,u1,u2,u3')
    }

    It 'still sends 20 a batch when no request has a measured budget' {
        $null = New-GraphBulkRequest -tenantid 'contoso.com' -asapp $true -Requests @(1..25 | ForEach-Object { @{ id = "u$_"; method = 'GET'; url = "users/u$_" } })
        @($script:Sent | ForEach-Object { $_.Count }) | Should -Be @(20, 5)
    }

    It 'keeps Conditional Access to its burst of 10 a batch' {
        $null = New-GraphBulkRequest -tenantid 'contoso.com' -asapp $true -Version 'v1.0' -Requests @(1..26 | ForEach-Object { @{ id = "e$_"; method = 'POST'; url = 'identity/conditionalAccess/evaluate'; body = @{}; headers = @{ 'Content-Type' = 'application/json' } } })
        @($script:Sent | ForEach-Object { $_.Count }) | Should -Be @(10, 10, 6)
    }

    It 'leaves a batch with dependsOn and no measured budget whole' {
        $Requests = @(
            @{ id = '1'; method = 'POST'; url = 'applications'; body = @{}; headers = @{ 'Content-Type' = 'application/json' } }
            @{ id = '2'; method = 'POST'; url = 'servicePrincipals'; dependsOn = @('1'); body = @{}; headers = @{ 'Content-Type' = 'application/json' } }
        )
        $null = New-GraphBulkRequest -tenantid 'contoso.com' -asapp $true -Requests $Requests
        @($script:Sent | ForEach-Object { $_ -join ',' }) | Should -Be @('1,2')
    }

    It 'retries throttled sub-requests in batches within the burst too' {
        $script:Call = 0
        Mock Invoke-CIPPRestMethod {
            $Requests = @(($Body | ConvertFrom-Json).requests); $script:Sent.Add(@($Requests.id)); $script:Call++
            if ($script:Call -le 2) { [pscustomobject]@{ responses = @($Requests | ForEach-Object { [pscustomobject]@{ id = $_.id; status = 429; headers = [pscustomobject]@{ 'Retry-After' = '0' }; body = [pscustomobject]@{} } }) } }
            else { New-Ok $Requests }
        }
        Mock Start-Sleep { }
        $Responses = @(New-GraphBulkRequest -tenantid 'contoso.com' -asapp $true -Requests @(1..12 | ForEach-Object { @{ id = "s$_"; method = 'GET'; url = 'auditLogs/signIns' } }))
        @($Responses | Where-Object { $_.status -eq 200 }).Count | Should -Be 12
        @($script:Sent | ForEach-Object { $_.Count }) | Should -Be @(10, 2, 10, 2)
    }
}