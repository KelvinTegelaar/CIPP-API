# Mailbox-store writes (e.g. Set-Mailbox -DefaultAuditSet) fail with CmdletProxyNotAvailableException
# unless the POST is routed to the mailbox's own server, and a $batch routes as a whole.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/New-ExoBulkRequest.ps1')

    function Get-AuthorisedRequest { param($TenantID) $true }
    function Get-GraphToken { param($Tenantid, $scope, $AsApp) @{ Authorization = 'Bearer x' } }
    function Get-Tenants { param([switch]$IncludeErrors, $TenantFilter) [PSCustomObject]@{ customerId = 'cid'; initialDomainName = 'contoso.onmicrosoft.com' } }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text) $Text }
    function Invoke-CIPPRestMethod { param($Uri, $Method, $Body, $Headers, $ContentType, $TimeoutSec, $ResponseHeadersVariable) }

    $script:Cmdlets = foreach ($Upn in 'a@contoso.com', 'b@contoso.com') {
        @{ CmdletInput = @{ CmdletName = 'Set-Mailbox'; Parameters = @{ Identity = $Upn } }; OperationGuid = $Upn }
    }
    $script:Respond = { param($Body, $Status) @{ responses = @(($Body | ConvertFrom-Json).requests | ForEach-Object { [PSCustomObject]@{ id = $_.id; status = $Status; body = [PSCustomObject]@{} } }) } }
}

Describe 'New-ExoBulkRequest -AnchorPerMailbox' {
    BeforeEach {
        $script:Posts = [System.Collections.Generic.List[object]]::new()
        $script:Throttle = $false
        Mock Start-Sleep {}
        Mock Invoke-CIPPRestMethod {
            $script:Posts.Add(@{ Anchor = $Headers['X-AnchorMailbox']; Size = @(($Body | ConvertFrom-Json).requests).Count })
            $Status = if ($script:Throttle -and $script:Posts.Count -eq 1) { 429 } else { 200 }
            & $script:Respond $Body $Status
        }
    }

    It 'sends one POST per cmdlet, each routed to its own mailbox' {
        $null = New-ExoBulkRequest -tenantid 'contoso.onmicrosoft.com' -cmdletArray @($script:Cmdlets) -AnchorPerMailbox
        $script:Posts.Anchor | Should -Be @('UPN:a@contoso.com', 'UPN:b@contoso.com')
        $script:Posts.Size | Should -Be @(1, 1)
    }

    It 'retries a throttled cmdlet routed to the same mailbox' {
        $script:Throttle = $true
        $null = New-ExoBulkRequest -tenantid 'contoso.onmicrosoft.com' -cmdletArray @($script:Cmdlets) -AnchorPerMailbox
        $script:Posts.Anchor | Should -Be @('UPN:a@contoso.com', 'UPN:b@contoso.com', 'UPN:a@contoso.com')
    }

    It 'keeps the default: one system-mailbox-routed batch' {
        $null = New-ExoBulkRequest -tenantid 'contoso.onmicrosoft.com' -cmdletArray @($script:Cmdlets)
        $script:Posts.Size | Should -Be @(2)
        $script:Posts[0].Anchor | Should -BeLike 'APP:SystemMailbox*'
    }
}
