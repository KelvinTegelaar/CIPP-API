# Pester tests for Invoke-ExecOneDriveCopyToUser and Invoke-ListOneDriveCopyToUser

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    $UsersDir = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Users'
    $script:ExecPath = Join-Path $UsersDir 'Invoke-ExecOneDriveCopyToUser.ps1'
    $script:ListPath = Join-Path $UsersDir 'Invoke-ListOneDriveCopyToUser.ps1'
    if (-not (Test-Path $script:ExecPath)) { throw "Could not locate $script:ExecPath" }
    if (-not (Test-Path $script:ListPath)) { throw "Could not locate $script:ListPath" }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Start-CIPPOneDriveCopyToUser { param($TenantFilter, $Leaver, $Recipients, $Library, $IncludeVersionHistory, $StartedBy, $OperationId, $Headers, $APIName, [switch]$WaitForSignInBlock) }
    function Update-CIPPOneDriveCopyToUserStatus { param($TenantFilter, $OperationId) }
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($Filter, $TableName) }
    function Get-CIPPOneDriveCopyTenantKey { param($TenantFilter) 'c0ffee00-1111-2222-3333-444444444444' }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [PSCustomObject]@{ NormalizedError = $Exception.Exception.Message ?? $Exception.Message } }

    . $script:ExecPath
    . $script:ListPath
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')

    function New-ExecRequest($Body, $Headers = @{}) {
        [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecOneDriveCopyToUser' }; Headers = $Headers; Body = [pscustomobject]$Body }
    }
}

