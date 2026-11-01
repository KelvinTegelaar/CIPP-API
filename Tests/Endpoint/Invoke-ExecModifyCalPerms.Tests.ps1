# Pester tests for Invoke-ExecModifyCalPerms
# Covers the bulk 'mailboxRequests' shape used by the Calendar Permissions Report bulk remove,
# the legacy single-mailbox shape, and per-mailbox failure isolation in bulk mode. The EXO work
# itself lives in Set-CIPPCalendarPermission, which is mocked here.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecModifyCalPerms.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecModifyCalPerms.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-GraphGetRequest { param($uri, $tenantid) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Set-CIPPCalendarPermission {
        param($APIName, $Headers, $RemoveAccess, $TenantFilter, $UserID, $FolderName, $UserToGetPermissions, $LoggingName, $Permissions, $CanViewPrivateItems, $SendNotificationToUser, $CacheContext)
    }

    . $FunctionPath
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')

    function New-Request {
        param($Body)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecModifyCalPerms' }
            Headers = @{ Authorization = 'token' }
            Body    = $Body
        }
    }
    function New-RemovePerm {
        param($User, $Level = 'Editor', $FolderName = 'Calendar')
        [pscustomobject]@{ UserID = $User; PermissionLevel = $Level; FolderName = $FolderName; Modification = 'Remove' }
    }
}

Describe 'Invoke-ExecModifyCalPerms' {
    BeforeEach {
        Mock -CommandName New-GraphGetRequest -MockWith {
            param($uri, $tenantid)
            if ($uri -match 'missing@') { throw 'not found' }
            [pscustomobject]@{ id = if ($uri -match 'room@') { '22222222-2222-2222-2222-222222222222' } else { '11111111-1111-1111-1111-111111111111' } }
        }
        Mock -CommandName Get-CippException -MockWith { [pscustomobject]@{ NormalizedError = 'not found' } }
        Mock -CommandName Write-LogMessage -MockWith { }
        $script:Contexts = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Set-CIPPCalendarPermission -MockWith { $script:Contexts.Add($CacheContext); "removed $RemoveAccess from $UserID" }
    }

    Context 'Bulk mailboxRequests shape' {
        It 'removes every grant on every mailbox, passing FolderName and the display name through' {
            $Body = [pscustomobject]@{
                tenantFilter    = 'contoso.com'
                mailboxRequests = @(
                    [pscustomobject]@{ userID = 'alice@contoso.com'; permissions = @((New-RemovePerm 'Bob Jones' 'Reviewer' 'Kalender'), (New-RemovePerm 'Carol')) }
                    [pscustomobject]@{ userID = 'room@contoso.com'; permissions = @(New-RemovePerm 'Bob Jones') }
                )
            }
            $Response = Invoke-ExecModifyCalPerms -Request (New-Request $Body) -TriggerMetadata $null

            $Response.StatusCode | Should -Be 200
            @($Response.Body.Results).Count | Should -Be 3
            Should -Invoke Set-CIPPCalendarPermission -Times 3 -Exactly
            Should -Invoke Set-CIPPCalendarPermission -Times 1 -Exactly -ParameterFilter {
                $RemoveAccess -eq 'Bob Jones' -and $FolderName -eq 'Kalender' -and $Permissions -eq 'Reviewer' -and
                $UserID -eq '11111111-1111-1111-1111-111111111111' -and $TenantFilter -eq 'contoso.com'
            }
            Should -Invoke Set-CIPPCalendarPermission -Times 1 -Exactly -ParameterFilter {
                $RemoveAccess -eq 'Bob Jones' -and $UserID -eq '22222222-2222-2222-2222-222222222222'
            }
            # One cache context for the whole request, so the cache sync reads the tenant's cache once
            $script:Contexts[0] | Should -BeOfType [hashtable]
            $script:Contexts | ForEach-Object { [object]::ReferenceEquals($_, $script:Contexts[0]) | Should -BeTrue }
        }

        It 'keeps processing the batch when one mailbox cannot be resolved' {
            $Body = [pscustomobject]@{
                tenantFilter    = 'contoso.com'
                mailboxRequests = @(
                    [pscustomobject]@{ userID = 'missing@contoso.com'; permissions = @(New-RemovePerm 'Bob Jones') }
                    [pscustomobject]@{ userID = 'alice@contoso.com'; permissions = @(New-RemovePerm 'Bob Jones') }
                )
            }
            $Response = Invoke-ExecModifyCalPerms -Request (New-Request $Body) -TriggerMetadata $null

            Should -Invoke Set-CIPPCalendarPermission -Times 1 -Exactly
            $Response.Body.Results | Should -Contain 'Failed to get user ID for missing@contoso.com: not found'
            $Response.StatusCode | Should -Not -Be 404
        }
    }

    Context 'Legacy single-mailbox shape' {
        It 'still processes userID + permissions' {
            $Body = [pscustomobject]@{ tenantFilter = 'contoso.com'; userID = 'alice@contoso.com'; permissions = @(New-RemovePerm 'Bob Jones') }
            $Response = Invoke-ExecModifyCalPerms -Request (New-Request $Body) -TriggerMetadata $null

            $Response.StatusCode | Should -Be 200
            Should -Invoke Set-CIPPCalendarPermission -Times 1 -Exactly -ParameterFilter { $RemoveAccess -eq 'Bob Jones' -and $FolderName -eq 'Calendar' }
        }

        It 'returns 400 when userID is missing' {
            $Body = [pscustomobject]@{ tenantFilter = 'contoso.com'; permissions = @(New-RemovePerm 'Bob Jones') }
            (Invoke-ExecModifyCalPerms -Request (New-Request $Body) -TriggerMetadata $null).StatusCode | Should -Be 400
        }

        It 'returns 404 when the mailbox cannot be resolved' {
            $Body = [pscustomobject]@{ tenantFilter = 'contoso.com'; userID = 'missing@contoso.com'; permissions = @(New-RemovePerm 'Bob Jones') }
            (Invoke-ExecModifyCalPerms -Request (New-Request $Body) -TriggerMetadata $null).StatusCode | Should -Be 404
            Should -Invoke Set-CIPPCalendarPermission -Times 0 -Exactly
        }
    }
}
