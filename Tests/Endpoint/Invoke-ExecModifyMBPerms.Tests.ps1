# Pester tests for Invoke-ExecModifyMBPerms
# The endpoint delegates the permission-level -> EXO cmdlet/parameter mapping to
# Set-CIPPMailboxPermission (dot-sourced below and called in -AsCmdletObject mode), so these tests
# focus on what the endpoint owns: the single-operation vs bulk (New-ExoBulkRequest + GUID mapping)
# execution paths, the bulk-failure fallback, the three accepted input shapes, the user-lookup
# fallback, and the request guards. The mapping itself is covered by Set-CIPPMailboxPermission.Tests.ps1.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecModifyMBPerms.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecModifyMBPerms.ps1 under Modules/' }

    # Dot-source the REAL Set-CIPPMailboxPermission so -AsCmdletObject produces real mappings - the
    # endpoint now delegates the level -> cmdlet mapping to it. Its -AsCmdletObject path only builds a
    # hashtable and returns early, so none of the EXO / log stubs below are exercised by it.
    $PermissionFunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Set-CIPPMailboxPermission.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $PermissionFunctionPath) { throw 'Could not locate Set-CIPPMailboxPermission.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    # The function uses the short [HttpStatusCode]; register a type accelerator so it resolves here.
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-GraphGetRequest { param($uri, $tenantid) }
    function New-ExoRequest { param($Anchor, $tenantid, $cmdlet, $cmdParams) }
    function New-ExoBulkRequest { param($tenantid, $cmdletArray, $ReturnWithCommand) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Sync-CIPPMailboxPermissionCache { param($TenantFilter, $MailboxIdentity, $User, $PermissionType, $Action) }

    . $PermissionFunctionPath
    . $FunctionPath

    # Build a request in the bulk 'mailboxRequests' shape.
    function New-ModifyRequest {
        param($Mailboxes)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecModifyMBPerms' }
            Headers = @{ Authorization = 'token' }
            Body    = [pscustomobject]@{ tenantFilter = 'contoso.com'; mailboxRequests = $Mailboxes }
        }
    }

    # Build a single mailbox request object with one permission.
    function New-Perm {
        param($Level, $Modification, $TargetUser = 'user@contoso.com', $AutoMap = $true)
        [pscustomobject]@{
            PermissionLevel = $Level
            Modification    = $Modification
            AutoMap         = $AutoMap
            UserID          = @([pscustomobject]@{ value = $TargetUser })
        }
    }
    function New-Mailbox {
        param($UserID = 'shared@contoso.com', $Permissions)
        [pscustomobject]@{ userID = $UserID; permissions = $Permissions }
    }
}