Describe 'Endpoint roles' {
    It '<Name> declares <Role>' -ForEach @(
        @{ Name = 'ExecOneDriveCopyToUser'; Role = 'Identity.OneDrive.ReadWrite' }
        @{ Name = 'ListOneDriveCopyToUser'; Role = 'Identity.OneDrive.Read' }
    ) {
        $Path = if ($Name -like 'Exec*') { $script:ExecPath } else { $script:ListPath }
        (Get-Content $Path -Raw) -match '\.ROLE\s*\r?\n\s*([A-Za-z0-9.]+)' | Should -BeTrue
        $Matches[1] | Should -Be $Role
    }

    # Test-CIPPAccess grants an endpoint when any permission of the caller's custom role matches the
    # endpoint's .ROLE as a regex ($Permission -match $APIRole). Check that rule against every entrypoint.
    It 'a custom role holding only <Permission> reaches exactly <Expected>' -ForEach @(
        @{ Permission = 'Identity.OneDrive.ReadWrite'; Expected = @('Invoke-ExecOneDriveCopyToUser', 'Invoke-ListOneDriveCopyToUser') }
        @{ Permission = 'Identity.OneDrive.Read'; Expected = @('Invoke-ListOneDriveCopyToUser') }
    ) {
        $EntrypointRoot = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints'
        $Granted = @(Get-ChildItem -Path $EntrypointRoot -Recurse -Filter 'Invoke-*.ps1' | ForEach-Object {
                if ((Get-Content $_.FullName -Raw) -match '\.ROLE\s*\r?\n\s*([A-Za-z0-9.*]+)') {
                    $Role = $Matches[1]
                    if ($Permission -match $Role) { $_.BaseName }
                }
            } | Sort-Object)
        $Granted | Should -Be $Expected
    }

    It 'no existing endpoint role is satisfied by the new permissions other than the two new endpoints' {
        $EntrypointRoot = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints'
        $Others = @(Get-ChildItem -Path $EntrypointRoot -Recurse -Filter 'Invoke-*.ps1' |
                Where-Object { $_.BaseName -notin @('Invoke-ExecOneDriveCopyToUser', 'Invoke-ListOneDriveCopyToUser') } |
                ForEach-Object { if ((Get-Content $_.FullName -Raw) -match '\.ROLE\s*\r?\n\s*([A-Za-z0-9.*]+)') { $Matches[1] } })
        $Others.Count | Should -BeGreaterThan 100
        @($Others | Where-Object { 'Identity.OneDrive.ReadWrite' -match $_ }) | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-ExecOneDriveCopyToUser' {
    BeforeEach {
        Mock Start-CIPPOneDriveCopyToUser { [pscustomobject]@{ OperationId = '11111111-2222-3333-4444-555555555555'; Recipients = @() } }
        Mock Write-LogMessage {}
    }

    It 'starts the copy with plain and {label,value} inputs and passes the caller headers on' {
        $Principal = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((@{ userDetails = 'tech@partner.com' } | ConvertTo-Json)))
        $Response = Invoke-ExecOneDriveCopyToUser -Request (New-ExecRequest @{
                tenantFilter          = 'contoso.com'
                leaver                = [pscustomobject]@{ label = 'Jane'; value = 'jane@contoso.com' }
                recipients            = @('bob@contoso.com', [pscustomobject]@{ label = 'Carol'; value = 'carol@contoso.com' })
                includeVersionHistory = $true
            } @{ 'x-ms-client-principal' = $Principal })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::Accepted)
        $Response.Body.Results.OperationId | Should -Be '11111111-2222-3333-4444-555555555555'
        Should -Invoke Start-CIPPOneDriveCopyToUser -Times 1 -Exactly -ParameterFilter {
            $TenantFilter -eq 'contoso.com' -and $Leaver -eq 'jane@contoso.com' -and
            (@($Recipients) -join ';') -eq 'bob@contoso.com;carol@contoso.com' -and
            $IncludeVersionHistory -eq $true -and $Headers.'x-ms-client-principal' -eq $Principal
        }
    }

    It 'gives the UI one result line, as a warning when a recipient did not start' {
        Mock Start-CIPPOneDriveCopyToUser {
            [pscustomobject]@{ OperationId = 'op-1'; Message = 'Started copying.'; Warnings = @(); Recipients = @(
                    [pscustomobject]@{ UserPrincipalName = 'bob@contoso.com'; State = 'Queued' }
                    [pscustomobject]@{ UserPrincipalName = 'carol@contoso.com'; State = 'Failed'; Message = 'Copy failed to start: denied' }
                ) }
        }
        $Results = (Invoke-ExecOneDriveCopyToUser -Request (New-ExecRequest @{ tenantFilter = 'contoso.com'; leaver = 'jane@contoso.com'; recipients = @('bob@contoso.com', 'carol@contoso.com') })).Body.Results
        $Results.resultText | Should -Be 'Started copying. carol@contoso.com: Copy failed to start: denied'
        $Results.state | Should -Be 'warning'
        $Results.OperationId | Should -Be 'op-1'
    }

    It 'reports a clean start as success' {
        Mock Start-CIPPOneDriveCopyToUser { [pscustomobject]@{ OperationId = 'op-1'; Message = 'Started copying.'; Recipients = @([pscustomobject]@{ UserPrincipalName = 'bob@contoso.com'; State = 'Queued' }) } }
        (Invoke-ExecOneDriveCopyToUser -Request (New-ExecRequest @{ tenantFilter = 'contoso.com'; leaver = 'jane@contoso.com'; recipients = @('bob@contoso.com') })).Body.Results.state | Should -Be 'success'
    }

    It 'accepts a document library instead of recipients' {
        $Response = Invoke-ExecOneDriveCopyToUser -Request (New-ExecRequest @{
                tenantFilter = 'contoso.com'; leaver = 'jane@contoso.com'
                library      = [pscustomobject]@{ site = [pscustomobject]@{ value = 'https://contoso.sharepoint.com/sites/HR' }; library = [pscustomobject]@{ label = 'Leavers'; value = 'list-1' }; folder = 'Leavers' }
            })
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::Accepted)
        Should -Invoke Start-CIPPOneDriveCopyToUser -Times 1 -Exactly -ParameterFilter {
            @($Recipients).Count -eq 0 -and $Library.site -eq 'https://contoso.sharepoint.com/sites/HR' -and $Library.library -eq 'list-1' -and $Library.folder -eq 'Leavers'
        }
    }

    It 'never lets the caller choose the operation id (it could reuse an id the offboarding licence step waits for)' {
        Invoke-ExecOneDriveCopyToUser -Request (New-ExecRequest @{ tenantFilter = 'contoso.com'; leaver = 'jane@contoso.com'; recipients = 'bob@contoso.com'; OperationId = '11111111-2222-3333-4444-555555555555' }) | Out-Null
        Should -Invoke Start-CIPPOneDriveCopyToUser -Times 1 -Exactly -ParameterFilter { [string]::IsNullOrEmpty($OperationId) }
    }

    It 'refuses a leaver who can still sign in at once (no waiting for the block, unlike offboarding)' {
        Invoke-ExecOneDriveCopyToUser -Request (New-ExecRequest @{ tenantFilter = 'contoso.com'; leaver = 'jane@contoso.com'; recipients = 'bob@contoso.com'; WaitForSignInBlock = $true }) | Out-Null
        Should -Invoke Start-CIPPOneDriveCopyToUser -Times 1 -Exactly -ParameterFilter { -not $WaitForSignInBlock }
    }

    It 'leaves version history off when includeVersionHistory is not sent' {
        Invoke-ExecOneDriveCopyToUser -Request (New-ExecRequest @{ tenantFilter = 'contoso.com'; leaver = 'jane@contoso.com'; recipients = 'bob@contoso.com' }) | Out-Null
        Should -Invoke Start-CIPPOneDriveCopyToUser -ParameterFilter { $IncludeVersionHistory -eq $false }
    }

    It 'returns BadRequest without calling the helper when <Case>' -ForEach @(
        @{ Case = 'tenantFilter is missing'; Body = @{ leaver = 'jane@contoso.com'; recipients = @('bob@contoso.com') } }
        @{ Case = 'tenantFilter is AllTenants'; Body = @{ tenantFilter = 'AllTenants'; leaver = 'jane@contoso.com'; recipients = @('bob@contoso.com') } }
        @{ Case = 'leaver is missing'; Body = @{ tenantFilter = 'contoso.com'; recipients = @('bob@contoso.com') } }
        @{ Case = 'recipients is missing'; Body = @{ tenantFilter = 'contoso.com'; leaver = 'jane@contoso.com' } }
        @{ Case = 'recipients is not a list of ids'; Body = @{ tenantFilter = 'contoso.com'; leaver = 'jane@contoso.com'; recipients = @(@{ id = 5 }) } }
    ) {
        $Response = Invoke-ExecOneDriveCopyToUser -Request (New-ExecRequest $Body)
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke Start-CIPPOneDriveCopyToUser -Times 0 -Exactly
    }

    It 'returns <Expected> when the helper throws <Kind>' -ForEach @(
        @{ Kind = 'a refusal'; Exception = [System.ArgumentException]::new('Recipient bob@contoso.com does not have enough space.'); Expected = [System.Net.HttpStatusCode]::BadRequest }
        @{ Kind = 'an upstream failure'; Exception = [System.Exception]::new('Graph 503'); Expected = [System.Net.HttpStatusCode]::InternalServerError }
    ) {
        $Thrown = $Exception
        Mock Start-CIPPOneDriveCopyToUser { throw $Thrown }
        $Response = Invoke-ExecOneDriveCopyToUser -Request (New-ExecRequest @{ tenantFilter = 'contoso.com'; leaver = 'jane@contoso.com'; recipients = @('bob@contoso.com') })
        $Response.StatusCode | Should -Be $Expected
        $Response.Body.Results | Should -BeLike "Failed to start the OneDrive copy. Error: *$($Exception.Message)*"
    }
}

