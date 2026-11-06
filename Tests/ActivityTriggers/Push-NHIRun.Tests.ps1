BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:OriginalRoot = $env:CIPPRootPath
    # The shipped heuristics are read through $env:CIPPRootPath.
    $env:CIPPRootPath = $RepoRoot

    # Platform helpers the run calls; each is a stub so Mock has something to replace.
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, $SliceHours, [switch]$Stream) }
    function New-GraphBulkRequest { param($Requests, $tenantid, $asapp, $Version) }
    function Get-Tenants { param($TenantFilter) }
    function Get-CIPPTenantCapabilities { param($TenantFilter) }
    function Get-CIPPGeoIPLocationBatch { param([string[]]$IPs) }
    function Get-CIPPBecIPGuidance { param($TenantFilter, $Anchor) }
    function Get-CIPPBecRogueAppFeed { }
    function Get-CIPPVendorTenantMap { @{} }
    function Get-CIPPAppPermissionExposure { param($TenantFilter, [switch]$Live, $ServicePrincipalId, [switch]$IncludeUncatalogued) }
    function Search-CIPPBecSignIn { param($TenantFilter, $Filter, $StartDate, $EndDate, $Select, $AsApp, $SliceHours, [switch]$Stream) }
    function Search-CIPPBecAuditLog { param($TenantFilter, $StartDate, $EndDate, $Operations, $FreeText, $MaxPages) }
    function Resolve-CIPPIPAllowBlockList { param($IPAddress, $Entries) }
    function Test-IpInRange { param($IPAddress, $Range) $false }
    function Write-LogMessage { param($message, $tenant, $API, $headers, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = [string]$Exception.Exception.Message } }
    function Get-NormalizedError { param($message) $message }
    function Set-CippBecCaseContext { param($CaseId) }
    function Set-CIPPBecReport { param($TenantFilter, $CaseId, $Properties, $Results, [switch]$Replace, $Kind) }
    function Get-CIPPAsyncDeployment { param($JobId) }
    function New-CIPPAsyncDeployment { param($JobId, $Names, $StepTitles, $Source, $TenantFilter) $JobId }
    function Set-CIPPAsyncDeploymentStatus { param($JobId, $Name, $Status, $Logs) }
    function Set-CIPPAsyncDeploymentStep { param($JobId, $Name, $StepIndex, $StepStatus, $Message) }
    # The run state table, in memory; the real Get-/Set-CIPPBecRunState run over it.
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force, $OperationType) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property, $First) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }

    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    foreach ($File in 'AppPermissions/Get-CIPPRiskyPermissionCatalog.ps1', 'AppPermissions/ConvertFrom-CIPPGrantAuditEvent.ps1', 'AppPermissions/ConvertFrom-CIPPRoleAuditEvent.ps1', 'BEC/ConvertTo-CIPPBecHostAddress.ps1', 'BEC/New-CIPPBecCollectorResult.ps1', 'BEC/Get-CIPPBecRunState.ps1', 'BEC/Set-CIPPBecRunState.ps1', 'NHI/Get-CIPPNhiRunSteps.ps1', 'NHI/Get-CIPPNhiIPVerdicts.ps1', 'NHI/Get-CIPPNhiScore.ps1') {
        . (Join-Path $RepoRoot "Modules/CIPPCore/Public/$File")
    }
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Push-NHIRun.ps1' | Select-Object -First 1).FullName

    # a run is one job per phase, queued in order
    function Invoke-NhiRun { param($Item) foreach ($RunStep in @(Get-CIPPNhiRunSteps)) { Push-NHIRun -Item ($Item + @{ Step = $RunStep.Key }) } }
    $script:Item = @{ TenantFilter = 'contoso.com'; ServicePrincipalId = 'sp-1'; SubjectName = 'Invoice Sync'; CaseId = 'NHI-20261105120000-test01' }
    $script:Day = { param($Offset) [datetime]::UtcNow.AddDays($Offset).ToString('o') }
}

