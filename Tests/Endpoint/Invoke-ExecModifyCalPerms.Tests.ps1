# Pester tests for Invoke-ExecModifyCalPerms
# Covers the bulk 'mailboxRequests' shape (mailbox list bulk add, Calendar Permissions Report bulk remove),
# the legacy single-mailbox shape, folder resolution, the Add -> Set pass for existing entries, and
# per-mailbox failure isolation. EXO and Graph are mocked at New-ExoBulkRequest / New-GraphBulkRequest.

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

    function New-GraphBulkRequest { param($tenantid, $Requests) }
    function New-ExoBulkRequest { param($tenantid, $cmdletArray, $ReturnWithCommand, $MaxConcurrency, [switch]$AnchorPerMailbox) }
    function Remove-CIPPFolderPermission { param($TenantFilter, $FolderIdentity, $User, $AccessRights, $Anchor) }
    function Sync-CIPPCalendarPermissionCache { param($TenantFilter, $MailboxIdentity, $FolderName, $User, $Permissions, $Action, $CacheContext) }
    function Get-CippException { param($Exception) }
    function Get-NormalizedError { param($Message) $Message }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }

    . $FunctionPath
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')

    $script:AliceId = '11111111-1111-1111-1111-111111111111'
    $script:RoomId = '22222222-2222-2222-2222-222222222222'

    function New-Request {
        param($Body)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecModifyCalPerms' }
            Headers = @{ Authorization = 'token' }
            Body    = $Body
        }
    }
    function New-Perm {
        param($User, $Level = 'Editor', $FolderName, $Modification = 'Remove')
        $Perm = [pscustomobject]@{ UserID = $User; PermissionLevel = $Level; Modification = $Modification }
        if ($FolderName) { $Perm | Add-Member -NotePropertyName FolderName -NotePropertyValue $FolderName }
        $Perm
    }
}

