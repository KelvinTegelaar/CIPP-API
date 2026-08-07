# Pester tests for the membership handling in Invoke-EditGroup.
#
# This is the Groups page (and the "Add to Group" user action, which posts a different shape into
# the same endpoint). It carries yet another copy of the Exchange-vs-Graph routing decision, taken
# from the group type the form supplied - $UserObj.groupId.addedFields.groupType, falling back to
# $UserObj.groupType.
#
# Worth knowing while reading these: adds and removes use different Graph verbs. An add is a PATCH
# of members@odata.bind on the group, a remove is a DELETE of the member's $ref. Owners on an
# Exchange group are not a membership at all - they are rewritten wholesale via the ManagedBy
# property of Set-DistributionGroup, so a remove has to be expressed as "the list without them".

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Groups/Invoke-EditGroup.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Invoke-EditGroup.ps1 at $FunctionPath" }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, $ComplexFilter, $Select) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $body, $AsApp) }
    function New-GraphBulkRequest { param($Requests, $tenantid, $scope, $asapp) }
    function New-ExoBulkRequest { param($tenantid, $cmdletArray, $useSystemMailbox) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Select, $Anchor, $UseSystemMailbox) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-NormalizedError { param($message) $message }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Set-CIPPGroupLicense { param($GroupId, $TenantFilter, $AddLicenses, $RemoveLicenses, $Headers, $APIName) }

    # Real helper, not a stub: matching Exchange bulk results back to operations is exactly what
    # the reporting assertions below are checking.
    $ResolverPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Resolve-CippExoBulkResult.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $ResolverPath) { throw 'Could not locate Resolve-CippExoBulkResult.ps1 under Modules/' }
    . $ResolverPath

    . $FunctionPath

    # The Edit Group page posts the group as an autocomplete option carrying its type.
    # groupName rather than displayName: displayName also triggers the separate group-properties
    # edit, which would queue a Set-DistributionGroup ahead of the membership calls under test.
    function New-GroupRequest {
        param([string]$GroupType = 'Security', [hashtable]$Body = @{})
        $RequestBody = [pscustomobject]@{
            tenantFilter = 'contoso.com'
            groupName    = 'All Office'
            groupId      = [pscustomobject]@{
                value       = 'group-guid'
                label       = 'All Office'
                addedFields = [pscustomobject]@{ groupType = $GroupType }
            }
        }
        foreach ($Key in $Body.Keys) {
            $RequestBody | Add-Member -NotePropertyName $Key -NotePropertyValue $Body[$Key] -Force
        }
        [pscustomobject]@{
            Body    = $RequestBody
            Headers = @{}
            Params  = @{ CIPPEndpoint = 'EditGroup' }
        }
    }

    # A member as either form posts it: the page sends an option, the user action sends a UPN.
    function New-Member {
        param([string]$Upn, [string]$Value)
        [pscustomobject]@{
            label       = $Upn
            value       = $Value
            addedFields = [pscustomobject]@{ userPrincipalName = $Upn }
        }
    }
}