Describe 'Invoke-ExecModifyMBPerms' {
    BeforeEach {
        Mock -CommandName New-GraphGetRequest -MockWith { [pscustomobject]@{ userPrincipalName = 'shared@contoso.com' } }
        Mock -CommandName New-ExoRequest -MockWith { }
        Mock -CommandName New-ExoBulkRequest -MockWith {
            param($tenantid, $cmdletArray, $ReturnWithCommand)
            # Echo each operation back as a success keyed by cmdlet name (GUID round-trips so the
            # function can map results to its metadata).
            $h = @{}
            foreach ($c in $cmdletArray) {
                $name = $c.CmdletInput.CmdletName
                if (-not $h.ContainsKey($name)) { $h[$name] = @() }
                $h[$name] += [pscustomobject]@{ OperationGuid = $c.OperationGuid }
            }
            $h
        }
        Mock -CommandName Get-CippException -MockWith { [pscustomobject]@{ NormalizedError = 'boom' } }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Sync-CIPPMailboxPermissionCache -MockWith { }
    }

    Context 'Single-operation execution and per-level mapping' {
        It 'FullAccess Add -> individual New-ExoRequest with Add-MailboxPermission' {
            $req = New-ModifyRequest -Mailboxes @(New-Mailbox -Permissions @(New-Perm -Level 'FullAccess' -Modification 'Add'))

            $response = Invoke-ExecModifyMBPerms -Request $req -TriggerMetadata $null

            $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
                $cmdlet -eq 'Add-MailboxPermission' -and $cmdParams.user -eq 'user@contoso.com' -and
                $cmdParams.Identity -eq 'shared@contoso.com' -and $cmdParams.automapping -eq $true
            }
            Should -Invoke New-ExoBulkRequest -Times 0 -Exactly
            $response.Body.Results | Should -Contain 'Granted user@contoso.com FullAccess to shared@contoso.com with automapping True'
        }

        It 'FullAccess Remove -> Remove-MailboxPermission' {
            $req = New-ModifyRequest -Mailboxes @(New-Mailbox -Permissions @(New-Perm -Level 'FullAccess' -Modification 'Remove'))
            $response = Invoke-ExecModifyMBPerms -Request $req -TriggerMetadata $null
            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Remove-MailboxPermission' }
            $response.Body.Results | Should -Contain 'Removed user@contoso.com FullAccess from shared@contoso.com'
        }

        It 'SendAs Add -> Add-RecipientPermission with Trustee' {
            $req = New-ModifyRequest -Mailboxes @(New-Mailbox -Permissions @(New-Perm -Level 'SendAs' -Modification 'Add'))
            Invoke-ExecModifyMBPerms -Request $req -TriggerMetadata $null
            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Add-RecipientPermission' -and $cmdParams.Trustee -eq 'user@contoso.com' }
        }

        It 'SendOnBehalf Add -> Set-Mailbox with GrantSendonBehalfTo add hashtable' {
            $req = New-ModifyRequest -Mailboxes @(New-Mailbox -Permissions @(New-Perm -Level 'SendOnBehalf' -Modification 'Add'))
            Invoke-ExecModifyMBPerms -Request $req -TriggerMetadata $null
            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
                $cmdlet -eq 'Set-Mailbox' -and $cmdParams.GrantSendonBehalfTo.add -eq 'user@contoso.com' -and
                $cmdParams.GrantSendonBehalfTo['@odata.type'] -eq '#Exchange.GenericHashTable'
            }
        }

        It 'SendOnBehalf Remove -> Set-Mailbox with GrantSendonBehalfTo remove hashtable' {
            $req = New-ModifyRequest -Mailboxes @(New-Mailbox -Permissions @(New-Perm -Level 'SendOnBehalf' -Modification 'Remove'))
            Invoke-ExecModifyMBPerms -Request $req -TriggerMetadata $null
            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Set-Mailbox' -and $cmdParams.GrantSendonBehalfTo.remove -eq 'user@contoso.com' }
        }

        It 'default-level Remove (<Level>) -> Remove-MailboxPermission with that access right' -ForEach @(
            @{ Level = 'ReadPermission' }
            @{ Level = 'ExternalAccount' }
            @{ Level = 'DeleteItem' }
            @{ Level = 'ChangePermission' }
            @{ Level = 'ChangeOwner' }
        ) {
            $req = New-ModifyRequest -Mailboxes @(New-Mailbox -Permissions @(New-Perm -Level $Level -Modification 'Remove'))
            Invoke-ExecModifyMBPerms -Request $req -TriggerMetadata $null
            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Remove-MailboxPermission' -and $cmdParams.accessRights -contains $Level }
        }

        It 'default-level Add produces no cmdlet -> OK with a no-op message' {
            $req = New-ModifyRequest -Mailboxes @(New-Mailbox -Permissions @(New-Perm -Level 'ReadPermission' -Modification 'Add'))
            $response = Invoke-ExecModifyMBPerms -Request $req -TriggerMetadata $null
            Should -Invoke New-ExoRequest -Times 0 -Exactly
            $response.Body.Results | Should -Contain 'No valid permission changes to process'
        }
    }

    Context 'Bulk execution path' {
        It 'two operations -> New-ExoBulkRequest with GUID-mapped results, no individual calls' {
            $req = New-ModifyRequest -Mailboxes @(New-Mailbox -Permissions @(
                (New-Perm -Level 'FullAccess' -Modification 'Add')
                (New-Perm -Level 'SendAs' -Modification 'Add')
            ))

            $response = Invoke-ExecModifyMBPerms -Request $req -TriggerMetadata $null

            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly
            Should -Invoke New-ExoRequest -Times 0 -Exactly
            $response.Body.Results | Should -Contain 'Granted user@contoso.com FullAccess to shared@contoso.com with automapping True'
            $response.Body.Results | Should -Contain 'Granted user@contoso.com SendAs permissions to shared@contoso.com'
        }

        It 'maps a per-operation error from the bulk result to an error string' {
            Mock -CommandName New-ExoBulkRequest -MockWith {
                param($tenantid, $cmdletArray, $ReturnWithCommand)
                $h = @{}
                foreach ($c in $cmdletArray) {
                    $name = $c.CmdletInput.CmdletName
                    if (-not $h.ContainsKey($name)) { $h[$name] = @() }
                    $h[$name] += [pscustomobject]@{ OperationGuid = $c.OperationGuid; error = 'kaboom' }
                }
                $h
            }
            $req = New-ModifyRequest -Mailboxes @(New-Mailbox -Permissions @(
                (New-Perm -Level 'FullAccess' -Modification 'Add')
                (New-Perm -Level 'SendAs' -Modification 'Add')
            ))

            $response = Invoke-ExecModifyMBPerms -Request $req -TriggerMetadata $null

            ($response.Body.Results -join "`n") | Should -Match 'Error processing FullAccess for user@contoso.com on shared@contoso.com: boom'
        }

        It 'falls back to individual New-ExoRequest calls when the bulk request throws' {
            Mock -CommandName New-ExoBulkRequest -MockWith { throw 'bulk endpoint down' }
            $req = New-ModifyRequest -Mailboxes @(New-Mailbox -Permissions @(
                (New-Perm -Level 'FullAccess' -Modification 'Add')
                (New-Perm -Level 'SendAs' -Modification 'Add')
            ))

            $response = Invoke-ExecModifyMBPerms -Request $req -TriggerMetadata $null

            Should -Invoke New-ExoRequest -Times 2 -Exactly
            $response.Body.Results | Should -Contain 'Granted user@contoso.com FullAccess to shared@contoso.com with automapping True'
        }
    }

    Context 'Input shapes' {
        It 'accepts the legacy single-mailbox format (userID + permissions on the body)' {
            $req = [pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecModifyMBPerms' }
                Headers = @{ Authorization = 'token' }
                Body    = [pscustomobject]@{
                    tenantFilter = 'contoso.com'
                    userID       = 'shared@contoso.com'
                    permissions  = @(New-Perm -Level 'FullAccess' -Modification 'Add')
                }
            }

            $response = Invoke-ExecModifyMBPerms -Request $req -TriggerMetadata $null

            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Add-MailboxPermission' }
            $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        }
    }

    Context 'User lookup' {
        It 'falls back to a userPrincipalName filter query when the direct Graph lookup fails' {
            Mock -CommandName New-GraphGetRequest -MockWith { [pscustomobject]@{ value = @([pscustomobject]@{ userPrincipalName = 'shared@contoso.com' }) } } -ParameterFilter { $uri -like '*filter*' }
            Mock -CommandName New-GraphGetRequest -MockWith { throw 'direct lookup failed' }

            $req = New-ModifyRequest -Mailboxes @(New-Mailbox -Permissions @(New-Perm -Level 'FullAccess' -Modification 'Add'))

            $response = Invoke-ExecModifyMBPerms -Request $req -TriggerMetadata $null

            Should -Invoke New-GraphGetRequest -ParameterFilter { $uri -like '*filter*' }
            Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Add-MailboxPermission' }
            $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        }

        It 'records a "could not find user" message when both lookups fail' {
            # Graph fails for 'ghost' on both the direct and filter lookups; a second valid mailbox
            # keeps CmdletArray non-empty so the specific message is not discarded by the
            # "No valid permission changes" guard (which returns only a generic string).
            Mock -CommandName New-GraphGetRequest -MockWith { throw 'not found' } -ParameterFilter { $uri -like '*ghost@contoso.com*' }

            $req = New-ModifyRequest -Mailboxes @(
                (New-Mailbox -UserID 'ghost@contoso.com' -Permissions @(New-Perm -Level 'FullAccess' -Modification 'Add'))
                (New-Mailbox -UserID 'valid@contoso.com' -Permissions @(New-Perm -Level 'FullAccess' -Modification 'Add'))
            )

            $response = Invoke-ExecModifyMBPerms -Request $req -TriggerMetadata $null

            ($response.Body.Results -join "`n") | Should -Match 'Could not find user ghost@contoso.com'
        }
    }

    Context 'Cache sync' {
        # The endpoint executes cmdlets itself (bypassing Set-CIPPMailboxPermission's execute-mode
        # sync), so it must sync the reporting-DB cache for every operation that succeeded.
        It 'syncs the cache after a successful single Remove' {
            $req = New-ModifyRequest -Mailboxes @(New-Mailbox -Permissions @(New-Perm -Level 'FullAccess' -Modification 'Remove'))

            Invoke-ExecModifyMBPerms -Request $req -TriggerMetadata $null

            Should -Invoke Sync-CIPPMailboxPermissionCache -Times 1 -Exactly -ParameterFilter {
                $TenantFilter -eq 'contoso.com' -and $MailboxIdentity -eq 'shared@contoso.com' -and
                $User -eq 'user@contoso.com' -and $PermissionType -eq 'FullAccess' -and $Action -eq 'Remove'
            }
        }

        It 'syncs with the resolved UPN when the request identifies the mailbox by object id' {
            # Cached permission rows are keyed by mailbox UPN, so the sync must use what the
            # Graph lookup resolved (BeforeEach mock: shared@contoso.com), not the raw request id.
            $req = New-ModifyRequest -Mailboxes @(New-Mailbox -UserID '11111111-2222-3333-4444-555555555555' -Permissions @(New-Perm -Level 'FullAccess' -Modification 'Remove'))

            Invoke-ExecModifyMBPerms -Request $req -TriggerMetadata $null

            Should -Invoke Sync-CIPPMailboxPermissionCache -Times 1 -Exactly -ParameterFilter {
                $MailboxIdentity -eq 'shared@contoso.com'
            }
        }

        It 'syncs with Action Add for additions' {
            $req = New-ModifyRequest -Mailboxes @(New-Mailbox -Permissions @(New-Perm -Level 'SendAs' -Modification 'Add'))

            Invoke-ExecModifyMBPerms -Request $req -TriggerMetadata $null

            Should -Invoke Sync-CIPPMailboxPermissionCache -Times 1 -Exactly -ParameterFilter {
                $PermissionType -eq 'SendAs' -and $Action -eq 'Add'
            }
        }

        It 'syncs every successful operation in a bulk request' {
            $req = New-ModifyRequest -Mailboxes @(New-Mailbox -Permissions @(
                (New-Perm -Level 'FullAccess' -Modification 'Remove')
                (New-Perm -Level 'SendOnBehalf' -Modification 'Remove')
            ))

            Invoke-ExecModifyMBPerms -Request $req -TriggerMetadata $null

            Should -Invoke Sync-CIPPMailboxPermissionCache -Times 1 -Exactly -ParameterFilter { $PermissionType -eq 'FullAccess' }
            Should -Invoke Sync-CIPPMailboxPermissionCache -Times 1 -Exactly -ParameterFilter { $PermissionType -eq 'SendOnBehalf' }
        }

        It 'does not sync operations that failed in the bulk response' {
            # FullAccess Remove (Remove-MailboxPermission) succeeds; SendAs Remove
            # (Remove-RecipientPermission) comes back with an error attached.
            Mock -CommandName New-ExoBulkRequest -MockWith {
                param($tenantid, $cmdletArray, $ReturnWithCommand)
                $h = @{}
                foreach ($c in $cmdletArray) {
                    $name = $c.CmdletInput.CmdletName
                    if (-not $h.ContainsKey($name)) { $h[$name] = @() }
                    $entry = [pscustomobject]@{ OperationGuid = $c.OperationGuid }
                    if ($name -eq 'Remove-RecipientPermission') {
                        $entry | Add-Member -NotePropertyName error -NotePropertyValue 'denied'
                    }
                    $h[$name] += $entry
                }
                $h
            }
            $req = New-ModifyRequest -Mailboxes @(New-Mailbox -Permissions @(
                (New-Perm -Level 'FullAccess' -Modification 'Remove')
                (New-Perm -Level 'SendAs' -Modification 'Remove')
            ))

            Invoke-ExecModifyMBPerms -Request $req -TriggerMetadata $null

            Should -Invoke Sync-CIPPMailboxPermissionCache -Times 1 -Exactly
            Should -Invoke Sync-CIPPMailboxPermissionCache -Times 1 -Exactly -ParameterFilter { $PermissionType -eq 'FullAccess' }
        }

        It 'does not sync non-cacheable permission levels' {
            # Comma-joined levels are split per operation; ReadPermission executes but has no
            # cache representation, so only the FullAccess half syncs.
            $req = New-ModifyRequest -Mailboxes @(New-Mailbox -Permissions @(New-Perm -Level 'FullAccess, ReadPermission' -Modification 'Remove'))

            Invoke-ExecModifyMBPerms -Request $req -TriggerMetadata $null

            Should -Invoke Sync-CIPPMailboxPermissionCache -Times 1 -Exactly
            Should -Invoke Sync-CIPPMailboxPermissionCache -Times 1 -Exactly -ParameterFilter { $PermissionType -eq 'FullAccess' }
        }
    }

    Context 'Guards' {
        It 'returns BadRequest when no mailbox requests are provided' {
            $req = [pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecModifyMBPerms' }
                Headers = @{ Authorization = 'token' }
                Body    = [pscustomobject]@{ tenantFilter = 'contoso.com' }
            }

            $response = Invoke-ExecModifyMBPerms -Request $req -TriggerMetadata $null

            $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $response.Body.Results | Should -Contain 'No mailbox requests provided'
        }

        It 'skips a mailbox request that is missing its userID' {
            # A second valid mailbox keeps CmdletArray non-empty so the "Skipped" message survives
            # (the empty-array guard would otherwise replace Results with a generic string).
            $req = New-ModifyRequest -Mailboxes @(
                (New-Mailbox -UserID '' -Permissions @(New-Perm -Level 'FullAccess' -Modification 'Add'))
                (New-Mailbox -UserID 'valid@contoso.com' -Permissions @(New-Perm -Level 'FullAccess' -Modification 'Add'))
            )

            $response = Invoke-ExecModifyMBPerms -Request $req -TriggerMetadata $null

            Should -Invoke New-ExoRequest -Times 1 -Exactly
            ($response.Body.Results -join "`n") | Should -Match 'Skipped mailbox with missing userID'
        }
    }
}