Describe 'Invoke-ExecModifyCalPerms' {
    BeforeEach {
        # UPN lookups: alice and room resolve, anything else is missing
        Mock -CommandName New-GraphBulkRequest -MockWith {
            foreach ($Req in $Requests) {
                $Id = if ($Req.url -match '^users/alice@') { $script:AliceId } elseif ($Req.url -match '^users/room@') { $script:RoomId }
                [pscustomobject]@{ id = $Req.id; status = if ($Id) { 200 } else { 404 }; body = [pscustomobject]@{ id = $Id } }
            }
        }
        $script:ExoCalls = [System.Collections.Generic.List[object]]::new()
        $script:Existing = @()
        $script:Ambiguous = @()
        Mock -CommandName New-ExoBulkRequest -MockWith {
            $script:ExoCalls.Add(@($cmdletArray))
            $Out = @{}
            foreach ($Cmd in $cmdletArray) {
                $Name = $Cmd.CmdletInput.CmdletName
                $P = $Cmd.CmdletInput.Parameters
                $Result = switch ($Name) {
                    'Get-MailboxFolderStatistics' { [pscustomobject]@{ OperationGuid = $Cmd.OperationGuid; FolderType = 'Calendar'; Name = 'Kalender'; FolderId = "fid-$($P.Identity)" } }
                    'Add-MailboxFolderPermission' {
                        if ($P.User -in $script:Existing) { [pscustomobject]@{ OperationGuid = $Cmd.OperationGuid; error = '|Microsoft.Exchange.Management.StoreTasks.UserAlreadyExistsInPermissionEntryException|An existing permission entry was found' } }
                        else { [pscustomobject]@{ OperationGuid = $Cmd.OperationGuid } }
                    }
                    'Remove-MailboxFolderPermission' {
                        if ($P.User -in $script:Ambiguous) { [pscustomobject]@{ OperationGuid = $Cmd.OperationGuid; error = '|ManagementObjectAmbiguousException|ambiguous' } }
                        else { [pscustomobject]@{ OperationGuid = $Cmd.OperationGuid } }
                    }
                    default { [pscustomobject]@{ OperationGuid = $Cmd.OperationGuid } }
                }
                if (-not $Out[$Name]) { $Out[$Name] = [System.Collections.Generic.List[object]]::new() }
                $Out[$Name].Add($Result)
            }
            $Out
        }
        Mock -CommandName Remove-CIPPFolderPermission -MockWith { $User }
        $script:Contexts = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Sync-CIPPCalendarPermissionCache -MockWith { $script:Contexts.Add($CacheContext) }
        Mock -CommandName Get-CippException -MockWith { [pscustomobject]@{ NormalizedError = 'boom' } }
        Mock -CommandName Write-LogMessage -MockWith { }
    }

    Context 'Bulk add from the mailbox list' {
        It 'resolves each localized calendar by folder id, skips Graph for object ids, and routes per mailbox' {
            $Add = New-Perm -User @([pscustomobject]@{ label = 'Bob'; value = 'bob@contoso.com' }, [pscustomobject]@{ label = 'Carol'; value = 'carol@contoso.com' }) -Level 'Reviewer' -Modification 'Add'
            $Body = [pscustomobject]@{
                tenantFilter    = 'contoso.com'
                mailboxRequests = @(
                    [pscustomobject]@{ userID = $script:AliceId; permissions = @($Add) }
                    [pscustomobject]@{ userID = 'room@contoso.com'; permissions = @($Add) }
                )
            }
            $Response = Invoke-ExecModifyCalPerms -Request (New-Request $Body) -TriggerMetadata $null

            $Response.StatusCode | Should -Be 200
            @($Response.Body.Results).Count | Should -Be 4
            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { @($Requests).Count -eq 1 -and $Requests[0].url -match '^users/room@' }
            Should -Invoke New-ExoBulkRequest -Times 2 -Exactly -ParameterFilter { $AnchorPerMailbox }
            $Adds = @($script:ExoCalls[1])
            $Adds.Count | Should -Be 4
            $Adds.CmdletInput.CmdletName | Sort-Object -Unique | Should -Be 'Add-MailboxFolderPermission'
            $Adds.CmdletInput.Parameters.Identity | Sort-Object -Unique | Should -Be @("$($script:AliceId):fid-$($script:AliceId)", "$($script:RoomId):fid-$($script:RoomId)")
            Should -Invoke Sync-CIPPCalendarPermissionCache -Times 4 -Exactly -ParameterFilter { $FolderName -eq 'Kalender' -and $Action -eq 'Add' -and $Permissions -eq 'Reviewer' }
            # One cache context for the whole request, so the cache sync reads the tenant's cache once
            $script:Contexts | ForEach-Object { [object]::ReferenceEquals($_, $script:Contexts[0]) | Should -BeTrue }
        }

        It 'updates entries that already exist with Set in a second pass' {
            $script:Existing = @('bob@contoso.com')
            $Add = New-Perm -User @('bob@contoso.com', 'carol@contoso.com') -Level 'Editor' -Modification 'Add'
            $Add | Add-Member -NotePropertyName CanViewPrivateItems -NotePropertyValue $true
            $Body = [pscustomobject]@{ tenantFilter = 'contoso.com'; mailboxRequests = @([pscustomobject]@{ userID = $script:AliceId; permissions = @($Add) }) }
            $Response = Invoke-ExecModifyCalPerms -Request (New-Request $Body) -TriggerMetadata $null

            $Response.StatusCode | Should -Be 200
            $Sets = @($script:ExoCalls[2])
            $Sets.Count | Should -Be 1
            $Sets[0].CmdletInput.CmdletName | Should -Be 'Set-MailboxFolderPermission'
            $Sets[0].CmdletInput.Parameters.User | Should -Be 'bob@contoso.com'
            $Sets[0].CmdletInput.Parameters.SharingPermissionFlags | Should -Be 'Delegate,CanViewPrivateItems'
            @($Response.Body.Results) | Should -Not -Match '^Failed'
        }
    }

    Context 'Bulk remove from the report' {
        It 'removes with the listed folder name and resolves a display name shared by two recipients' {
            $script:Ambiguous = @('Bob Jones')
            $Body = [pscustomobject]@{
                tenantFilter    = 'contoso.com'
                mailboxRequests = @([pscustomobject]@{ userID = 'alice@contoso.com'; permissions = @((New-Perm 'Bob Jones' 'Reviewer' 'Kalender'), (New-Perm 'Carol' 'Editor' 'Kalender')) })
            }
            $Response = Invoke-ExecModifyCalPerms -Request (New-Request $Body) -TriggerMetadata $null

            $Response.StatusCode | Should -Be 200
            # A FolderName was supplied, so no folder lookup
            $script:ExoCalls.Count | Should -Be 1
            $script:ExoCalls[0].CmdletInput.Parameters.Identity | Sort-Object -Unique | Should -Be "$($script:AliceId):\Kalender"
            Should -Invoke Remove-CIPPFolderPermission -Times 1 -Exactly -ParameterFilter { $User -eq 'Bob Jones' -and $AccessRights -eq 'Reviewer' -and $Anchor -eq $script:AliceId }
            Should -Invoke Sync-CIPPCalendarPermissionCache -Times 2 -Exactly -ParameterFilter { $Action -eq 'Remove' -and $FolderName -eq 'Kalender' }
        }

        It 'keeps processing the batch when one mailbox cannot be resolved' {
            $Body = [pscustomobject]@{
                tenantFilter    = 'contoso.com'
                mailboxRequests = @(
                    [pscustomobject]@{ userID = 'missing@contoso.com'; permissions = @(New-Perm 'Bob Jones' -FolderName 'Calendar') }
                    [pscustomobject]@{ userID = 'alice@contoso.com'; permissions = @(New-Perm 'Bob Jones' -FolderName 'Calendar') }
                )
            }
            $Response = Invoke-ExecModifyCalPerms -Request (New-Request $Body) -TriggerMetadata $null

            $Response.StatusCode | Should -Be 207
            @($script:ExoCalls[0]).Count | Should -Be 1
            $Response.Body.Results | Should -Contain 'Failed to get user ID for missing@contoso.com: not found'
        }
    }

    Context 'Legacy single-mailbox shape' {
        It 'still processes userID + permissions' {
            $Body = [pscustomobject]@{ tenantFilter = 'contoso.com'; userID = 'alice@contoso.com'; permissions = @(New-Perm 'Bob Jones' -FolderName 'Calendar') }
            $Response = Invoke-ExecModifyCalPerms -Request (New-Request $Body) -TriggerMetadata $null

            $Response.StatusCode | Should -Be 200
            $script:ExoCalls[0][0].CmdletInput.Parameters.Identity | Should -Be "$($script:AliceId):\Calendar"
        }

        It 'returns 400 when userID is missing' {
            $Body = [pscustomobject]@{ tenantFilter = 'contoso.com'; permissions = @(New-Perm 'Bob Jones') }
            (Invoke-ExecModifyCalPerms -Request (New-Request $Body) -TriggerMetadata $null).StatusCode | Should -Be 400
        }

        It 'returns 404 when the mailbox cannot be resolved' {
            $Body = [pscustomobject]@{ tenantFilter = 'contoso.com'; userID = 'missing@contoso.com'; permissions = @(New-Perm 'Bob Jones') }
            (Invoke-ExecModifyCalPerms -Request (New-Request $Body) -TriggerMetadata $null).StatusCode | Should -Be 404
            Should -Invoke New-ExoBulkRequest -Times 0 -Exactly
        }
    }
}
