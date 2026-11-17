# Pester tests for Invoke-ExecOneDriveCopyToUser and Invoke-ListOneDriveCopyToUser

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
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

    function Start-CIPPOneDriveCopyToUser { param($TenantFilter, $Leaver, $Recipients, $IncludeVersionHistory, $StartedBy, $OperationId, $Headers, $APIName, [switch]$WaitForSignInBlock) }
    function Update-CIPPOneDriveCopyToUserStatus { param($TenantFilter, $OperationId) }
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

    It 'starts the copy with plain and {label,value} inputs and records who started it' {
        $Principal = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((@{ userDetails = 'tech@partner.com' } | ConvertTo-Json)))
        $Response = Invoke-ExecOneDriveCopyToUser -Request (New-ExecRequest @{
                tenantFilter          = 'contoso.com'
                leaver                = [pscustomobject]@{ label = 'Jane'; value = 'jane@contoso.com' }
                recipients            = @('bob@contoso.com', [pscustomobject]@{ label = 'Carol'; value = 'carol@contoso.com' }, 'dave@contoso.com, erin@contoso.com')
                includeVersionHistory = $true
            } @{ 'x-ms-client-principal' = $Principal })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.Results.OperationId | Should -Be '11111111-2222-3333-4444-555555555555'
        Should -Invoke Start-CIPPOneDriveCopyToUser -Times 1 -Exactly -ParameterFilter {
            $TenantFilter -eq 'contoso.com' -and $Leaver -eq 'jane@contoso.com' -and
            (@($Recipients) -join ';') -eq 'bob@contoso.com;carol@contoso.com;dave@contoso.com;erin@contoso.com' -and
            $IncludeVersionHistory -eq $true -and $StartedBy -eq 'tech@partner.com'
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

    It 'falls back to the API client name for StartedBy' {
        Invoke-ExecOneDriveCopyToUser -Request (New-ExecRequest @{ tenantFilter = 'contoso.com'; leaver = 'jane@contoso.com'; recipients = 'bob@contoso.com' } @{ 'x-ms-client-principal-name' = 'app-id-123' }) | Out-Null
        Should -Invoke Start-CIPPOneDriveCopyToUser -ParameterFilter { $StartedBy -eq 'app-id-123' -and $IncludeVersionHistory -eq $false }
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
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' }
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
    BeforeEach {
        Mock Update-CIPPOneDriveCopyToUserStatus { [pscustomobject]@{ OperationId = $OperationId; State = 'InProgress'; Recipients = @() } }
        Mock Write-LogMessage {}
    }

    It 'returns the status for the operation in the tenant' {
        $Response = Invoke-ListOneDriveCopyToUser -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ListOneDriveCopyToUser' }
                Headers = @{}
                Query   = @{ tenantFilter = 'contoso.com'; OperationId = 'op-1' }
            })
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.Results.State | Should -Be 'InProgress'
        Should -Invoke Update-CIPPOneDriveCopyToUserStatus -ParameterFilter { $TenantFilter -eq 'contoso.com' -and $OperationId -eq 'op-1' }
    }

    It 'returns BadRequest when <Missing> is missing' -ForEach @(
        @{ Missing = 'tenantFilter'; Query = @{ OperationId = 'op-1' } }
        @{ Missing = 'OperationId'; Query = @{ tenantFilter = 'contoso.com' } }
    ) {
        $Response = Invoke-ListOneDriveCopyToUser -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = 'ListOneDriveCopyToUser' }; Headers = @{}; Query = $Query })
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke Update-CIPPOneDriveCopyToUserStatus -Times 0 -Exactly
    }

    It 'returns NotFound for an unknown operation' {
        Mock Update-CIPPOneDriveCopyToUserStatus { throw [System.Management.Automation.ItemNotFoundException]::new('OneDrive copy operation not found.') }
        $Response = Invoke-ListOneDriveCopyToUser -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = 'ListOneDriveCopyToUser' }; Headers = @{}; Query = @{ tenantFilter = 'contoso.com'; OperationId = 'op-1' } })
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::NotFound)
    }
}