Describe 'Invoke-EditGroup - membership' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName New-GraphGetRequest -MockWith { [pscustomobject]@{ id = 'group-guid'; displayName = 'All Office' } }
        Mock -CommandName New-GraphBulkRequest -MockWith { @() }
        Mock -CommandName New-ExoBulkRequest -MockWith { @() }
        Mock -CommandName New-ExoRequest -MockWith { @() }
        Mock -CommandName Set-CIPPGroupLicense -MockWith { }
    }

    Context 'Adding members' {
        It 'PATCHes the member binding for a security group' {
            $Request = New-GroupRequest -GroupType 'Security' -Body @{
                AddMember = @(New-Member -Upn 'sseck@contoso.com' -Value 'user-guid')
            }

            $null = Invoke-EditGroup -Request $Request

            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Requests[0].method -eq 'PATCH' -and
                $Requests[0].url -eq 'groups/group-guid' -and
                $Requests[0].body.'members@odata.bind' -contains 'https://graph.microsoft.com/v1.0/directoryObjects/user-guid'
            }
            Should -Invoke New-ExoBulkRequest -Times 0 -Exactly
        }

        It 'uses Add-DistributionGroupMember for a <GroupType>' -ForEach @(
            @{ GroupType = 'Distribution List' }
            @{ GroupType = 'Mail-Enabled Security' }
        ) {
            $Request = New-GroupRequest -GroupType $GroupType -Body @{
                AddMember = @(New-Member -Upn 'sseck@contoso.com' -Value 'user-guid')
            }

            $null = Invoke-EditGroup -Request $Request

            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly -ParameterFilter {
                $cmdletArray[0].CmdletInput.CmdletName -eq 'Add-DistributionGroupMember' -and
                $cmdletArray[0].CmdletInput.Parameters.Identity -eq 'group-guid' -and
                $cmdletArray[0].CmdletInput.Parameters.Member -eq 'sseck@contoso.com' -and
                $cmdletArray[0].CmdletInput.Parameters.BypassSecurityGroupManagerCheck -eq $true
            }
            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
        }

        It 'batches several members into one bulk call' {
            $Request = New-GroupRequest -GroupType 'Security' -Body @{
                AddMember = @(
                    New-Member -Upn 'one@contoso.com' -Value 'user-1'
                    New-Member -Upn 'two@contoso.com' -Value 'user-2'
                )
            }

            $null = Invoke-EditGroup -Request $Request

            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { $Requests.Count -eq 2 }
        }

        It 'resolves a member given only as a UPN by the Add to Group user action' {
            # That action posts bare strings rather than autocomplete options.
            Mock -CommandName New-GraphGetRequest -MockWith { [pscustomobject]@{ id = 'resolved-guid' } } -ParameterFilter { $uri -like '*/users/*' }
            $Request = New-GroupRequest -GroupType 'Security' -Body @{ AddMember = @('sseck@contoso.com') }

            $null = Invoke-EditGroup -Request $Request

            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Requests[0].body.'members@odata.bind' -contains 'https://graph.microsoft.com/v1.0/directoryObjects/resolved-guid'
            }
        }

        It 'reports success per member once the batch comes back clean' {
            $Request = New-GroupRequest -GroupType 'Security' -Body @{
                AddMember = @(New-Member -Upn 'sseck@contoso.com' -Value 'user-guid')
            }
            Mock -CommandName New-GraphBulkRequest -MockWith {
                @([pscustomobject]@{ id = 'addMember-sseck@contoso.com'; status = 204 })
            }

            $Response = Invoke-EditGroup -Request $Request

            $Response.Body.Results | Should -Contain 'Success - Added member sseck@contoso.com to All Office group'
        }

        It 'renders a structured Graph error as its message, not as a hashtable dump' {
            # Graph returns body.error as an object; passing it through whole showed the operator
            # "@{code=Request_BadRequest; message=...; innerError=}".
            $Request = New-GroupRequest -GroupType 'Security' -Body @{
                AddMember = @(New-Member -Upn 'sseck@contoso.com' -Value 'user-guid')
            }
            Mock -CommandName New-GraphBulkRequest -MockWith {
                @([pscustomobject]@{
                        id     = 'addMember-sseck@contoso.com'
                        status = 400
                        body   = [pscustomobject]@{
                            error = [pscustomobject]@{
                                code       = 'Request_BadRequest'
                                message    = 'The group must have at least one owner.'
                                innerError = [pscustomobject]@{}
                            }
                        }
                    })
            }

            $Response = Invoke-EditGroup -Request $Request

            $Response.Body.Results | Should -Contain 'Error - The group must have at least one owner.'
            "$($Response.Body.Results)" | Should -Not -BeLike '*Request_BadRequest*'
        }

        It 'reports the Graph error when a member add comes back non-2xx' {
            $Request = New-GroupRequest -GroupType 'Security' -Body @{
                AddMember = @(New-Member -Upn 'sseck@contoso.com' -Value 'user-guid')
            }
            Mock -CommandName New-GraphBulkRequest -MockWith {
                @([pscustomobject]@{
                        id     = 'addMember-sseck@contoso.com'
                        status = 400
                        body   = [pscustomobject]@{ error = 'Cannot Update a mail-enabled security groups and or distribution list.' }
                    })
            }

            $Response = Invoke-EditGroup -Request $Request

            $Response.Body.Results | Should -Contain 'Error - Cannot Update a mail-enabled security groups and or distribution list.'
        }
    }

    Context 'Removing members' {
        It 'DELETEs the member reference for a security group' {
            $Request = New-GroupRequest -GroupType 'Security' -Body @{
                RemoveMember = @(New-Member -Upn 'sseck@contoso.com' -Value 'user-guid')
            }

            $null = Invoke-EditGroup -Request $Request

            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Requests[0].method -eq 'DELETE' -and
                $Requests[0].url -eq 'groups/group-guid/members/user-guid/$ref'
            }
        }

        It 'uses Remove-DistributionGroupMember for a distribution list' {
            $Request = New-GroupRequest -GroupType 'Distribution List' -Body @{
                RemoveMember = @(New-Member -Upn 'sseck@contoso.com' -Value 'user-guid')
            }

            $null = Invoke-EditGroup -Request $Request

            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly -ParameterFilter {
                $cmdletArray[0].CmdletInput.CmdletName -eq 'Remove-DistributionGroupMember' -and
                $cmdletArray[0].CmdletInput.Parameters.Member -eq 'sseck@contoso.com'
            }
        }

        It 'adds and removes in the same request' {
            $Request = New-GroupRequest -GroupType 'Security' -Body @{
                AddMember    = @(New-Member -Upn 'one@contoso.com' -Value 'user-1')
                RemoveMember = @(New-Member -Upn 'two@contoso.com' -Value 'user-2')
            }

            $null = Invoke-EditGroup -Request $Request

            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Requests.Count -eq 2 -and
                $Requests.method -contains 'PATCH' -and
                $Requests.method -contains 'DELETE'
            }
        }
    }

    Context 'Devices' {
        It 'refuses to add a device to a <GroupType> instead of sending a doomed request' -ForEach @(
            @{ GroupType = 'Distribution List' }
            @{ GroupType = 'Mail-Enabled Security' }
        ) {
            $Request = New-GroupRequest -GroupType $GroupType -Body @{
                AddDevice = @([pscustomobject]@{ label = 'LAPTOP-01'; value = 'device-guid' })
            }

            $Response = Invoke-EditGroup -Request $Request

            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
            $Response.Body.Results | Should -Contain "Error - Devices cannot be added to a $GroupType group"
        }

        It 'binds a device into a security group through Graph' {
            $Request = New-GroupRequest -GroupType 'Security' -Body @{
                AddDevice = @([pscustomobject]@{ label = 'LAPTOP-01'; value = 'device-guid' })
            }

            $null = Invoke-EditGroup -Request $Request

            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Requests[0].body.'members@odata.bind' -contains 'https://graph.microsoft.com/v1.0/directoryObjects/device-guid'
            }
        }
    }

    Context 'Owners' {
        It 'POSTs an owner reference for a security group' {
            $Request = New-GroupRequest -GroupType 'Security' -Body @{
                AddOwner = @(New-Member -Upn 'boss@contoso.com' -Value 'owner-guid')
            }

            $null = Invoke-EditGroup -Request $Request

            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Requests[0].method -eq 'POST' -and $Requests[0].url -like '*/owners/*'
            }
        }

        It 'rewrites ManagedBy wholesale when adding an owner to a distribution list' {
            # Exchange has no owners collection to append to.
            Mock -CommandName New-ExoRequest -MockWith { [pscustomobject]@{ ManagedBy = @('existing@contoso.com') } }
            $Request = New-GroupRequest -GroupType 'Distribution List' -Body @{
                AddOwner = @(New-Member -Upn 'boss@contoso.com' -Value 'boss@contoso.com')
            }

            $null = Invoke-EditGroup -Request $Request

            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Set = $cmdletArray | Where-Object { $_.CmdletInput.CmdletName -eq 'Set-DistributionGroup' }
                $Set -and
                $Set.CmdletInput.Parameters.ManagedBy -contains 'existing@contoso.com' -and
                $Set.CmdletInput.Parameters.ManagedBy -contains 'boss@contoso.com'
            }
        }

        It 'bypasses the security group manager check when rewriting ManagedBy' {
            # Without this the check applies to mail-enabled security groups and Exchange refuses
            # with "The executing user is not in the current organization", so the owner change
            # silently does nothing. Caught against a live tenant, not in review.
            Mock -CommandName New-ExoRequest -MockWith { [pscustomobject]@{ ManagedBy = @('existing@contoso.com') } }
            $Request = New-GroupRequest -GroupType 'Mail-Enabled Security' -Body @{
                AddOwner = @(New-Member -Upn 'boss@contoso.com' -Value 'boss@contoso.com')
            }

            $null = Invoke-EditGroup -Request $Request

            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Set = $cmdletArray | Where-Object { $_.CmdletInput.CmdletName -eq 'Set-DistributionGroup' }
                $Set -and $Set.CmdletInput.Parameters.BypassSecurityGroupManagerCheck -eq $true
            }
        }

        It 'drops a removed owner out of the rewritten ManagedBy list' {
            Mock -CommandName New-ExoRequest -MockWith { [pscustomobject]@{ ManagedBy = @('keep@contoso.com', 'drop@contoso.com') } }
            $Request = New-GroupRequest -GroupType 'Distribution List' -Body @{
                RemoveOwner = @(New-Member -Upn 'drop@contoso.com' -Value 'drop@contoso.com')
            }

            $null = Invoke-EditGroup -Request $Request

            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Set = $cmdletArray | Where-Object { $_.CmdletInput.CmdletName -eq 'Set-DistributionGroup' }
                $Set -and
                $Set.CmdletInput.Parameters.ManagedBy -contains 'keep@contoso.com' -and
                $Set.CmdletInput.Parameters.ManagedBy -notcontains 'drop@contoso.com'
            }
        }
    }

    Context 'Resolving the group type from the group itself' {
        # The posted type comes from an autocomplete option: absent on anything stored before
        # addedFields existed, and stale whenever a group was converted after the option was saved.
        # The endpoint already fetches the group, so that answer wins over what the form claimed.
        BeforeEach {
            # Only the group lookup returns flags; the member lookup keeps its own shape.
            Mock -CommandName New-GraphGetRequest -MockWith {
                [pscustomobject]@{ id = 'group-guid'; displayName = 'All Office'; groupTypes = @(); mailEnabled = $true; securityEnabled = $false }
            } -ParameterFilter { $uri -like '*/groups/*' }
        }

        It 'sends a classic distribution list to Exchange even when the form said Security' {
            $Request = New-GroupRequest -GroupType 'Security' -Body @{
                AddMember = @(New-Member -Upn 'sseck@contoso.com' -Value 'user-guid')
            }

            $null = Invoke-EditGroup -Request $Request

            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly -ParameterFilter {
                $cmdletArray[0].CmdletInput.CmdletName -eq 'Add-DistributionGroupMember'
            }
            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
        }

        It 'sends a removal from a mislabelled distribution list to Exchange too' {
            $Request = New-GroupRequest -GroupType 'Security' -Body @{
                RemoveMember = @(New-Member -Upn 'sseck@contoso.com' -Value 'user-guid')
            }

            $null = Invoke-EditGroup -Request $Request

            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly -ParameterFilter {
                $cmdletArray[0].CmdletInput.CmdletName -eq 'Remove-DistributionGroupMember'
            }
        }

        It 'routes a mail-enabled security group to Exchange when the form carried no type' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                [pscustomobject]@{ id = 'group-guid'; displayName = 'SG-LIC-M365'; groupTypes = @(); mailEnabled = $true; securityEnabled = $true }
            } -ParameterFilter { $uri -like '*/groups/*' }
            $Request = [pscustomobject]@{
                Body    = [pscustomobject]@{
                    tenantFilter = 'contoso.com'
                    groupName    = 'SG-LIC-M365'
                    groupId      = 'group-guid'
                    AddMember    = @(New-Member -Upn 'sseck@contoso.com' -Value 'user-guid')
                }
                Headers = @{}
                Params  = @{ CIPPEndpoint = 'EditGroup' }
            }

            $null = Invoke-EditGroup -Request $Request

            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly -ParameterFilter {
                $cmdletArray[0].CmdletInput.CmdletName -eq 'Add-DistributionGroupMember'
            }
        }

        It 'keeps a Microsoft 365 group on Graph even though it is mail-enabled' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                [pscustomobject]@{ id = 'group-guid'; displayName = 'IEQ - ALL'; groupTypes = @('Unified'); mailEnabled = $true; securityEnabled = $false }
            } -ParameterFilter { $uri -like '*/groups/*' }
            $Request = New-GroupRequest -GroupType 'Distribution List' -Body @{
                AddMember = @(New-Member -Upn 'sseck@contoso.com' -Value 'user-guid')
            }

            $null = Invoke-EditGroup -Request $Request

            Should -Invoke New-ExoBulkRequest -Times 0 -Exactly
            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { $Requests[0].method -eq 'PATCH' }
        }

        It 'keeps a plain security group on Graph when the form mislabelled it as a list' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                [pscustomobject]@{ id = 'group-guid'; displayName = 'All-Users'; groupTypes = @(); mailEnabled = $false; securityEnabled = $true }
            } -ParameterFilter { $uri -like '*/groups/*' }
            $Request = New-GroupRequest -GroupType 'Distribution List' -Body @{
                AddMember = @(New-Member -Upn 'sseck@contoso.com' -Value 'user-guid')
            }

            $null = Invoke-EditGroup -Request $Request

            Should -Invoke New-ExoBulkRequest -Times 0 -Exactly
            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly
        }

        It 'lets a device be added to a group the form wrongly called a distribution list' {
            # The refusal is correct for a real Exchange group and wrong for a security group,
            # so it has to follow the resolved type rather than the posted one.
            Mock -CommandName New-GraphGetRequest -MockWith {
                [pscustomobject]@{ id = 'group-guid'; displayName = 'All-Users'; groupTypes = @(); mailEnabled = $false; securityEnabled = $true }
            } -ParameterFilter { $uri -like '*/groups/*' }
            $Request = New-GroupRequest -GroupType 'Distribution List' -Body @{
                AddDevice = @([pscustomobject]@{ label = 'LAPTOP-01'; value = 'device-guid' })
            }

            $Response = Invoke-EditGroup -Request $Request

            $Response.Body.Results | Should -Not -Contain 'Error - Devices cannot be added to a Distribution List group'
            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                $Requests[0].body.'members@odata.bind' -contains 'https://graph.microsoft.com/v1.0/directoryObjects/device-guid'
            }
        }

        It 'still refuses a device on a group that really is a distribution list' {
            $Request = New-GroupRequest -GroupType 'Security' -Body @{
                AddDevice = @([pscustomobject]@{ label = 'LAPTOP-01'; value = 'device-guid' })
            }

            $Response = Invoke-EditGroup -Request $Request

            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
            $Response.Body.Results | Should -Contain 'Error - Devices cannot be added to a Distribution List group'
        }
    }

    Context 'Where the group type comes from' {
        It 'falls back to the top-level groupType when the option carries none' {
            # The Add to Group user action posts the type beside the group rather than inside it.
            $Request = [pscustomobject]@{
                Body    = [pscustomobject]@{
                    tenantFilter = 'contoso.com'
                    groupName    = 'All Office'
                    groupId      = 'group-guid'
                    groupType    = 'Distribution List'
                    AddMember    = @(New-Member -Upn 'sseck@contoso.com' -Value 'user-guid')
                }
                Headers = @{}
                Params  = @{ CIPPEndpoint = 'EditGroup' }
            }

            $null = Invoke-EditGroup -Request $Request

            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly -ParameterFilter {
                $cmdletArray[0].CmdletInput.CmdletName -eq 'Add-DistributionGroupMember'
            }
        }

        It 'matches the group type regardless of casing' {
            # /api/ListGroups emits 'Distribution List'; other callers use 'Distribution list'.
            $Request = New-GroupRequest -GroupType 'Distribution list' -Body @{
                AddMember = @(New-Member -Upn 'sseck@contoso.com' -Value 'user-guid')
            }

            $null = Invoke-EditGroup -Request $Request

            Should -Invoke New-ExoBulkRequest -Times 1 -Exactly
        }
    }
}
