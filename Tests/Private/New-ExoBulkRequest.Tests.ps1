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

Describe 'New-ExoBulkRequest transient sub-request errors' {
    BeforeEach {
        $script:Posts = [System.Collections.Generic.List[object]]::new()
        Mock Start-Sleep {}
        Mock Invoke-CIPPRestMethod {
            $Requests = @(($Body | ConvertFrom-Json).requests)
            $script:Posts.Add($Requests.Count)
            @{ responses = @($Requests | ForEach-Object {
                        if ($script:Posts.Count -eq 1 -and $_.body.CmdletInput.Parameters.Identity -eq 'a@contoso.com') {
                            [PSCustomObject]@{ id = $_.id; status = 500; body = [PSCustomObject]@{ error = [PSCustomObject]@{ message = $script:FirstError } } }
                        } else {
                            [PSCustomObject]@{ id = $_.id; status = 200; body = [PSCustomObject]@{ value = @([PSCustomObject]@{ Identity = $_.body.CmdletInput.Parameters.Identity }) } }
                        }
                    }) }
        }
    }

    It 'retries a mailbox that was mid-failover (<Message>)' -ForEach @(
        @{ Message = '|Microsoft.Exchange.Data.Storage.MailboxCrossSiteFailoverException|Cannot open mailbox.' }
        @{ Message = '|Microsoft.Exchange.Data.Storage.MailboxInfoStaleException|Can''t connect to the mailbox of user' }
        @{ Message = '|Microsoft.Exchange.Data.Storage.StorageTransientException|Try again later.' }
        @{ Message = '|Microsoft.Exchange.Data.Storage.MailboxOfflineException|Cannot open mailbox.' }
    ) {
        $script:FirstError = $Message
        $Result = @(New-ExoBulkRequest -tenantid 'contoso.onmicrosoft.com' -cmdletArray @($script:Cmdlets))
        $script:Posts | Should -Be @(2, 1)
        @($Result.Where({ $_.error })).Count | Should -Be 0
        @($Result.Identity) | Should -Contain 'a@contoso.com'
    }

    It 'does not retry a permanent error' {
        $script:FirstError = '|Microsoft.Exchange.Configuration.Tasks.ManagementObjectNotFoundException|The operation couldn''t be performed because object couldn''t be found.'
        $Result = @(New-ExoBulkRequest -tenantid 'contoso.onmicrosoft.com' -cmdletArray @($script:Cmdlets))
        $script:Posts | Should -Be @(2)
        @($Result.Where({ $_.error })).Count | Should -Be 1
    }
}

Describe 'New-ExoBulkRequest @adminapi.warnings' {
    BeforeEach {
        Mock Start-Sleep {}
        Mock Write-Warning {}
        Mock Invoke-CIPPRestMethod {
            @{ responses = @(($Body | ConvertFrom-Json).requests | ForEach-Object {
                        [PSCustomObject]@{ id = $_.id; status = 200; body = [PSCustomObject]@{ value = @(); '@adminapi.warnings' = $script:Warnings } }
                    }) }
        }
    }

    It 'drops the per-mailbox "has not logged on" notice but keeps other warnings (<Mode>)' -ForEach @(
        @{ Mode = 'default'; Splat = @{} }
        @{ Mode = 'ReturnWithCommand'; Splat = @{ ReturnWithCommand = $true } }
    ) {
        $script:Warnings = @("The user hasn't logged on to mailbox 'a@contoso.com' ('guid'), so there is no data to return. After the user logs on, this warning will no longer appear.")
        $null = New-ExoBulkRequest -tenantid 'contoso.onmicrosoft.com' -cmdletArray @($script:Cmdlets) @Splat
        Should -Invoke Write-Warning -Times 0 -Exactly

        $script:Warnings = @("The user hasn't logged on to mailbox 'a@contoso.com' ('guid'), so there is no data to return.", 'The command completed successfully but no settings have been modified.')
        $null = New-ExoBulkRequest -tenantid 'contoso.onmicrosoft.com' -cmdletArray @($script:Cmdlets) @Splat
        Should -Invoke Write-Warning -Times 2 -Exactly -ParameterFilter { $Message -like '*no settings have been modified*' -and $Message -notlike "*hasn't logged on*" }
    }
}
