function Push-NHIRun {
    <#
        .FUNCTIONALITY
        Entrypoint
        .SYNOPSIS
        Runs one phase of the non-human identity (NHI) compromise check for one service principal.
        .DESCRIPTION
        The BEC check, for an app or managed identity. Queued by New-CIPPNhiRunRequest as one sequential
        orchestration per investigation: one job per phase of Get-CIPPNhiRunSteps ($Item.Step), run in order on
        one worker, each within its own activity timeout. A phase hands what it collected to the later phases
        through the BecRunState table (keyed on the case id); a phase that fails is recorded as a failed step and
        an incomplete check, and the phases after it still run. The last phase judges every address, scores the
        run against the app's exposure and writes it to the NhiReports (metadata) and NhiResults (payload) tables.

        The window is the last window.days (7) days and the baseline the baseline.days (23) before it: together
        the 30 days Entra keeps sign-in logs for with Entra ID P1. Without P1 the sign-in phases are skipped and
        the case rests on the app's configuration, its changes and its activity. Metadata only - no message
        bodies or file contents.
    #>
    param($Item)

    $TenantFilter = $Item.TenantFilter
    $ServicePrincipalId = [string]$Item.ServicePrincipalId
    $CaseId = [string]$Item.CaseId
    $RunSteps = @(Get-CIPPNhiRunSteps)
    $StepIndex = [array]::IndexOf(@($RunSteps.Key), [string]$Item.Step)

    if (!$TenantFilter -or !$ServicePrincipalId -or !$CaseId -or $StepIndex -lt 0) {
        Write-Information 'NHI: No service principal, tenant, case or phase specified'
        return
    }
    $Key = $RunSteps[$StepIndex].Key
    $IsFirst = $StepIndex -eq 0
    $IsLast = $StepIndex -eq $RunSteps.Count - 1
    $Heuristics = [System.IO.File]::ReadAllText((Join-Path $env:CIPPRootPath 'Config/NhiHeuristics.json')) | ConvertFrom-Json

    if ($IsFirst) {
        $Name = if ([string]::IsNullOrWhiteSpace([string]$Item.SubjectName)) { $ServicePrincipalId } else { [string]$Item.SubjectName }
        $WindowDays = [int]($Heuristics.window.days ?? 7)
        $BaselineDays = [int]($Heuristics.baseline.days ?? 23)
        $endDate = (Get-Date).ToUniversalTime()
        $startDate = $endDate.AddDays(-$WindowDays)
        $baselineStart = $startDate.AddDays(-$BaselineDays)
        # a retry of the first phase starts clean, never on a dead attempt's state
        Set-CIPPBecRunState -CaseId $CaseId -Clear
        Set-CIPPBecRunState -CaseId $CaseId -Section '00-Run' -Values @{ SubjectName = $Name; StartDate = $startDate.ToString('o'); EndDate = $endDate.ToString('o'); BaselineStart = $baselineStart.ToString('o'); WindowDays = $WindowDays; BaselineDays = $BaselineDays }
        $State = @{ Completeness = [ordered]@{} }
    } else {
        # Only what this phase reads is built (Score reads everything); Push-NHIRun.Tests checks the lists against each phase
        $StateNames = @('SubjectName', 'WindowDays', 'BaselineDays', 'StartDate', 'EndDate', 'BaselineStart', 'Subject')
        $State = if ($Key -eq 'Score') { Get-CIPPBecRunState -CaseId $CaseId } else { Get-CIPPBecRunState -CaseId $CaseId -Name $StateNames }
        if ([string]::IsNullOrWhiteSpace([string]$State.SubjectName)) {
            Write-Information "NHI: case $CaseId has no run state; skipping phase $Key"
            return
        }
        $Name = [string]$State.SubjectName
        $WindowDays = [int]$State.WindowDays
        $BaselineDays = [int]$State.BaselineDays
        $startDate = ([datetime]$State.StartDate).ToUniversalTime()
        $endDate = ([datetime]$State.EndDate).ToUniversalTime()
        $baselineStart = ([datetime]$State.BaselineStart).ToUniversalTime()
    }
    $Subject = $State.Subject

    Set-CippBecCaseContext -CaseId $CaseId
    Write-Information "Working on $Name (case $CaseId, phase $Key)"

    # Progress writes are best-effort - a failure to report never fails the phase. The progress row is keyed on the
    # service principal id: an app's display name can hold characters a table key cannot (/ \ # ?).
    $Step = {
        param($Index, $Status, $Message)
        try { Set-CIPPAsyncDeploymentStep -JobId $CaseId -Name $ServicePrincipalId -StepIndex $Index -StepStatus $Status -Message ([string]$Message) } catch { Write-Information "NHI: progress update failed for $CaseId`: $($_.Exception.Message)" }
    }
    # Every array read from the state goes through here: a phase that failed left the value unset, and @($null) is one row.
    $Rows = { param($Field) , @(@($State[$Field]).Where({ $_ })) }
    $Completeness = [ordered]@{}
    $Mark = {
        param($Marker, $Result)
        $Completeness[$Marker] = [pscustomobject]@{
            Complete    = [bool]$Result.Complete
            Cap         = $Result.Cap
            Error       = $Result.Error
            Skipped     = [bool]$Result.Skipped
            Requirement = $Result.Requirement
            Count       = [int]$Result.Count
        }
    }
    $Collect = {
        param($Collector, [scriptblock]$Body)
        Write-Information "NHI: $Collector started"
        $CollectorTimer = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            & $Body
            Write-Information "NHI: $Collector finished in $([int]$CollectorTimer.Elapsed.TotalSeconds)s"
        } catch {
            $CollectorError = Get-CippException -Exception $_
            Write-LogMessage -API 'NHIRun' -message "NHI collector $Collector failed for $($Name): $($CollectorError.NormalizedError)" -tenant $TenantFilter -sev Warning -LogData $CollectorError
            # a missing licence is a check that could not run, not a failure
            $Unlicensed = $CollectorError.NormalizedError -match '(?i)(licen[cs]e|premium|sku|not (have|be) (an? )?(valid|required))'
            New-CIPPBecCollectorResult -Data @() -Error $(if (-not $Unlicensed) { $CollectorError.NormalizedError }) -Skipped $Unlicensed -Requirement $(if ($Unlicensed) { $CollectorError.NormalizedError })
        }
    }
    $Save = {
        param([hashtable]$Values)
        $Values.Completeness = $Completeness
        Set-CIPPBecRunState -CaseId $CaseId -Section ('{0:D2}-{1}' -f ($StepIndex + 1), $Key) -Values $Values
    }
    # Sign-in logs through the API need Entra ID P1: without it the sign-in phases are skipped, not failed.
    $HasP1 = {
        $Capabilities = try { Get-CIPPTenantCapabilities -TenantFilter $TenantFilter } catch { $null }
        (-not $Capabilities) -or $Capabilities.AAD_PREMIUM -eq $true -or $Capabilities.AAD_PREMIUM_P2 -eq $true
    }
    # Folds a stream of the app's sign-ins into per-address, per-credential and overall counts: a busy daemon signs
    # in tens of thousands of times a week, so no raw rows are kept but the newest few for the timeline.
    $Fold = {
        param([scriptblock]$Source, [int]$Keep)
        $Cap = [int]($Heuristics.caps.signInRows ?? 100000)
        $Comparer = [System.StringComparer]::OrdinalIgnoreCase
        $Agg = @{ Total = 0; Success = 0; Failed = 0; First = $null; Last = $null }
        $ByIP = [System.Collections.Generic.Dictionary[string, object]]::new($Comparer)
        $ByKey = [System.Collections.Generic.Dictionary[string, object]]::new($Comparer)
        $Counts = @{ ASNs = @{}; Countries = @{}; Resources = @{}; CredentialTypes = @{}; AttachedResources = @{} }
        $Days = [System.Collections.Generic.HashSet[string]]::new()
        $Recent = [System.Collections.Generic.List[object]]::new()
        $HostOf = @{}
        & $Source | Select-Object -First $Cap | ForEach-Object {
            $Row = $_
            $Agg.Total++
            $Ok = [int]$Row.status.errorCode -eq 0
            if ($Ok) { $Agg.Success++ } else { $Agg.Failed++ }
            $When = if ($Row.createdDateTime) { ([datetime]$Row.createdDateTime).ToUniversalTime() } else { $null }
            if ($When) {
                if (-not $Agg.First -or $When -lt $Agg.First) { $Agg.First = $When }
                if (-not $Agg.Last -or $When -gt $Agg.Last) { $Agg.Last = $When }
                $null = $Days.Add($When.ToString('yyyy-MM-dd'))
            }
            $Raw = [string]$Row.ipAddress
            if (-not $HostOf.ContainsKey($Raw)) { $HostOf[$Raw] = [string](ConvertTo-CIPPBecHostAddress -Address $Raw) }
            $IP = $HostOf[$Raw]
            $Resource = if ($Row.resourceDisplayName) { [string]$Row.resourceDisplayName } else { [string]$Row.resourceId }
            $KeyId = [string]$Row.servicePrincipalCredentialKeyId
            $Type = [string]$Row.clientCredentialType
            $Attached = [string]$Row.managedServiceIdentity.associatedResourceId
            $Asn = [string]$Row.autonomousSystemNumber
            $Country = [string]$Row.location.countryOrRegion
            foreach ($Pair in @(@('ASNs', $Asn), @('Countries', $Country), @('Resources', $Resource), @('CredentialTypes', $Type), @('AttachedResources', $Attached))) {
                if ($Pair[1] -and $Pair[1] -ne '0') { $Counts[$Pair[0]][$Pair[1]] = [int]$Counts[$Pair[0]][$Pair[1]] + 1 }
            }
            if ($IP) {
                $Entry = $null
                if (-not $ByIP.TryGetValue($IP, [ref]$Entry)) {
                    $Entry = @{
                        IP = $IP; Count = 0; Success = 0; Failed = 0; First = $When; Last = $When; Country = $Country; City = [string]$Row.location.city; ASN = $Asn
                        Resources = [System.Collections.Generic.HashSet[string]]::new($Comparer); KeyIds = [System.Collections.Generic.HashSet[string]]::new($Comparer)
                        CredentialTypes = [System.Collections.Generic.HashSet[string]]::new($Comparer); ErrorCodes = [System.Collections.Generic.HashSet[string]]::new()
                        AttachedResources = [System.Collections.Generic.HashSet[string]]::new($Comparer)
                    }
                    $ByIP[$IP] = $Entry
                }
                $Entry.Count++
                if ($Ok) { $Entry.Success++ } else { $Entry.Failed++; $null = $Entry.ErrorCodes.Add([string]$Row.status.errorCode) }
                if ($When -and $When -lt $Entry.First) { $Entry.First = $When }
                if ($When -and $When -gt $Entry.Last) { $Entry.Last = $When }
                if ($Resource) { $null = $Entry.Resources.Add($Resource) }
                if ($KeyId) { $null = $Entry.KeyIds.Add($KeyId) }
                if ($Type) { $null = $Entry.CredentialTypes.Add($Type) }
                if ($Attached) { $null = $Entry.AttachedResources.Add($Attached) }
            }
            if ($KeyId) {
                $Entry = $null
                if (-not $ByKey.TryGetValue($KeyId, [ref]$Entry)) {
                    $Entry = @{ KeyId = $KeyId; Thumbprint = [string]$Row.servicePrincipalCredentialThumbprint; CredentialType = $Type; Count = 0; Success = 0; Failed = 0; First = $When; Last = $When; IPs = [System.Collections.Generic.HashSet[string]]::new($Comparer) }
                    $ByKey[$KeyId] = $Entry
                }
                $Entry.Count++
                if ($Ok) { $Entry.Success++ } else { $Entry.Failed++ }
                if ($When -and $When -lt $Entry.First) { $Entry.First = $When }
                if ($When -and $When -gt $Entry.Last) { $Entry.Last = $When }
                if ($IP) { $null = $Entry.IPs.Add($IP) }
            }
            if ($Recent.Count -lt $Keep) {
                $Recent.Add([pscustomobject]@{
                        CreatedDateTime  = if ($When) { $When.ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
                        IPAddress        = $IP
                        Status           = if ($Ok) { 'Success' } else { 'Failed' }
                        ErrorCode        = $Row.status.errorCode
                        FailureReason    = $Row.status.failureReason
                        Resource         = $Resource
                        KeyId            = $KeyId
                        CredentialType   = $Type
                        AttachedResource = $Attached
                        Country          = $Country
                        City             = [string]$Row.location.city
                        ASN              = $Asn
                        IPVerdict        = $null
                    })
            }
        }
        $Sorted = { param($Table) @($Table.GetEnumerator() | Sort-Object -Property Value -Descending | ForEach-Object { $_.Key }) }
        [pscustomobject]@{
            Total               = $Agg.Total
            Success             = $Agg.Success
            Failed              = $Agg.Failed
            First               = $Agg.First
            Last                = $Agg.Last
            ActiveDays          = $Days.Count
            Capped              = $Agg.Total -ge $Cap
            IPs                 = @($ByIP.Keys)
            ASNs                = @($Counts.ASNs.GetEnumerator() | Sort-Object -Property Value -Descending | ForEach-Object { [pscustomobject]@{ ASN = $_.Key; Count = $_.Value } })
            Countries           = & $Sorted $Counts.Countries
            Resources           = & $Sorted $Counts.Resources
            CredentialTypes     = & $Sorted $Counts.CredentialTypes
            AttachedResources   = & $Sorted $Counts.AttachedResources
            KeyIds              = @($ByKey.Keys)
            ByIP                = @(foreach ($Entry in $ByIP.Values) {
                    [pscustomobject]@{
                        IP = $Entry.IP; Count = $Entry.Count; Success = $Entry.Success; Failed = $Entry.Failed; First = $Entry.First; Last = $Entry.Last
                        Country = $Entry.Country; City = $Entry.City; ASN = $Entry.ASN; Resources = @($Entry.Resources); KeyIds = @($Entry.KeyIds)
                        CredentialTypes = @($Entry.CredentialTypes); ErrorCodes = @($Entry.ErrorCodes); AttachedResources = @($Entry.AttachedResources)
                    }
                }) | Sort-Object -Property Count -Descending
            ByCredential        = @(foreach ($Entry in $ByKey.Values) {
                    [pscustomobject]@{ KeyId = $Entry.KeyId; Thumbprint = $Entry.Thumbprint; CredentialType = $Entry.CredentialType; Count = $Entry.Count; Success = $Entry.Success; Failed = $Entry.Failed; First = $Entry.First; Last = $Entry.Last; IPs = @($Entry.IPs) }
                })
            Recent              = $Recent.ToArray()
        }
    }
    $SignInFilter = if ($Subject.IsManagedIdentity) { "servicePrincipalId eq '$ServicePrincipalId' and signInEventTypes/any(t: t eq 'managedIdentity')" } else { "servicePrincipalId eq '$ServicePrincipalId' and signInEventTypes/any(t: t eq 'servicePrincipal')" }
    # managedServiceIdentity (the Azure resource behind a managed identity's sign-in) cannot be selected - Graph answers
    # "Unsupported Query" - so a managed identity reads whole rows, which carry it.
    # an app's sign-ins are slow for Graph to search: a week of a busy app's runs past the request timeout
    $SliceHours = [int]($Heuristics.caps.signInSliceHours ?? 24)
    $SignInSelect = if ($Subject.IsManagedIdentity) { $null } else { 'id,createdDateTime,ipAddress,location,autonomousSystemNumber,resourceDisplayName,resourceId,status,servicePrincipalCredentialKeyId,servicePrincipalCredentialThumbprint,clientCredentialType,federatedCredentialId' }
    # Who made a change: a person, the app itself, CIPP, a Microsoft service or another app.
    $CippAppId = [System.Environment]::GetEnvironmentVariable('ApplicationID')

    if ($IsFirst) {
        try {
            $null = New-CIPPAsyncDeployment -JobId $CaseId -Names @($ServicePrincipalId) -StepTitles @($RunSteps.Title) -Source 'NHI' -TenantFilter $TenantFilter
            Set-CIPPAsyncDeploymentStatus -JobId $CaseId -Name $ServicePrincipalId -Status 'running'
            $null = Set-CIPPBecReport -Kind 'NHI' -TenantFilter $TenantFilter -CaseId $CaseId -Properties @{ Status = 'Running'; StartedAt = (Get-Date).ToUniversalTime().ToString('o') }
        } catch {
            Write-Information "NHI: progress reporting unavailable for $CaseId`: $($_.Exception.Message)"
        }
    } else {
        # An earlier phase still marked running or pending never finished: its worker timed out or restarted.
        $Job = try { @(Get-CIPPAsyncDeployment -JobId $CaseId) | Select-Object -First 1 } catch { $null }
        $JobSteps = @($Job.Steps)
        for ($i = 0; $i -lt [Math]::Min($StepIndex, $JobSteps.Count); $i++) {
            if ($JobSteps[$i].Status -in @('running', 'pending')) {
                $Stopped = 'The phase stopped before it finished (worker timeout or restart); its checks are missing from this run.'
                & $Step $i 'failed' $Stopped
                & $Mark $RunSteps[$i].Title ([pscustomobject]@{ Complete = $false; Error = $Stopped })
            }
        }
    }

    & $Step $StepIndex 'running' $RunSteps[$StepIndex].Running
    try {
        $StepMessage = 'Done'
        switch ($Key) {
            'Subject' {
                $Sp = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/servicePrincipals/$($ServicePrincipalId)?`$select=id,appId,displayName,servicePrincipalType,accountEnabled,appOwnerOrganizationId,createdDateTime,publisherName,verifiedPublisher,signInAudience,alternativeNames,disabledByMicrosoftStatus" -tenantid $TenantFilter -AsApp $true
                $TenantId = [string](@(Get-Tenants -TenantFilter $TenantFilter) | Select-Object -First 1).customerId
                $IsManagedIdentity = $Sp.servicePrincipalType -eq 'ManagedIdentity'
                $IsOwnApp = -not $IsManagedIdentity -and $TenantId -and [string]$Sp.appOwnerOrganizationId -eq $TenantId
                $OwnerSelect = '$select=id,displayName,userPrincipalName,userType,appId'
                $Requests = @(
                    @{ id = 'Owners'; method = 'GET'; url = "servicePrincipals/$ServicePrincipalId/owners?$OwnerSelect" }
                    @{ id = 'AppRoles'; method = 'GET'; url = "servicePrincipals/$ServicePrincipalId/appRoleAssignments?`$top=999" }
                    @{ id = 'Grants'; method = 'GET'; url = "oauth2PermissionGrants?`$filter=clientId eq '$ServicePrincipalId'&`$top=999" }
                    @{ id = 'Roles'; method = 'GET'; url = "roleManagement/directory/roleAssignments?`$filter=principalId eq '$ServicePrincipalId'&`$expand=roleDefinition(`$select=displayName,templateId,isBuiltIn)" }
                    @{ id = 'Risk'; method = 'GET'; url = "identityProtection/riskyServicePrincipals?`$filter=id eq '$ServicePrincipalId'" }
                    @{ id = 'Detections'; method = 'GET'; url = "identityProtection/servicePrincipalRiskDetections?`$filter=servicePrincipalId eq '$ServicePrincipalId'&`$top=100" }
                    if ($IsOwnApp) { @{ id = 'App'; method = 'GET'; url = "applications(appId='$($Sp.appId)')?`$select=id,appId,displayName,createdDateTime,signInAudience,web,spa,publicClient,servicePrincipalLockConfiguration,disabledByMicrosoftStatus&`$expand=owners($OwnerSelect)" } }
                )
                $Responses = @(New-GraphBulkRequest -Requests $Requests -tenantid $TenantFilter -asapp $true)
                $Body = @{}
                foreach ($Request in $Requests) {
                    $Response = $Responses | Where-Object { $_.id -eq $Request.id } | Select-Object -First 1
                    $Failed = (-not $Response) -or [int]$Response.status -ge 400
                    $Message = if ($Failed) { [string]($Response.body.error.message ?? "Graph request $($Request.id) failed") } else { $null }
                    $Body[$Request.id] = if ($Failed) { $null } elseif ($Request.id -eq 'App') { $Response.body } else { @($Response.body.value | Where-Object { $_ }) }
                    # Identity Protection for workload identities is a licence of its own: a refusal is a skipped check
                    $Unlicensed = $Failed -and $Request.id -in 'Risk', 'Detections' -and ([int]$Response.status -eq 403 -or $Message -match '(?i)(licen[cs]e|premium)')
                    & $Mark "Subject$($Request.id)" ([pscustomobject]@{
                            Complete    = -not $Failed
                            Error       = if ($Failed -and -not $Unlicensed) { $Message }
                            Skipped     = $Unlicensed
                            Requirement = if ($Unlicensed) { 'requires Microsoft Entra Workload ID Premium' }
                            Count       = @($Body[$Request.id]).Count
                        })
                }
                # The names of the application permissions: the appRoles of each resource the app holds them on.
                $RoleNames = @{}
                $ResourceIds = @($Body.AppRoles | ForEach-Object { [string]$_.resourceId } | Where-Object { $_ } | Select-Object -Unique)
                if ($ResourceIds.Count -gt 0) {
                    try {
                        foreach ($Response in @(New-GraphBulkRequest -Requests @($ResourceIds | ForEach-Object { @{ id = $_; method = 'GET'; url = "servicePrincipals/$($_)?`$select=id,appRoles" } }) -tenantid $TenantFilter -asapp $true)) {
                            foreach ($AppRole in @($Response.body.appRoles)) { if ($AppRole.id) { $RoleNames["$($Response.id)|$($AppRole.id)"] = [string]$AppRole.value } }
                        }
                    } catch { Write-Information "NHI: permission names unavailable: $($_.Exception.Message)" }
                }
                $App = $Body.App
                $Exposure = & $Collect 'Exposure' {
                    $Row = @(Get-CIPPAppPermissionExposure -TenantFilter $TenantFilter -Live -ServicePrincipalId $ServicePrincipalId -IncludeUncatalogued) | Select-Object -First 1
                    New-CIPPBecCollectorResult -Data $Row -Count ([int][bool]$Row)
                }
                & $Mark 'Exposure' $Exposure
                $Rogue = try { (Get-CIPPBecRogueAppFeed).Apps[([string]$Sp.appId).ToLowerInvariant()] } catch { Write-Information "NHI: rogue-app feed unavailable: $($_.Exception.Message)"; $null }
                $SubjectValues = [pscustomobject]@{
                    Id                     = [string]$Sp.id
                    AppId                  = [string]$Sp.appId
                    DisplayName            = [string]$Sp.displayName
                    ServicePrincipalType   = [string]$Sp.servicePrincipalType
                    AccountEnabled         = $Sp.accountEnabled
                    AppOwnerOrganizationId = [string]$Sp.appOwnerOrganizationId
                    CreatedDateTime        = $Sp.createdDateTime
                    PublisherName          = [string]$Sp.publisherName
                    VerifiedPublisher      = [string]$Sp.verifiedPublisher.displayName
                    SignInAudience         = [string]$Sp.signInAudience
                    AzureResourceId        = @($Sp.alternativeNames) -like '/subscriptions/*' | Select-Object -First 1
                    IsManagedIdentity      = [bool]$IsManagedIdentity
                    IsOwnApp               = [bool]$IsOwnApp
                    AppRegistrationId      = [string]$App.id
                    AppSignInAudience      = [string]$App.signInAudience
                    RedirectUris           = @(@($App.web.redirectUris) + @($App.spa.redirectUris) + @($App.publicClient.redirectUris) | Where-Object { $_ })
                    PropertyLock           = $App.servicePrincipalLockConfiguration.isEnabled
                    Ownership              = $Exposure.Data.Ownership
                    IsMicrosoftApp         = [bool]$Exposure.Data.IsMicrosoftApp
                    IsCippApp              = [bool]($CippAppId -and $Sp.appId -eq $CippAppId)
                }
                $Owners = @(
                    foreach ($Pair in @(@('Enterprise app', $Body.Owners), @('App registration', $App.owners))) {
                        foreach ($Owner in @($Pair[1] | Where-Object { $_ })) {
                            [pscustomobject]@{ Id = [string]$Owner.id; DisplayName = [string]$Owner.displayName; UserPrincipalName = [string]$Owner.userPrincipalName; UserType = [string]$Owner.userType; IsApp = [bool]$Owner.appId; OwnerOf = $Pair[0]; ObjectId = if ($Pair[0] -eq 'Enterprise app') { $ServicePrincipalId } else { [string]$App.id } }
                        }
                    })
                $AppRoleAssignments = @(foreach ($Assignment in $Body.AppRoles) {
                        [pscustomobject]@{
                            Id                  = [string]$Assignment.id
                            ResourceId          = [string]$Assignment.resourceId
                            ResourceDisplayName = [string]$Assignment.resourceDisplayName
                            AppRoleId           = [string]$Assignment.appRoleId
                            Permission          = $RoleNames["$($Assignment.resourceId)|$($Assignment.appRoleId)"] ?? [string]$Assignment.appRoleId
                            CreatedDateTime     = $Assignment.createdDateTime
                            InWindow            = [bool]($Assignment.createdDateTime -and ([datetime]$Assignment.createdDateTime).ToUniversalTime() -ge $startDate)
                        }
                    })
                $DelegatedGrants = @(foreach ($Grant in $Body.Grants) {
                        [pscustomobject]@{ Id = [string]$Grant.id; ResourceId = [string]$Grant.resourceId; ConsentType = [string]$Grant.consentType; PrincipalId = [string]$Grant.principalId; Scope = ([string]$Grant.scope).Trim() }
                    })
                $DirectoryRoles = @(foreach ($Role in $Body.Roles) {
                        [pscustomobject]@{ Id = [string]$Role.id; RoleDefinitionId = [string]$Role.roleDefinitionId; RoleName = [string]$Role.roleDefinition.displayName; DirectoryScopeId = [string]$Role.directoryScopeId }
                    })
                & $Save @{
                    Subject            = $SubjectValues
                    Exposure           = $Exposure.Data
                    Owners             = $Owners
                    AppRoleAssignments = $AppRoleAssignments
                    DelegatedGrants    = $DelegatedGrants
                    DirectoryRoles     = $DirectoryRoles
                    RogueMatch         = if ($Rogue) { [pscustomobject]@{ Name = $Rogue.Name; Categories = @($Rogue.Categories); Description = $Rogue.Description; Source = $Rogue.Source } } else { $null }
                    RiskState          = @($Body.Risk) | Select-Object -First 1
                    RiskDetections     = @($Body.Detections)
                }
                $StepMessage = "$(if ($IsManagedIdentity) { 'Managed identity' } elseif ($IsOwnApp) { 'App registered in this tenant' } else { "App owned by $($Exposure.Data.Ownership ?? 'another organisation')" }), exposure $($Exposure.Data.Risk ?? 'unknown')"
            }

            'Changes' {
                # Everything done to the app since the baseline started: persistence is usually set up before the window.
                $Since = $baselineStart.ToString('yyyy-MM-ddTHH:mm:ssZ')
                $TargetIds = @($ServicePrincipalId, $Subject.AppRegistrationId) | Where-Object { $_ }
                $Result = & $Collect 'Changes' {
                    $Events = @{}
                    foreach ($TargetId in $TargetIds) {
                        foreach ($AuditEvent in @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?`$filter=activityDateTime ge $Since and targetResources/any(t:t/id eq '$TargetId')&`$top=999" -tenantid $TenantFilter -AsApp $true)) {
                            if ($AuditEvent.id) { $Events[[string]$AuditEvent.id] = $AuditEvent }
                        }
                    }
                    # The owner organisation of every app that changed this one: a Microsoft service is housekeeping.
                    $ActorOwners = @{}
                    $ActorIds = @($Events.Values | ForEach-Object { [string]$_.initiatedBy.app.servicePrincipalId } | Where-Object { $_ -match '^[0-9a-fA-F-]{36}$' } | Select-Object -Unique)
                    if ($ActorIds.Count -gt 0) {
                        try {
                            foreach ($Response in @(New-GraphBulkRequest -Requests @($ActorIds | ForEach-Object { @{ id = $_; method = 'GET'; url = "servicePrincipals/$($_)?`$select=id,appOwnerOrganizationId" } }) -tenantid $TenantFilter -asapp $true)) {
                                if ([int]$Response.status -eq 200) { $ActorOwners[[string]$Response.id] = [string]$Response.body.appOwnerOrganizationId }
                            }
                        } catch { Write-Information "NHI: actor apps unavailable: $($_.Exception.Message)" }
                    }
                    $VendorTenants = Get-CIPPVendorTenantMap
                    $C = $Heuristics.changes
                    $Changes = foreach ($AuditEvent in $Events.Values) {
                        $Properties = @(foreach ($Target in @($AuditEvent.targetResources)) { if ($Target.id -in $TargetIds) { @($Target.modifiedProperties) } }) | Where-Object { $_ }
                        $PropertyNames = @($Properties.displayName | Where-Object { $_ }) -join ' '
                        $Activity = [string]$AuditEvent.activityDisplayName
                        $Kind = if ($Activity -match $C.credentialActivityRegex -or $PropertyNames -match '(?i)\b(KeyDescription|keyCredentials|passwordCredentials)\b') {
                            'Credential'
                        } elseif ($Activity -match $C.federatedRegex -or $PropertyNames -match $C.federatedRegex) {
                            'FederatedCredential'
                        } elseif ($Activity -match $C.ownerActivityRegex) {
                            'Owner'
                        } elseif ($PropertyNames -match $C.redirectRegex) {
                            'RedirectUri'
                        } elseif ($PropertyNames -match $C.audienceRegex) {
                            # only opening the app to other organisations counts
                            $NewValue = @($Properties | Where-Object { $_.displayName -match $C.audienceRegex }).newValue -join ' '
                            if ($NewValue -match '(?i)(multipleorgs|personal|true)') { 'Audience' } else { 'Other' }
                        } elseif ($PropertyNames -match $C.lockRegex) {
                            'Lock'
                        } elseif ($Activity -in @($C.grantActivities)) {
                            'Grant'
                        } elseif ($PropertyNames -match $C.enabledRegex) {
                            'Enabled'
                        } elseif ($Activity -match '(?i)^Add (service principal|application)$') {
                            'Created'
                        } else {
                            'Other'
                        }
                        $ActorApp = $AuditEvent.initiatedBy.app
                        $ByType = if ($ActorApp.appId -or $ActorApp.servicePrincipalId) { 'Application' } else { 'User' }
                        $BySelf = $ByType -eq 'Application' -and ($ActorApp.appId -eq $Subject.AppId -or $ActorApp.servicePrincipalId -eq $ServicePrincipalId)
                        $OwnerOrg = $ActorOwners[[string]$ActorApp.servicePrincipalId]
                        $ByMicrosoft = $OwnerOrg -and $VendorTenants[$OwnerOrg].VendorType -eq 'Microsoft'
                        $ByCipp = $CippAppId -and $ActorApp.appId -eq $CippAppId
                        $When = ([datetime]$AuditEvent.activityDateTime).ToUniversalTime()
                        [pscustomobject]@{
                            ActivityDateTime = $When.ToString('yyyy-MM-ddTHH:mm:ssZ')
                            Activity         = $Activity
                            Kind             = $Kind
                            Result           = [string]$AuditEvent.result
                            InitiatedBy      = if ($ByType -eq 'Application') { [string]($ActorApp.displayName ?? $ActorApp.appId) } else { [string]($AuditEvent.initiatedBy.user.userPrincipalName ?? $AuditEvent.initiatedBy.user.displayName) }
                            InitiatedByType  = $ByType
                            InitiatedById    = if ($ByType -eq 'Application') { [string]$ActorApp.appId } else { [string]$AuditEvent.initiatedBy.user.id }
                            ClientIP         = ConvertTo-CIPPBecHostAddress -Address ([string]$AuditEvent.initiatedBy.user.ipAddress)
                            BySelf           = [bool]$BySelf
                            ByCipp           = [bool]$ByCipp
                            # a change by an app is unusual, unless that app is CIPP or a Microsoft service
                            ByApp            = [bool]($ByType -eq 'Application' -and -not $ByCipp -and -not $ByMicrosoft)
                            InWindow         = $When -ge $startDate
                            Flagged          = $Kind -in 'Credential', 'FederatedCredential', 'Owner', 'RedirectUri', 'Audience', 'Lock', 'Grant'
                            Detail           = (@($Properties | Where-Object { $_.displayName -and $_.displayName -notmatch '(?i)^Included Updated Properties$' } | ForEach-Object { $_.displayName }) | Select-Object -Unique) -join ', '
                        }
                    }
                    New-CIPPBecCollectorResult -Data @($Changes | Sort-Object -Property ActivityDateTime -Descending)
                }
                & $Mark 'Changes' $Result
                & $Save @{ Changes = @($Result.Data) }
                $StepMessage = "$(@($Result.Data | Where-Object { $_.Flagged -and $_.InWindow }).Count) flagged change(s) in the window"
            }

            { $_ -in 'SignIns', 'Baseline' } {
                $IsWindow = $Key -eq 'SignIns'
                if (-not (& $HasP1)) {
                    $Result = New-CIPPBecCollectorResult -Data $null -Skipped $true -Requirement 'requires Entra ID P1 (sign-in logs)'
                } else {
                    $From = if ($IsWindow) { $startDate } else { $baselineStart }
                    $To = if ($IsWindow) { $endDate } else { $startDate }
                    $Result = & $Collect $Key {
                        $Folded = & $Fold { Search-CIPPBecSignIn -TenantFilter $TenantFilter -Filter $SignInFilter -StartDate $From -EndDate $To -Select $SignInSelect -SliceHours $SliceHours -Stream } $(if ($IsWindow) { [int]($Heuristics.caps.rawSignIns ?? 500) } else { 0 })
                        New-CIPPBecCollectorResult -Data $Folded -Count $Folded.Total -Complete (-not $Folded.Capped) -Cap $(if ($Folded.Capped) { "the newest $($Folded.Total) sign-ins" })
                    }
                }
                & $Mark $Key $Result
                $Folded = $Result.Data
                if ($IsWindow) {
                    & $Save @{
                        SignInSummary       = if ($Folded) { $Folded | Select-Object -Property * -ExcludeProperty ByIP, ByCredential, Recent, IPs } else { $null }
                        SignInsByIP         = @($Folded.ByIP)
                        SignInsByCredential = @($Folded.ByCredential)
                        RecentSignIns       = @($Folded.Recent)
                    }
                } else {
                    & $Save @{ Baseline = if ($Folded) { $Folded | Select-Object -Property * -ExcludeProperty ByIP, ByCredential, Recent } else { $null } }
                }
                $StepMessage = if ($Result.Skipped) { 'Skipped: requires Entra ID P1' } else { "$([int]$Folded.Total) sign-in(s) from $(@($Folded.IPs).Count) address(es)" }
            }

            'DelegatedUse' {
                # Users signing in to the app: a consent-phishing app shows as a burst of new users, and an app abusing their
                # tokens as non-interactive sign-ins from its own servers. Not for managed identities (no users) or Microsoft's apps (everyone).
                $Result = if ($Subject.IsManagedIdentity -or $Subject.IsMicrosoftApp) {
                    New-CIPPBecCollectorResult -Data $null -Skipped $true -Requirement $(if ($Subject.IsManagedIdentity) { 'not applicable to a managed identity' } else { "not applicable to Microsoft's own apps" })
                } elseif (-not (& $HasP1)) {
                    New-CIPPBecCollectorResult -Data $null -Skipped $true -Requirement 'requires Entra ID P1 (sign-in logs)'
                } else {
                    & $Collect 'DelegatedUse' {
                        $Cap = [int]($Heuristics.caps.signInRows ?? 100000)
                        $Users = @{}
                        $Total = 0
                        foreach ($Interactive in $true, $false) {
                            $Filter = if ($Interactive) { "appId eq '$($Subject.AppId)'" } else { "appId eq '$($Subject.AppId)' and signInEventTypes/any(t: t eq 'nonInteractiveUser')" }
                            Search-CIPPBecSignIn -TenantFilter $TenantFilter -Filter $Filter -StartDate $startDate -EndDate $endDate -Select 'createdDateTime,userId,userPrincipalName,ipAddress,status,location' -AsApp $false -SliceHours $SliceHours -Stream | Select-Object -First $Cap | ForEach-Object {
                                $Total++
                                $UserKey = [string]$_.userId
                                if (-not $Users.ContainsKey($UserKey)) {
                                    $Users[$UserKey] = @{ UserId = $UserKey; UserPrincipalName = [string]$_.userPrincipalName; Count = 0; Success = 0; Interactive = $false; IPs = [System.Collections.Generic.HashSet[string]]::new(); Countries = [System.Collections.Generic.HashSet[string]]::new(); First = $null; Last = $null }
                                }
                                $Entry = $Users[$UserKey]
                                $Entry.Count++
                                if ([int]$_.status.errorCode -eq 0) { $Entry.Success++ }
                                if ($Interactive) { $Entry.Interactive = $true }
                                $IP = ConvertTo-CIPPBecHostAddress -Address ([string]$_.ipAddress)
                                if ($IP) { $null = $Entry.IPs.Add($IP) }
                                if ($_.location.countryOrRegion) { $null = $Entry.Countries.Add([string]$_.location.countryOrRegion) }
                                $When = ([datetime]$_.createdDateTime).ToUniversalTime()
                                if (-not $Entry.First -or $When -lt $Entry.First) { $Entry.First = $When }
                                if (-not $Entry.Last -or $When -gt $Entry.Last) { $Entry.Last = $When }
                            }
                        }
                        $Data = @(foreach ($Entry in $Users.Values) {
                                [pscustomobject]@{ UserId = $Entry.UserId; UserPrincipalName = $Entry.UserPrincipalName; SignIns = $Entry.Count; Successful = $Entry.Success; Interactive = $Entry.Interactive; IPs = @($Entry.IPs); Countries = @($Entry.Countries); First = $Entry.First; Last = $Entry.Last }
                            }) | Sort-Object -Property SignIns -Descending
                        New-CIPPBecCollectorResult -Data @($Data) -Count $Total -Complete ($Total -lt $Cap * 2) -Cap $(if ($Total -ge $Cap * 2) { "the newest $Cap user sign-ins of each kind" })
                    }
                }
                & $Mark 'DelegatedUse' $Result
                & $Save @{ DelegatedSignIns = @($Result.Data) }
                $StepMessage = if ($Result.Skipped) { "Skipped: $($Result.Requirement)" } else { "$(@($Result.Data).Count) user(s) signed in to the app" }
            }

            'DirectoryActions' {
                # What the app itself changed in the directory since the baseline started.
                $Since = $baselineStart.ToString('yyyy-MM-ddTHH:mm:ssZ')
                $OwnIds = @($ServicePrincipalId, $Subject.AppRegistrationId) | Where-Object { $_ }
                $Critical = @($Heuristics.directoryActions.criticalActivities)
                $Flagged = @($Heuristics.directoryActions.flaggedActivities)
                $AppCreation = @($Heuristics.directoryActions.appCreationActivities)
                $Catalog = Get-CIPPRiskyPermissionCatalog
                $ImpactRank = @{ Low = 1; Medium = 2; High = 3; Critical = 4 }
                $Result = & $Collect 'DirectoryActions' {
                    $Events = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?`$filter=activityDateTime ge $Since and initiatedBy/app/appId eq '$($Subject.AppId)'&`$top=999" -tenantid $TenantFilter -AsApp $true)
                    $Actions = foreach ($AuditEvent in $Events) {
                        $Activity = [string]$AuditEvent.activityDisplayName
                        $Targets = @(foreach ($Target in @($AuditEvent.targetResources)) { [pscustomobject]@{ Type = [string]$Target.type; Id = [string]$Target.id; DisplayName = [string]$Target.displayName; UserPrincipalName = [string]$Target.userPrincipalName } })
                        $OnApps = @($Targets | Where-Object { $_.Type -in 'ServicePrincipal', 'Application' })
                        # a credential or owner on its own objects is the app rotating itself (and a change in Changes); on another app it is lateral movement
                        $Persistence = $Activity -match $Heuristics.changes.credentialActivityRegex -or $Activity -match $Heuristics.changes.ownerActivityRegex
                        $OnSelf = $OnApps.Count -gt 0 -and @($OnApps | Where-Object { $_.Id -notin $OwnIds }).Count -eq 0
                        $Lateral = $Persistence -and $OnApps.Count -gt 0 -and -not $OnSelf
                        # App persistence: apps it created, and credentials or owners it put on other apps - a foothold
                        # that outlives removing this app.
                        $CreatedApp = $Activity -in $AppCreation
                        # Elevation: access the app granted - an application or delegated permission, or a directory role -
                        # to itself, another app or a user, rated by the catalog's impact of what was granted.
                        $Elevation = $null
                        if ($Activity -eq 'Add app role assignment to service principal') {
                            $Props = @{}
                            foreach ($Target in @($AuditEvent.targetResources)) { foreach ($Prop in @($Target.modifiedProperties)) { if ($Prop.displayName) { $Props[[string]$Prop.displayName] = ([string]$Prop.newValue).Trim('"', ' ') } } }
                            $Resource = @($AuditEvent.targetResources | Where-Object { @($_.modifiedProperties.displayName) -contains 'AppRole.Id' }) | Select-Object -First 1
                            $RecipientId = $Props['ServicePrincipal.ObjectID']
                            if (-not $RecipientId -or $RecipientId -eq $Resource.id) { $RecipientId = [string](@($AuditEvent.targetResources | Where-Object { $_.type -eq 'ServicePrincipal' -and $_.id -ne $Resource.id }) | Select-Object -First 1).id }
                            $Entry = $null
                            [void]$Catalog.Application.TryGetValue("$($Catalog.ApiByDisplayName[[string]$Resource.displayName])|$($Props['AppRole.Id'])", [ref]$Entry)
                            $Elevation = @{ Type = 'Application permission'; Permission = "$($Resource.displayName) $($Props['AppRole.Value'])"; RoleId = $Props['AppRole.Id']; ResourceId = [string]$Resource.id; RecipientId = $RecipientId; RecipientType = 'ServicePrincipal'; RecipientName = $Props['ServicePrincipal.DisplayName']; Impact = [string]($Entry.impact ?? 'Low') }
                        } elseif ($Activity -like 'Add delegated permission grant*') {
                            $Grant = @(ConvertFrom-CIPPGrantAuditEvent -Events @($AuditEvent)) | Select-Object -First 1
                            if ($Grant) {
                                $Api = $Catalog.ApiByDisplayName[[string]$Grant.resourceDisplayName]
                                $Rank = 0
                                foreach ($Scope in ([string]$Grant.scope).Split([char[]]' ', [System.StringSplitOptions]::RemoveEmptyEntries)) {
                                    $Entry = $null
                                    if ($Catalog.Delegated.TryGetValue("$Api|$Scope", [ref]$Entry)) { $Rank = [Math]::Max($Rank, [int]$ImpactRank[[string]$Entry.impact]) }
                                }
                                $Elevation = @{ Type = 'Delegated permission'; Permission = "$($Grant.resourceDisplayName) $($Grant.scope) ($($Grant.consentType))"; Scopes = [string]$Grant.scope; ConsentType = [string]$Grant.consentType; ResourceId = [string]$Grant.resourceId; RecipientId = [string]$Grant.clientId; RecipientType = 'ServicePrincipal'; RecipientName = $null; Impact = @('Low', 'Low', 'Medium', 'High', 'Critical')[$Rank] }
                            }
                        } elseif ($Activity -like 'Add member to role*' -or $Activity -like 'Add eligible member to role*') {
                            $Role = @(ConvertFrom-CIPPRoleAuditEvent -Events @($AuditEvent) -AnyPrincipal | Where-Object { $_.roleId }) | Select-Object -First 1
                            if ($Role) {
                                $Entry = $null
                                [void]$Catalog.DirectoryRole.TryGetValue([string]$Role.roleId, [ref]$Entry)
                                # a role outside the catalog is still a directory role an app handed out
                                $Elevation = @{ Type = if ($Activity -like 'Add eligible*') { 'Eligible directory role' } else { 'Directory role' }; Permission = [string]$Role.roleName; RoleId = [string]$Role.roleId; RecipientId = [string]$Role.targetId; RecipientType = [string]$Role.targetType; RecipientName = [string]$Role.targetDisplayName; Impact = [string]($Entry.impact ?? 'Medium') }
                            }
                        }
                        if ($Elevation) {
                            $Elevation.Recipient = if ($Elevation.RecipientId -and $Elevation.RecipientId -in $OwnIds) { 'Self' } elseif ($Elevation.RecipientType -eq 'User') { 'User' } else { 'App' }
                            if (-not $Elevation.RecipientName) { $Elevation.RecipientName = [string](@($Targets | Where-Object Id -EQ $Elevation.RecipientId) | Select-Object -First 1).DisplayName }
                        }
                        $When = ([datetime]$AuditEvent.activityDateTime).ToUniversalTime()
                        [pscustomobject]@{
                            ActivityDateTime = $When.ToString('yyyy-MM-ddTHH:mm:ssZ')
                            Activity         = $Activity
                            Category         = [string]$AuditEvent.category
                            Result           = [string]$AuditEvent.result
                            Targets          = $Targets
                            Kind             = if ($Elevation) { 'Elevation' } elseif ($Lateral -or $CreatedApp) { 'AppPersistence' } else { 'Directory' }
                            Severity         = if ($Elevation) {
                                if ($Elevation.Impact -in 'High', 'Critical') { 'Critical' } elseif ($Elevation.Impact -eq 'Medium') { 'Flagged' } else { 'Info' }
                            } elseif ($Persistence -and $OnSelf) { 'Info' } elseif ($Lateral -or $CreatedApp -or $Activity -in $Critical) { 'Critical' } elseif ($Activity -in $Flagged) { 'Flagged' } else { 'Info' }
                            Lateral          = [bool]$Lateral
                            CreatedApp       = [bool]$CreatedApp
                            ElevationId      = if ($Elevation) { "$($When.ToString('o'))|$($Elevation.RecipientId)|$($Elevation.RoleId ?? $Elevation.Scopes)" } else { $null }
                            ElevationType    = $Elevation.Type
                            Permission       = $Elevation.Permission
                            Impact           = $Elevation.Impact
                            Recipient        = $Elevation.Recipient
                            RecipientType    = $Elevation.RecipientType
                            RecipientId      = $Elevation.RecipientId
                            RecipientName    = $Elevation.RecipientName
                            ElevationRoleId  = $Elevation.RoleId
                            ResourceId       = $Elevation.ResourceId
                            Scopes           = $Elevation.Scopes
                            ConsentType      = $Elevation.ConsentType
                            InWindow         = $When -ge $startDate
                        }
                    }
                    # The app each persistence action touched, as the service principal an investigation or containment acts
                    # on: an app registration resolves through its appId, and one with no service principal here has none.
                    # Microsoft's and CIPP's apps are marked protected: disabling one breaks the tenant or cuts CIPP off.
                    $Persisted = @($Actions | Where-Object { $_.Kind -eq 'AppPersistence' })
                    $TargetOf = @{}
                    foreach ($Row in $Persisted) {
                        $Target = @($Row.Targets | Where-Object { $_.Type -in 'ServicePrincipal', 'Application' -and $_.Id -notin $OwnIds -and $_.Id -match '^[0-9a-fA-F-]{36}$' }) | Select-Object -First 1
                        if ($Target) { $TargetOf[$Target.Id] = $Target.Type }
                    }
                    $SpOf = @{}
                    if ($TargetOf.Count -gt 0) {
                        try {
                            $AppIdOf = @{}
                            $AppTargets = @($TargetOf.Keys | Where-Object { $TargetOf[$_] -eq 'Application' })
                            if ($AppTargets.Count -gt 0) {
                                foreach ($Response in @(New-GraphBulkRequest -Requests @($AppTargets | ForEach-Object { @{ id = $_; method = 'GET'; url = "applications/$($_)?`$select=id,appId" } }) -tenantid $TenantFilter -asapp $true)) {
                                    if ([int]$Response.status -eq 200 -and $Response.body.appId) { $AppIdOf[[string]$Response.id] = [string]$Response.body.appId }
                                }
                            }
                            $SpSelect = '$select=id,appId,displayName,appOwnerOrganizationId,accountEnabled'
                            $Requests = @(foreach ($Id in $TargetOf.Keys) {
                                    if ($TargetOf[$Id] -eq 'ServicePrincipal') { @{ id = $Id; method = 'GET'; url = "servicePrincipals/$($Id)?$SpSelect" } }
                                    elseif ($AppIdOf[$Id]) { @{ id = $Id; method = 'GET'; url = "servicePrincipals(appId='$($AppIdOf[$Id])')?$SpSelect" } }
                                })
                            if ($Requests.Count -gt 0) {
                                foreach ($Response in @(New-GraphBulkRequest -Requests $Requests -tenantid $TenantFilter -asapp $true)) {
                                    if ([int]$Response.status -eq 200 -and $Response.body.id) { $SpOf[[string]$Response.id] = $Response.body }
                                }
                            }
                        } catch {
                            Write-Information "NHI: the apps behind the persistence actions could not be resolved: $($_.Exception.Message)"
                        }
                    }
                    $VendorTenants = Get-CIPPVendorTenantMap
                    foreach ($Row in $Persisted) {
                        $Target = @($Row.Targets | Where-Object { $_.Type -in 'ServicePrincipal', 'Application' -and $_.Id -notin $OwnIds }) | Select-Object -First 1
                        $TargetSp = if ($Target) { $SpOf[[string]$Target.Id] } else { $null }
                        $Owner = [string]$TargetSp.appOwnerOrganizationId
                        $Row | Add-Member -NotePropertyMembers ([ordered]@{
                                TargetServicePrincipalId = [string]$TargetSp.id
                                TargetAppId              = [string]$TargetSp.appId
                                TargetDisplayName        = if ($TargetSp.displayName) { [string]$TargetSp.displayName } else { [string]$Target.DisplayName }
                                TargetProtected          = [bool](($Owner -and $VendorTenants[$Owner].VendorType -eq 'Microsoft') -or ($CippAppId -and $TargetSp.appId -eq $CippAppId))
                            }) -Force
                    }
                    New-CIPPBecCollectorResult -Data @($Actions | Sort-Object -Property ActivityDateTime -Descending)
                }
                & $Mark 'DirectoryActions' $Result
                & $Save @{ DirectoryActions = @($Result.Data) }
                $StepMessage = "$(@($Result.Data | Where-Object { $_.InWindow -and $_.Severity -ne 'Info' }).Count) flagged action(s) in the window"
            }

            { $_ -in 'WorkloadBaseline', 'WorkloadActivity' } {
                # Mail and files the app reached, from the unified audit log: records carry the acting app's id
                # (AppId, ClientAppId, or ApplicationId on SharePoint), which the free-text search finds. The baseline
                # is what it reached before the window: a backup or archiving app reads every mailbox every day.
                $IsWindow = $Key -eq 'WorkloadActivity'
                $W = $Heuristics.workload
                $Result = & $Collect $Key {
                    $From = if ($IsWindow) { $startDate } else { $baselineStart }
                    $To = if ($IsWindow) { $endDate } else { $startDate }
                    $Search = Search-CIPPBecAuditLog -TenantFilter $TenantFilter -StartDate $From -EndDate $To -Operations @($W.operations) -FreeText $Subject.AppId -MaxPages ([int]($Heuristics.caps.auditLogPages ?? 10))
                    $Mailboxes = @{}
                    $Files = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    $Sites = @{}
                    $ByIP = @{}
                    $ByOperation = @{}
                    $Rules = [System.Collections.Generic.List[object]]::new()
                    $MailItems = 0
                    $Sent = 0
                    foreach ($Record in @($Search.Records)) {
                        $AD = $Record.AuditData
                        # the free text also matches records that only mention the app id
                        if ($Subject.AppId -notin @([string]$AD.AppId, [string]$AD.ClientAppId, [string]$AD.ApplicationId)) { continue }
                        $Operation = [string]$Record.Operation
                        $Count = if ($AD.OperationCount) { [int]$AD.OperationCount } else { 1 }
                        $ByOperation[$Operation] = [int]$ByOperation[$Operation] + $Count
                        $IP = ConvertTo-CIPPBecHostAddress -Address ([string]($AD.ClientIPAddress ?? $AD.ClientIP))
                        $Kind = if ($Operation -in @($W.ruleOperations)) { 'Rule' } elseif ($Operation -in @($W.mailOperations)) { 'Mail' } else { 'File' }
                        if ($IP) {
                            if (-not $ByIP.ContainsKey($IP)) { $ByIP[$IP] = @{ IP = $IP; Count = 0; Kinds = [System.Collections.Generic.HashSet[string]]::new() } }
                            $ByIP[$IP].Count += $Count
                            $null = $ByIP[$IP].Kinds.Add($Kind)
                        }
                        $When = [string]$AD.CreationTime
                        if ($Kind -eq 'File') {
                            if ($AD.ObjectId) { $null = $Files.Add([string]$AD.ObjectId) }
                            $Site = [string]($AD.SiteUrl ?? $AD.ObjectId)
                            if ($Site) {
                                if (-not $Sites.ContainsKey($Site)) { $Sites[$Site] = @{ Site = $Site; Count = 0; Operations = [System.Collections.Generic.HashSet[string]]::new(); Files = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase) } }
                                $Sites[$Site].Count += $Count
                                $null = $Sites[$Site].Operations.Add($Operation)
                                if ($AD.ObjectId) { $null = $Sites[$Site].Files.Add([string]$AD.ObjectId) }
                            }
                            continue
                        }
                        if ($Kind -eq 'Rule') {
                            $Rules.Add([pscustomobject]@{ CreationTime = $When; Operation = $Operation; Mailbox = [string]($AD.MailboxOwnerUPN ?? $AD.ObjectId); ClientIP = $IP; Parameters = (@($AD.Parameters | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '; ') })
                        }
                        if ($Operation -eq 'MailItemsAccessed') { $MailItems += $Count }
                        if ($Operation -in 'Send', 'SendAs', 'SendOnBehalf') { $Sent += $Count }
                        $Mailbox = [string]($AD.MailboxOwnerUPN ?? $AD.UserId)
                        if ($Mailbox) {
                            if (-not $Mailboxes.ContainsKey($Mailbox)) { $Mailboxes[$Mailbox] = @{ Mailbox = $Mailbox; Count = 0; Operations = [System.Collections.Generic.HashSet[string]]::new(); IPs = [System.Collections.Generic.HashSet[string]]::new(); First = $When; Last = $When } }
                            $Entry = $Mailboxes[$Mailbox]
                            $Entry.Count += $Count
                            $null = $Entry.Operations.Add($Operation)
                            if ($IP) { $null = $Entry.IPs.Add($IP) }
                            if ($When -and $When -lt $Entry.First) { $Entry.First = $When }
                            if ($When -and $When -gt $Entry.Last) { $Entry.Last = $When }
                        }
                    }
                    $Data = [pscustomobject]@{
                        ByOperation = @($ByOperation.GetEnumerator() | Sort-Object -Property Value -Descending | ForEach-Object { [pscustomobject]@{ Operation = $_.Key; Count = $_.Value } })
                        Mailboxes   = @($Mailboxes.Values | ForEach-Object { [pscustomobject]@{ Mailbox = $_.Mailbox; Count = $_.Count; Operations = @($_.Operations); IPs = @($_.IPs); First = $_.First; Last = $_.Last } } | Sort-Object -Property Count -Descending)
                        Sites       = @($Sites.Values | ForEach-Object { [pscustomobject]@{ Site = $_.Site; Count = $_.Count; FileCount = $_.Files.Count; Operations = @($_.Operations) } } | Sort-Object -Property Count -Descending)
                        InboxRules  = $Rules.ToArray()
                        ByIP        = @($ByIP.Values | ForEach-Object { [pscustomobject]@{ IP = $_.IP; Count = $_.Count; Kinds = @($_.Kinds) } } | Sort-Object -Property Count -Descending)
                        Summary     = [pscustomobject]@{ MailboxCount = $Mailboxes.Count; MailItemCount = $MailItems; SendCount = $Sent; FileCount = $Files.Count; SiteCount = $Sites.Count; RuleCount = $Rules.Count; AnonymousLinkCount = [int]$ByOperation['AnonymousLinkCreated'] }
                    }
                    New-CIPPBecCollectorResult -Data $Data -Count (@($Search.Records).Count) -Complete $Search.Complete -Cap $Search.Cap
                }
                & $Mark $Key $Result
                if ($IsWindow) {
                    & $Save @{ WorkloadActivity = $Result.Data | Select-Object -Property * -ExcludeProperty Summary; WorkloadSummary = $Result.Data.Summary }
                } else {
                    # which mailboxes and sites, and how many operations: what the window is compared with
                    & $Save @{ WorkloadBaseline = if ($Result.PSObject.Properties['Data'] -and $Result.Data.Summary) {
                            [pscustomobject]@{
                                Mailboxes          = @($Result.Data.Mailboxes | ForEach-Object { $_.Mailbox })
                                Sites              = @($Result.Data.Sites | ForEach-Object { $_.Site })
                                Operations         = [int](@($Result.Data.ByOperation | ForEach-Object { [int]$_.Count }) | Measure-Object -Sum).Sum
                                SendCount          = [int]$Result.Data.Summary.SendCount
                                AnonymousLinkCount = [int]$Result.Data.Summary.AnonymousLinkCount
                                Complete           = [bool]$Result.Complete
                            }
                        } else { $null } }
                }
                $StepMessage = "$([int]$Result.Data.Summary.MailboxCount) mailbox(es), $([int]$Result.Data.Summary.FileCount) file(s)$(if (-not $IsWindow) { ' before the window' })"
            }

            'Score' {
                $Exposure = $State.Exposure
                $Credentials = @($Exposure.CredentialDetails | Where-Object { $_ -and $_.Purpose -eq 'Sign-in' -and -not $_.Expired })
                # Flagged: added by another app, backdated, trusting an unrecognised issuer, or added in the window - unless
                # it replaced an expiring or removed credential: a rotation is the app's own new credential, and removing
                # it in containment would break the app.
                $FlaggedKeyIds = @($Credentials | Where-Object {
                        @($_.Flags | Where-Object { $_ -in 'AddedByApp', 'Backdated', 'UntrustedIssuer' }).Count -gt 0 -or ($_.Flags -contains 'AddedRecently' -and $_.Flags -notcontains 'Rotation' -and $_.AddedDateTime -and ([datetime]$_.AddedDateTime).ToUniversalTime() -ge $startDate)
                    } | ForEach-Object { [string]$_.KeyId } | Where-Object { $_ } | Select-Object -Unique)
                # A Microsoft or CIPP app never carries a credential of its own here: every one is flagged.
                if ($Exposure.IsMicrosoftApp -or $Exposure.IsCippApp) { $FlaggedKeyIds = @($Credentials | Where-Object { $_.Location -eq 'Enterprise app' -and $_.KeyId } | ForEach-Object { [string]$_.KeyId }) + $FlaggedKeyIds | Select-Object -Unique }
                $SignInsByIP = & $Rows 'SignInsByIP'
                $Workload = $State.WorkloadActivity
                $WorkloadIPs = @($Workload.ByIP | Where-Object { $_.IP })

                Write-Information 'Resolving IP locations'
                $Geo = @{}
                $AllIPs = @(@($SignInsByIP.IP) + @($WorkloadIPs.IP) | Where-Object { $_ } | Select-Object -Unique)
                if ($AllIPs.Count -gt 0) {
                    try { $Geo = Get-CIPPGeoIPLocationBatch -IPs $AllIPs } catch { Write-LogMessage -API 'NHIRun' -message "Failed to geo-locate the addresses of $($Name): $($_.Exception.Message)" -tenant $TenantFilter -sev Warning }
                }
                $Guidance = try { Get-CIPPBecIPGuidance -TenantFilter $TenantFilter } catch { New-CIPPBecCollectorResult -Data @() -Error "IP guidance failed: $($_.Exception.Message)" }
                & $Mark 'IPGuidance' $Guidance
                $TechnicianIPs = @(if ($Item.RequestedFromIP) { [pscustomobject]@{ IP = [string]$Item.RequestedFromIP; By = [string]$Item.RequestedBy } })
                $IPVerdicts = @(Get-CIPPNhiIPVerdicts -SignIns $SignInsByIP -Events $WorkloadIPs -Baseline $State.Baseline -Geo $Geo -Guidance @($Guidance.Data) -TechnicianIPs $TechnicianIPs -FlaggedKeyIds $FlaggedKeyIds -ManagedIdentity:([bool]$Subject.IsManagedIdentity) -Heuristics $Heuristics)
                $VerdictOf = @{}
                foreach ($Verdict in $IPVerdicts) { $VerdictOf[[string]$Verdict.IP] = [string]$Verdict.Verdict }
                $RecentSignIns = & $Rows 'RecentSignIns'
                foreach ($Row in $RecentSignIns) { if ($Row.IPAddress) { $Row.IPVerdict = $VerdictOf[[string]$Row.IPAddress] } }
                foreach ($Row in $WorkloadIPs) { $Row | Add-Member -NotePropertyName 'IPVerdict' -NotePropertyValue $VerdictOf[[string]$Row.IP] -Force }

                $Changes = & $Rows 'Changes'
                $Consents = @($Changes | Where-Object { $_.Activity -eq 'Consent to application' -and $_.InitiatedByType -eq 'User' } | ForEach-Object { [pscustomobject]@{ ActivityDateTime = $_.ActivityDateTime; User = $_.InitiatedBy; ClientIP = $_.ClientIP } })
                # Dormant: the baseline was read in full, found no sign-in, and the app existed before it began.
                $BaselineMarker = $State.Completeness['Baseline']
                $Dormant = [bool]($BaselineMarker.Complete -and [int]$State.Baseline.Total -eq 0 -and $Subject.CreatedDateTime -and ([datetime]$Subject.CreatedDateTime).ToUniversalTime() -lt $baselineStart)

                $AllCompleteness = $State.Completeness
                foreach ($Marker in @($Completeness.Keys)) { $AllCompleteness[$Marker] = $Completeness[$Marker] }
                $Results = [PSCustomObject]@{
                    CaseId              = $CaseId
                    ServicePrincipalId  = $ServicePrincipalId
                    AppId               = $Subject.AppId
                    DisplayName         = $Name
                    Subject             = $Subject
                    Exposure            = $Exposure
                    Owners              = & $Rows 'Owners'
                    AppRoleAssignments  = & $Rows 'AppRoleAssignments'
                    DelegatedGrants     = & $Rows 'DelegatedGrants'
                    DirectoryRoles      = & $Rows 'DirectoryRoles'
                    RogueMatch          = $State.RogueMatch
                    RiskState           = $State.RiskState
                    RiskDetections      = & $Rows 'RiskDetections'
                    FlaggedKeyIds       = @($FlaggedKeyIds)
                    Changes             = $Changes
                    Consents            = $Consents
                    SignInSummary       = $State.SignInSummary
                    SignInsByIP         = $SignInsByIP
                    SignInsByCredential = & $Rows 'SignInsByCredential'
                    RecentSignIns       = $RecentSignIns
                    Baseline            = $State.Baseline
                    Dormant             = $Dormant
                    DelegatedSignIns    = & $Rows 'DelegatedSignIns'
                    DirectoryActions    = & $Rows 'DirectoryActions'
                    WorkloadActivity    = $Workload
                    WorkloadSummary     = $State.WorkloadSummary
                    WorkloadBaseline    = $State.WorkloadBaseline
                    IPVerdicts          = $IPVerdicts
                    IPTechnicians       = $TechnicianIPs
                    Completeness        = [pscustomobject]$AllCompleteness
                    AnalysisWindowDays  = $WindowDays
                    BaselineDays        = $BaselineDays
                    StartDate           = $startDate.ToString('o')
                    EndDate             = $endDate.ToString('o')
                    BaselineStart       = $baselineStart.ToString('o')
                    ExtractedAt         = (Get-Date)
                }
                $Score = Get-CIPPNhiScore -Results $Results -Heuristics $Heuristics
                $Results | Add-Member -NotePropertyName 'Score' -NotePropertyValue $Score -Force

                $null = Set-CIPPBecReport -Kind 'NHI' -TenantFilter $TenantFilter -CaseId $CaseId -Results $Results -Properties @{
                    ServicePrincipalId   = $ServicePrincipalId
                    AppId                = [string]$Subject.AppId
                    DisplayName          = $Name
                    ServicePrincipalType = [string]$Subject.ServicePrincipalType
                    Status               = 'Completed'
                    Score                = [int]$Score.Value
                    Level                = [string]$Score.Level
                    EvidenceLevel        = [string]$Score.EvidenceLevel
                    Impact               = [string]$Score.Impact
                    ExtractedAt          = $Results.ExtractedAt.ToUniversalTime().ToString('o')
                    IncompleteCount      = @($AllCompleteness.Values | Where-Object { -not $_.Complete }).Count
                }
                Write-LogMessage -API 'NHIRun' -message "NHI check run for $Name - level $($Score.Level) (evidence $($Score.EvidenceLevel), $($Score.Value); impact $($Score.Impact)) [case $CaseId]" -tenant $TenantFilter -sev 'Info'
                $StepMessage = "Level $($Score.Level): evidence $($Score.EvidenceLevel) ($($Score.Value)), impact $($Score.Impact)"
            }
        }
        & $Step $StepIndex 'succeeded' $StepMessage
        if ($IsLast) {
            Set-CIPPAsyncDeploymentStatus -JobId $CaseId -Name $ServicePrincipalId -Status 'succeeded' -Logs "Completed run $CaseId with $StepMessage"
            try { Set-CIPPBecRunState -CaseId $CaseId -Clear } catch { Write-Information "NHI: could not clear the run state of $CaseId`: $($_.Exception.Message)" }
        }
    } catch {
        $errMessage = Get-NormalizedError -message $_.Exception.Message
        $CippError = Get-CippException -Exception $_
        Write-LogMessage -API 'NHIRun' -message "NHI phase $Key failed for $($Name): $errMessage [case $CaseId]" -tenant $TenantFilter -sev 'Error' -LogData $CippError
        & $Step $StepIndex 'failed' $errMessage
        if ($IsLast -or $IsFirst) {
            # without the app (first phase) or the score (last) there is no case: the run failed
            try {
                $null = Set-CIPPBecReport -Kind 'NHI' -TenantFilter $TenantFilter -CaseId $CaseId -Properties @{
                    ServicePrincipalId = $ServicePrincipalId
                    Status             = 'Error'
                    ErrorMessage       = [string]$errMessage
                    ExtractedAt        = (Get-Date).ToUniversalTime().ToString('o')
                }
                Set-CIPPBecRunState -CaseId $CaseId -Clear
            } catch {
                Write-Information "NHI: could not record the failed run $CaseId`: $($_.Exception.Message)"
            }
            Set-CIPPAsyncDeploymentStatus -JobId $CaseId -Name $ServicePrincipalId -Status 'failed' -Logs $errMessage
        } else {
            # the later phases still run; this phase's checks show as failed on the case
            try {
                & $Mark $RunSteps[$StepIndex].Title ([pscustomobject]@{ Complete = $false; Error = $errMessage })
                & $Save @{}
            } catch {
                Write-Information "NHI: could not record the failed phase $Key of $CaseId`: $($_.Exception.Message)"
            }
        }
    } finally {
        Set-CippBecCaseContext -CaseId $null
    }
}