AfterAll {
    $env:CIPPRootPath = $script:OriginalRoot
}

Describe 'Push-NHIRun' {
    BeforeEach {
        $script:Saved = $null
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        Mock Set-CIPPBecReport { $script:Writes.Add(@{ Kind = $Kind; Properties = $Properties }); $script:Saved = @{ Kind = $Kind; Properties = $Properties; Results = $Results } }
        $script:StepCalls = [System.Collections.Generic.List[object]]::new()
        Mock Set-CIPPAsyncDeploymentStep { $script:StepCalls.Add(@{ Index = $StepIndex; Status = $StepStatus; Message = $Message }) }
        Mock Set-CIPPAsyncDeploymentStatus { }
        Mock Get-CIPPAsyncDeployment { @() }
        Mock Write-LogMessage { }
        $script:StateRows = [System.Collections.Generic.List[object]]::new()
        Mock Add-CIPPAzDataTableEntity {
            foreach ($Old in @($script:StateRows | Where-Object { $_.PartitionKey -eq $Entity.PartitionKey -and $_.RowKey -eq $Entity.RowKey })) { $null = $script:StateRows.Remove($Old) }
            $script:StateRows.Add([pscustomobject]$Entity)
        }
        Mock Get-CIPPAzDataTableEntity { $PK = [regex]::Match($Filter, "PartitionKey eq '([^']*)'").Groups[1].Value; @($script:StateRows | Where-Object { $_.PartitionKey -eq $PK }) }
        Mock Remove-CIPPAzDataTableEntity { foreach ($Old in @($Entity)) { foreach ($Row in @($script:StateRows | Where-Object { $_.PartitionKey -eq $Old.PartitionKey -and $_.RowKey -eq $Old.RowKey })) { $null = $script:StateRows.Remove($Row) } } }

        Mock Get-Tenants { [pscustomobject]@{ customerId = 'tenant-guid' } }
        Mock Get-CIPPTenantCapabilities { [pscustomobject]@{ AAD_PREMIUM = $true } }
        Mock Get-CIPPBecRogueAppFeed { @{ Apps = @{} } }
        Mock Get-CIPPBecIPGuidance { [pscustomobject]@{ Data = @(); Complete = $true; Count = 0 } }
        Mock Get-CIPPGeoIPLocationBatch { @{ '20.50.1.10' = [pscustomobject]@{ Hosting = $true; Proxy = $false; ASName = 'Microsoft' }; '198.51.100.7' = [pscustomobject]@{ Hosting = $true; Proxy = $false; ASName = 'M247'; CountryOrRegion = 'RO' } } }
        Mock New-GraphGetRequest {
            if ($uri -like '*/servicePrincipals/sp-1?*') {
                return [pscustomobject]@{ id = 'sp-1'; appId = 'app-1'; displayName = 'Invoice Sync'; servicePrincipalType = 'Application'; accountEnabled = $true; appOwnerOrganizationId = 'tenant-guid'; createdDateTime = (& $script:Day -400) }
            }
            if ($uri -like '*targetResources/any*sp-1*') {
                return @(
                    [pscustomobject]@{ id = 'c1'; activityDateTime = (& $script:Day -2); activityDisplayName = 'Add service principal credentials'; result = 'success'; initiatedBy = [pscustomobject]@{ app = [pscustomobject]@{ appId = 'app-rogue'; displayName = 'Rogue Tool'; servicePrincipalId = '11111111-1111-1111-1111-111111111111' } }; targetResources = @([pscustomobject]@{ id = 'sp-1'; modifiedProperties = @([pscustomobject]@{ displayName = 'KeyDescription' }) }) }
                    [pscustomobject]@{ id = 'c2'; activityDateTime = (& $script:Day -20); activityDisplayName = 'Update service principal'; result = 'success'; initiatedBy = [pscustomobject]@{ user = [pscustomobject]@{ userPrincipalName = 'admin@contoso.com'; id = 'u1'; ipAddress = '192.0.2.1' } }; targetResources = @([pscustomobject]@{ id = 'sp-1'; modifiedProperties = @([pscustomobject]@{ displayName = 'Tags' }) }) }
                )
            }
            if ($uri -like '*targetResources/any*reg-1*') {
                return @([pscustomobject]@{ id = 'c3'; activityDateTime = (& $script:Day -1); activityDisplayName = 'Update application'; result = 'success'; initiatedBy = [pscustomobject]@{ user = [pscustomobject]@{ userPrincipalName = 'intruder@contoso.com'; id = 'u2'; ipAddress = '198.51.100.7' } }; targetResources = @([pscustomobject]@{ id = 'reg-1'; modifiedProperties = @([pscustomobject]@{ displayName = 'AppAddress'; newValue = '["https://x.ngrok-free.app"]' }) }) })
            }
            if ($uri -like '*initiatedBy/app/appId*') {
                return @(
                    [pscustomobject]@{ activityDateTime = (& $script:Day -1); activityDisplayName = 'Add service principal credentials'; category = 'ApplicationManagement'; result = 'success'; targetResources = @([pscustomobject]@{ type = 'ServicePrincipal'; id = '22222222-2222-2222-2222-222222222222'; displayName = 'Payroll Connector' }) }
                    [pscustomobject]@{ activityDateTime = (& $script:Day -1); activityDisplayName = 'Add service principal credentials'; category = 'ApplicationManagement'; result = 'success'; targetResources = @([pscustomobject]@{ type = 'ServicePrincipal'; id = 'sp-1'; displayName = 'Invoice Sync' }) }
                    [pscustomobject]@{ activityDateTime = (& $script:Day -1); activityDisplayName = 'Add application'; category = 'ApplicationManagement'; result = 'success'; targetResources = @([pscustomobject]@{ type = 'Application'; id = '33333333-3333-3333-3333-333333333333'; displayName = 'Teams Sync' }) }
                    [pscustomobject]@{ activityDateTime = (& $script:Day -1); activityDisplayName = 'Update user'; category = 'UserManagement'; result = 'success'; targetResources = @([pscustomobject]@{ type = 'User'; id = 'u9'; userPrincipalName = 'ceo@contoso.com' }) }
                    # elevation: Graph Mail.ReadWrite to another app and to itself, a delegated grant to itself, Global Administrator to a user
                    [pscustomobject]@{ activityDateTime = (& $script:Day -1); activityDisplayName = 'Add app role assignment to service principal'; category = 'ApplicationManagement'; result = 'success'; targetResources = @([pscustomobject]@{ type = 'ServicePrincipal'; id = 'res-graph'; displayName = 'Microsoft Graph'; modifiedProperties = @([pscustomobject]@{ displayName = 'AppRole.Id'; newValue = '"e2a3a72e-5f79-4c64-b1b1-878b674786c9"' }, [pscustomobject]@{ displayName = 'AppRole.Value'; newValue = '"Mail.ReadWrite"' }, [pscustomobject]@{ displayName = 'ServicePrincipal.ObjectID'; newValue = '"22222222-2222-2222-2222-222222222222"' }, [pscustomobject]@{ displayName = 'ServicePrincipal.DisplayName'; newValue = '"Payroll Connector"' }) }) }
                    [pscustomobject]@{ activityDateTime = (& $script:Day -1); activityDisplayName = 'Add app role assignment to service principal'; category = 'ApplicationManagement'; result = 'success'; targetResources = @([pscustomobject]@{ type = 'ServicePrincipal'; id = 'res-graph'; displayName = 'Microsoft Graph'; modifiedProperties = @([pscustomobject]@{ displayName = 'AppRole.Id'; newValue = '"e2a3a72e-5f79-4c64-b1b1-878b674786c9"' }, [pscustomobject]@{ displayName = 'AppRole.Value'; newValue = '"Mail.ReadWrite"' }, [pscustomobject]@{ displayName = 'ServicePrincipal.ObjectID'; newValue = '"sp-1"' }) }) }
                    [pscustomobject]@{ activityDateTime = (& $script:Day -1); activityDisplayName = 'Add delegated permission grant'; category = 'ApplicationManagement'; result = 'success'; targetResources = @([pscustomobject]@{ type = 'ServicePrincipal'; id = 'res-graph'; displayName = 'Microsoft Graph'; modifiedProperties = @([pscustomobject]@{ displayName = 'ServicePrincipal.ObjectID'; newValue = '"sp-1"' }, [pscustomobject]@{ displayName = 'DelegatedPermissionGrant.Scope'; newValue = '"Mail.ReadWrite"' }, [pscustomobject]@{ displayName = 'DelegatedPermissionGrant.ConsentType'; newValue = '"AllPrincipals"' }) }) }
                    [pscustomobject]@{ activityDateTime = (& $script:Day -1); activityDisplayName = 'Add member to role'; category = 'RoleManagement'; result = 'success'; targetResources = @([pscustomobject]@{ type = 'User'; id = 'u-helpdesk'; userPrincipalName = 'helpdesk@contoso.com'; modifiedProperties = @([pscustomobject]@{ displayName = 'Role.TemplateId'; newValue = '"62e90394-69f5-4237-9190-012177145e10"' }, [pscustomobject]@{ displayName = 'Role.DisplayName'; newValue = '"Global Administrator"' }) }) }
                )
            }
            @()
        }
        Mock New-GraphBulkRequest {
            foreach ($Request in $Requests) {
                $Body = switch ($Request.id) {
                    'Owners' { @{ value = @([pscustomobject]@{ id = 'u1'; displayName = 'Admin'; userPrincipalName = 'admin@contoso.com' }) } }
                    'AppRoles' { @{ value = @([pscustomobject]@{ id = 'ara-1'; resourceId = 'res-graph'; resourceDisplayName = 'Microsoft Graph'; appRoleId = 'role-mail'; createdDateTime = (& $script:Day -3) }) } }
                    'Grants' { @{ value = @() } }
                    'Roles' { @{ value = @() } }
                    'App' { [pscustomobject]@{ id = 'reg-1'; appId = 'app-1'; signInAudience = 'AzureADMyOrg'; owners = @() } }
                    'res-graph' { [pscustomobject]@{ id = 'res-graph'; appRoles = @([pscustomobject]@{ id = 'role-mail'; value = 'Mail.Read' }) } }
                    # the persistence targets: an existing app (by service principal) and a new registration (by appId)
                    '22222222-2222-2222-2222-222222222222' { [pscustomobject]@{ id = '22222222-2222-2222-2222-222222222222'; appId = 'app-payroll'; displayName = 'Payroll Connector'; appOwnerOrganizationId = 'tenant-guid' } }
                    '33333333-3333-3333-3333-333333333333' {
                        if ($Request.url -like 'applications/*') { [pscustomobject]@{ id = '33333333-3333-3333-3333-333333333333'; appId = 'app-backdoor' } }
                        else { [pscustomobject]@{ id = 'sp-backdoor'; appId = 'app-backdoor'; displayName = 'Teams Sync'; appOwnerOrganizationId = 'tenant-guid' } }
                    }
                    default { @{ value = @() } }
                }
                $Status = if ($Request.id -in 'Risk', 'Detections') { 403 } else { 200 }
                if ($Status -eq 403) { $Body = @{ error = @{ message = 'Your tenant is not licensed for this feature.' } } }
                [pscustomobject]@{ id = $Request.id; status = $Status; body = $Body }
            }
        }
        Mock Get-CIPPAppPermissionExposure {
            [pscustomobject]@{
                Ownership = 'This tenant'; Risk = 'High'; HighestImpact = 'Critical'; IsMicrosoftApp = $false; IsCippApp = $false; ServicePrincipalCredentialCount = 1
                CredentialDetails = @(
                    [pscustomobject]@{ Location = 'App registration'; Type = 'Certificate'; Purpose = 'Sign-in'; Expired = $false; KeyId = 'key-old'; AddedDateTime = (& $script:Day -300); Flags = @() }
                    [pscustomobject]@{ Location = 'Enterprise app'; Type = 'Secret'; Purpose = 'Sign-in'; Expired = $false; KeyId = 'key-new'; AddedDateTime = (& $script:Day -2); AddedByType = 'Application'; Flags = @('AddedByApp', 'AddedRecently') }
                    [pscustomobject]@{ Location = 'App registration'; Type = 'Secret'; Purpose = 'Sign-in'; Expired = $false; KeyId = 'key-rotated'; AddedDateTime = (& $script:Day -3); AddedByType = 'User'; Flags = @('AddedRecently', 'Rotation') }
                )
            }
        }
        # the app's own host every day with its certificate; in the window also a new network with the new secret
        Mock Search-CIPPBecSignIn {
            $Row = { param($IP, $Key, $Type, $Asn, $Offset) [pscustomobject]@{ createdDateTime = (& $script:Day $Offset); ipAddress = $IP; autonomousSystemNumber = $Asn; location = [pscustomobject]@{ countryOrRegion = if ($Asn -eq '8075') { 'NL' } else { 'RO' } }; resourceDisplayName = 'Microsoft Graph'; status = [pscustomobject]@{ errorCode = 0 }; servicePrincipalCredentialKeyId = $Key; clientCredentialType = $Type } }
            if ($Filter -like 'appId eq*') { return }
            if ($StartDate -lt [datetime]::UtcNow.AddDays(-8)) {
                foreach ($Offset in -29..-8) { & $Row '20.50.1.10' 'key-old' 'certificate' '8075' $Offset }
            } else {
                foreach ($Offset in -6..-1) { & $Row '20.50.1.10' 'key-old' 'certificate' '8075' $Offset }
                foreach ($Offset in 1..4) { & $Row '198.51.100.7' 'key-new' 'clientSecret' '9009' -1 }
            }
        }
        # thirty mailboxes read from the new address, and a record that only mentions the app id; nothing before the window
        Mock Search-CIPPBecAuditLog {
            if ($StartDate -lt [datetime]::UtcNow.AddDays(-8)) { return [pscustomobject]@{ Records = @(); Complete = $true; Cap = $null } }
            $Records = @(foreach ($n in 1..30) { [pscustomobject]@{ Operation = 'MailItemsAccessed'; AuditData = [pscustomobject]@{ AppId = 'app-1'; MailboxOwnerUPN = "user$n@contoso.com"; OperationCount = 5; ClientIPAddress = '198.51.100.7'; CreationTime = (& $script:Day -1) } } })
            $Records += [pscustomobject]@{ Operation = 'FileAccessed'; AuditData = [pscustomobject]@{ ApplicationId = 'other-app'; ObjectId = 'https://x/doc-mentioning-app-1'; ClientIP = '203.0.113.1' } }
            $Records += [pscustomobject]@{ Operation = 'Send'; AuditData = [pscustomobject]@{ AppId = 'app-1'; MailboxOwnerUPN = 'user1@contoso.com'; ClientIPAddress = '198.51.100.7'; CreationTime = (& $script:Day -1) } }
            $Records += [pscustomobject]@{ Operation = 'AnonymousLinkCreated'; AuditData = [pscustomobject]@{ ApplicationId = 'app-1'; ObjectId = 'https://contoso.sharepoint.com/sites/hr/doc.docx'; SiteUrl = 'https://contoso.sharepoint.com/sites/hr'; ClientIP = '198.51.100.7' } }
            [pscustomobject]@{ Records = $Records; Complete = $true; Cap = $null }
        }
    }

    It 'investigates the app end to end and rates a flagged credential used from a new network as a critical case' {
        Invoke-NhiRun -Item $script:Item

        $script:Saved.Kind | Should -BeExactly 'NHI'
        $script:Saved.Properties.Status | Should -BeExactly 'Completed'
        $Results = $script:Saved.Results
        $Applied = @($Results.Score.Breakdown | Where-Object Applied).Signal
        $Applied | Should -Contain 'CredentialAdded'
        $Applied | Should -Contain 'CredentialAddedByApp'
        $Applied | Should -Contain 'RedirectUriChanged'
        $Applied | Should -Contain 'AttackerIPs'
        $Applied | Should -Contain 'FlaggedCredentialUsed'
        $Applied | Should -Contain 'LateralCredentialAdds'
        $Applied | Should -Contain 'MassMailboxAccess'
        $Applied | Should -Contain 'AttackerWorkload' -Because 'the attacker address signed in with the flagged credential'
        $Results.Score.Level | Should -BeExactly 'Critical'
        $script:Saved.Properties.Level | Should -BeExactly 'Critical'

        ($Results.IPVerdicts | Where-Object IP -EQ '198.51.100.7').Verdict | Should -BeExactly 'LikelyAttacker'
        ($Results.IPVerdicts | Where-Object IP -EQ '20.50.1.10').Verdict | Should -BeExactly 'Expected'
        $Results.FlaggedKeyIds | Should -Be @('key-new') -Because 'a rotation added in the window is the app''s own new credential'
        $Results.WorkloadBaseline.Mailboxes.Count | Should -Be 0
        $Results.AppRoleAssignments[0].Permission | Should -BeExactly 'Mail.Read'
        $Results.AppRoleAssignments[0].InWindow | Should -BeTrue
        $Results.WorkloadSummary.MailboxCount | Should -Be 30 -Because 'a record that only mentions the app id is not the app''s'
        $Results.WorkloadSummary.MailItemCount | Should -Be 150
        $Results.WorkloadSummary.SendCount | Should -Be 1
        $Results.WorkloadSummary.AnonymousLinkCount | Should -Be 1
        $Applied | Should -Contain 'NewMailSending'
        $Applied | Should -Contain 'NewAnonymousLinks'
        @($Results.DirectoryActions | Where-Object Lateral).Count | Should -Be 1 -Because 'a credential on its own service principal is the app rotating itself'
        @($Results.DirectoryActions | Where-Object Kind -EQ 'AppPersistence').Count | Should -Be 2 -Because 'the app created one app and added a credential to another'
        ($Results.DirectoryActions | Where-Object Activity -EQ 'Update user').Kind | Should -BeExactly 'Directory'
        ($Results.DirectoryActions | Where-Object Activity -EQ 'Add application').TargetServicePrincipalId | Should -BeExactly 'sp-backdoor' -Because 'a new registration resolves to its service principal through its appId'
        ($Results.DirectoryActions | Where-Object Lateral).TargetServicePrincipalId | Should -BeExactly '22222222-2222-2222-2222-222222222222'
        ($Results.DirectoryActions | Where-Object Lateral).TargetProtected | Should -BeFalse
        $Elevation = @($Results.DirectoryActions | Where-Object Kind -EQ 'Elevation')
        $Elevation.Count | Should -Be 4
        ($Elevation | Where-Object { $_.Recipient -eq 'App' }).RecipientId | Should -BeExactly '22222222-2222-2222-2222-222222222222'
        ($Elevation | Where-Object { $_.Recipient -eq 'App' }).Impact | Should -BeExactly 'Critical'
        ($Elevation | Where-Object { $_.Recipient -eq 'User' }).Permission | Should -BeExactly 'Global Administrator'
        ($Elevation | Where-Object { $_.ElevationType -eq 'Delegated permission' }).Impact | Should -BeExactly 'Medium'
        ($Elevation | Where-Object { $_.ElevationType -eq 'Delegated permission' }).Recipient | Should -BeExactly 'Self'
        foreach ($Signal in 'SelfElevation', 'AppElevation', 'UserElevation', 'ElevationChain') { $Applied | Should -Contain $Signal }
        ($Results.Score.Breakdown | Where-Object Signal -EQ 'SelfElevation').Count | Should -Be 1 -Because 'the medium-impact delegated grant is listed, not scored'
        $Applied | Should -Contain 'AppsCreated'
        $Applied | Should -Contain 'FlaggedDirectoryActions'
        ($Results.Score.Breakdown | Where-Object Signal -EQ 'FlaggedDirectoryActions').Count | Should -Be 1 -Because 'app persistence is not counted again as a directory change'
        ($Results.DirectoryActions | Where-Object { $_.Targets[0].Id -eq 'sp-1' }).Severity | Should -BeExactly 'Info'
        ($Results.Changes | Where-Object Kind -EQ 'Credential').ByApp | Should -BeTrue
        $Results.Baseline.Total | Should -Be 22
        @($Results.RecentSignIns | Where-Object IPVerdict -EQ 'LikelyAttacker').Count | Should -Be 4
    }

    It 'marks Identity Protection skipped, not failed, when the tenant has no Workload ID Premium' {
        Invoke-NhiRun -Item $script:Item

        $Marker = $script:Saved.Results.Completeness.SubjectRisk
        $Marker.Skipped | Should -BeTrue
        $Marker.Requirement | Should -BeExactly 'requires Microsoft Entra Workload ID Premium'
        $script:Saved.Results.Completeness.SubjectOwners.Complete | Should -BeTrue
    }

    It 'skips the sign-in phases without Entra ID P1 and still scores the case on what it could read' {
        Mock Get-CIPPTenantCapabilities { [pscustomobject]@{ AAD_PREMIUM = $false; AAD_PREMIUM_P2 = $false } }

        Invoke-NhiRun -Item $script:Item

        $Results = $script:Saved.Results
        $script:Saved.Properties.Status | Should -BeExactly 'Completed'
        $Results.Completeness.SignIns.Skipped | Should -BeTrue
        $Results.Completeness.Baseline.Skipped | Should -BeTrue
        $Results.Dormant | Should -BeFalse -Because 'a baseline that was never read says nothing about dormancy'
        Should -Invoke Search-CIPPBecSignIn -Times 0
        @($Results.Score.Breakdown | Where-Object Applied).Signal | Should -Contain 'LateralCredentialAdds'
    }

    It 'rates an app that had no sign-ins before the window as woken up' {
        Mock Search-CIPPBecSignIn {
            if ($Filter -like 'appId eq*' -or $StartDate -lt [datetime]::UtcNow.AddDays(-8)) { return }
            [pscustomobject]@{ createdDateTime = (& $script:Day -1); ipAddress = '20.50.1.10'; status = [pscustomobject]@{ errorCode = 0 }; servicePrincipalCredentialKeyId = 'key-old' }
        }

        Invoke-NhiRun -Item $script:Item

        $script:Saved.Results.Dormant | Should -BeTrue
        @($script:Saved.Results.Score.Breakdown | Where-Object Applied).Signal | Should -Contain 'DormantAwakened'
    }

    It 'fails the case when the app cannot be read, and the later phases do nothing' {
        Mock New-GraphGetRequest { throw 'Resource ''sp-1'' does not exist' } -ParameterFilter { $uri -like '*/servicePrincipals/sp-1?*' }

        Invoke-NhiRun -Item $script:Item

        $script:Saved.Properties.Status | Should -BeExactly 'Error'
        $script:Saved.Properties.ErrorMessage | Should -BeLike '*does not exist*'
        @($script:Writes | Where-Object { $_.Properties.Status -eq 'Completed' }).Count | Should -Be 0
        $script:StateRows.Count | Should -Be 0
    }

    It 'records a failed middle phase as an incomplete check and still completes the case' {
        Mock Search-CIPPBecAuditLog { throw 'Unified audit log search failed' }

        Invoke-NhiRun -Item $script:Item

        $script:Saved.Properties.Status | Should -BeExactly 'Completed'
        $script:Saved.Results.Completeness.WorkloadActivity.Complete | Should -BeFalse
        $script:Saved.Results.Completeness.WorkloadActivity.Error | Should -BeLike '*audit log search failed*'
        $script:Saved.Properties.IncompleteCount | Should -BeGreaterThan 0
    }
}
