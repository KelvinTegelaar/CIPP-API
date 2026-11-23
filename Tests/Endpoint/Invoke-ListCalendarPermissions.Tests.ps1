# Pester tests for the live path of Invoke-ListCalendarPermissions: each grantee is labelled
# Internal, External or External (published link). Exchange's JSON names grantees as plain strings,
# so the label comes from the string's shape, with a resolved UserId overriding it.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListCalendarPermissions.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ListCalendarPermissions.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $anchor, $Select, $UseSystemMailbox) }
    function Resolve-CIPPFolderPermissionUser { param($TenantFilter, $FolderIdentity, $Permissions) }
    function Get-NormalizedError { param($Message) $Message }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }

    . $FunctionPath

    $script:Request = [pscustomobject]@{
        Params = @{ CIPPEndpoint = 'ListCalendarPermissions' }
        Query  = [pscustomobject]@{ UserID = 'owner@contoso.com'; tenantFilter = 'contoso.com' }
    }
}

Describe 'Invoke-ListCalendarPermissions live grantee scope' {
    BeforeAll {
        Mock New-ExoRequest -ParameterFilter { $cmdlet -eq 'Get-MailboxFolderStatistics' } { @([pscustomobject]@{ Name = 'Calendar'; FolderType = 'Calendar' }) }
        Mock New-ExoRequest -ParameterFilter { $cmdlet -eq 'Get-Mailbox' } { [pscustomobject]@{ UserPrincipalName = 'owner@contoso.com' } }
        Mock New-ExoRequest -ParameterFilter { $cmdlet -eq 'Get-MailboxFolderPermission' } { @() }
        Mock Resolve-CIPPFolderPermissionUser {
            @(
                [pscustomobject]@{ Identity = 'owner:\Calendar'; User = 'Default'; UserId = $null; AccessRights = @('LimitedDetails'); FolderName = 'Calendar' }
                [pscustomobject]@{ Identity = 'owner:\Calendar'; User = 'Anonymous'; UserId = $null; AccessRights = @('None'); FolderName = 'Calendar' }
                [pscustomobject]@{ Identity = 'owner:\Calendar'; User = 'Calendar Test Group'; UserId = 'ccc95183-fec2-4953-9e72-461e86685d49'; AccessRights = @('Reviewer'); FolderName = 'Calendar' }
                [pscustomobject]@{ Identity = 'owner:\Calendar'; User = 'socials@fabrikam.com'; UserId = $null; AccessRights = @('Reviewer'); FolderName = 'Calendar' }
                [pscustomobject]@{ Identity = 'owner:\Calendar'; User = 'ExchangePublishedUser.friend@gmail.com'; UserId = $null; AccessRights = @('Reviewer'); FolderName = 'Calendar' }
                [pscustomobject]@{ Identity = 'owner:\Calendar'; User = 'jane@contoso.com'; UserId = '0e86800e-9793-461e-a21b-3e8c4774a06c'; AccessRights = @('Editor'); FolderName = 'Calendar' }
            )
        }

        $Response = Invoke-ListCalendarPermissions -Request $script:Request -TriggerMetadata $null
        $script:Status = $Response.StatusCode
        $script:Rows = @{}
        foreach ($Row in $Response.Body) { $script:Rows[$Row.User] = $Row }
    }

    It 'returns 200 with every grantee' {
        $script:Status | Should -Be 200
        $script:Rows.Count | Should -Be 6
    }

    It 'leaves Default and Anonymous unlabelled' {
        $script:Rows['Default'].AccessScope | Should -BeNullOrEmpty
        $script:Rows['Anonymous'].AccessScope | Should -BeNullOrEmpty
    }

    It 'labels a display-name grantee Internal' {
        $script:Rows['Calendar Test Group'].AccessScope | Should -Be 'Internal'
        $script:Rows['Calendar Test Group'].ExternalAddress | Should -BeNullOrEmpty
    }

    It 'labels an unresolved address External, with the address' {
        $script:Rows['socials@fabrikam.com'].AccessScope | Should -Be 'External'
        $script:Rows['socials@fabrikam.com'].ExternalAddress | Should -Be 'socials@fabrikam.com'
    }

    It 'labels an ExchangePublishedUser grantee as a published link and strips the prefix' {
        $Row = $script:Rows['ExchangePublishedUser.friend@gmail.com']
        $Row.AccessScope | Should -Be 'External (published link)'
        $Row.ExternalAddress | Should -Be 'friend@gmail.com'
    }

    It 'keeps a resolved recipient Internal even when its display name is an address' {
        $script:Rows['jane@contoso.com'].AccessScope | Should -Be 'Internal'
    }

    It 'keeps the raw User value the remove action sends back' {
        $script:Rows['ExchangePublishedUser.friend@gmail.com'].User | Should -Be 'ExchangePublishedUser.friend@gmail.com'
        $script:Rows['ExchangePublishedUser.friend@gmail.com'].MailboxInfo.UserPrincipalName | Should -Be 'owner@contoso.com'
    }
}