Describe 'Invoke-ListOneDriveCopyToUser' {
    BeforeAll {
        function New-ListRequest($Query) { [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ListOneDriveCopyToUser' }; Headers = @{}; Query = $Query } }
    }
    BeforeEach {
        Mock Update-CIPPOneDriveCopyToUserStatus { [pscustomobject]@{ OperationId = $OperationId; State = 'InProgress'; Recipients = @() } }
        Mock Get-CIPPAzDataTableEntity {}
        Mock Write-LogMessage {}
    }

    It 'returns the status of one copy as a one-row list' {
        $Response = Invoke-ListOneDriveCopyToUser -Request (New-ListRequest @{ tenantFilter = 'contoso.com'; OperationId = 'op-1' })
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        @($Response.Body).Count | Should -Be 1
        $Response.Body[0].State | Should -Be 'InProgress'
        Should -Invoke Update-CIPPOneDriveCopyToUserStatus -ParameterFilter { $TenantFilter -eq 'contoso.com' -and $OperationId -eq 'op-1' }
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'lists every copy in the tenant from stored state, without polling SharePoint' {
        Mock Get-CIPPAzDataTableEntity {
            [pscustomobject]@{
                RowKey = 'op-1'; Kind = 'Operation'; LeaverUPN = 'jane@contoso.com'; State = 'Completed'; StartedBy = 'tech@partner.com'
                StartedUtc = '2026-11-17T00:00:00Z'; LastCheckedUnix = 1763337600; SourceFileCount = 6; SourceBytes = 60
                RecipientSummary = '[{"UserPrincipalName":"bob@contoso.com","State":"Completed","ItemsCopied":6},{"UserPrincipalName":"carol@contoso.com","State":"Completed","ItemsCopied":6}]'
            }
            [pscustomobject]@{ RowKey = 'op-2'; Kind = 'Operation'; LeaverUPN = 'pat@contoso.com' }
        }
        $Response = Invoke-ListOneDriveCopyToUser -Request (New-ListRequest @{ tenantFilter = 'contoso.com' })
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Rows = @($Response.Body)
        $Rows.Count | Should -Be 2
        $Rows[0].OperationId | Should -Be 'op-1'
        $Rows[0].Destinations | Should -Be 'bob@contoso.com, carol@contoso.com'
        $Rows[0].Recipients[1].ItemsCopied | Should -Be 6
        $Rows[0].LastCheckedUtc | Should -Be '2025-11-17T00:00:00.0000000Z'
        $Rows[1].State | Should -Be 'Queued'
        @($Rows[1].Recipients).Count | Should -Be 0
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Filter -eq "PartitionKey eq 'c0ffee00-1111-2222-3333-444444444444' and Kind eq 'Operation'" }
        Should -Invoke Update-CIPPOneDriveCopyToUserStatus -Times 0 -Exactly
    }

    It 'sends Recipients as a JSON array when a copy has one recipient or none' {
        Mock Get-CIPPAzDataTableEntity {
            [pscustomobject]@{ RowKey = 'op-1'; Kind = 'Operation'; LeaverUPN = 'jane@contoso.com'; State = 'Completed'; RecipientSummary = '[{"UserPrincipalName":"bob@contoso.com","State":"Completed"}]' }
            [pscustomobject]@{ RowKey = 'op-2'; Kind = 'Operation'; LeaverUPN = 'pat@contoso.com' }
        }
        $Response = Invoke-ListOneDriveCopyToUser -Request (New-ListRequest @{ tenantFilter = 'contoso.com' })
        $Json = ConvertTo-Json -InputObject @($Response.Body) -Depth 5 -Compress
        $Json | Should -Match '"Recipients":\[\{"UserPrincipalName":"bob@contoso.com"'
        $Json | Should -Match '"Recipients":\[\]'
    }

    It 'returns BadRequest when tenantFilter is missing' {
        $Response = Invoke-ListOneDriveCopyToUser -Request (New-ListRequest @{ OperationId = 'op-1' })
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke Update-CIPPOneDriveCopyToUserStatus -Times 0 -Exactly
    }

    It 'returns NotFound for an unknown operation' {
        Mock Update-CIPPOneDriveCopyToUserStatus { throw [System.Management.Automation.ItemNotFoundException]::new('OneDrive copy operation not found.') }
        $Response = Invoke-ListOneDriveCopyToUser -Request (New-ListRequest @{ tenantFilter = 'contoso.com'; OperationId = 'op-1' })
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::NotFound)
        $Response.Body.Results | Should -BeLike 'Failed to retrieve OneDrive copies:*'
    }
}
