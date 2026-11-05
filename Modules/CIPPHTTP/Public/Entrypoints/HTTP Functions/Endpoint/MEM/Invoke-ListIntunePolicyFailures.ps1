function Invoke-ListIntunePolicyFailures {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    .DESCRIPTION
        Lists the Intune configuration policies (settings catalog, device configuration profiles, administrative templates and endpoint security) that have at least one device in Error or Conflict, from the same report as Intune's Assignment failures view. With policyId it returns that policy's affected devices and its failing settings with error and conflict device counts, naming the other policies that set a conflicting setting where Intune exposes them.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    # Policy id (GUID) to drill into; omit for the list of failing policies
    $PolicyId = $Request.Query.policyId
    # The policy's PolicyBaseTypeName from the list; decides how conflicting policies are looked up
    $PolicyBaseTypeName = $Request.Query.policyBaseTypeName

    # Report shapes (probed 2026-10-30): the summary and per-policy device reports take a PolicyId filter;
    # getConfigurationSettingNonComplianceReport needs PolicyId, DeviceId and UserId together and has no
    # column naming the other policies, so conflict partners are the device's other policies in conflict on the
    # same setting path (classic profiles) or sharing a setting definition (settings catalog).
    $ReportBase = 'https://graph.microsoft.com/beta/deviceManagement/reports'
    $ClassicType = 'Microsoft.Management.Services.Api.DeviceConfiguration'
    $CatalogType = 'DeviceManagementConfigurationPolicy'
    $PolicyTypes = @(
        $ClassicType
        $CatalogType
        'DeviceConfigurationAdmxPolicy'
        'Microsoft.Management.Services.Api.DeviceManagementIntent'
    )
    $URLNames = @{
        $ClassicType                                               = 'deviceConfigurations'
        $CatalogType                                               = 'configurationPolicies'
        'DeviceConfigurationAdmxPolicy'                            = 'groupPolicyConfigurations'
        'Microsoft.Management.Services.Api.DeviceManagementIntent' = 'intents'
    }
    $TypeFilter = ($PolicyTypes | ForEach-Object { "(PolicyBaseTypeName eq '$_')" }) -join ' or '

    # Single-tenant page: the first render arrives before a tenant is picked, answer it with nothing to show
    if ([string]::IsNullOrWhiteSpace($TenantFilter) -or $TenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{
                StatusCode = [System.Net.HttpStatusCode]::OK
                Body       = @{ Results = @() }
            })
    }

    if ([string]::IsNullOrWhiteSpace($PolicyId)) {
        try {
            $Rows = Get-CIPPIntuneReportRows -TenantFilter $TenantFilter -Uri "$ReportBase/getConfigurationPolicyNonComplianceSummaryReport" -Filter "($TypeFilter)"
        } catch {
            return ([HttpResponseContext]@{
                    StatusCode = [System.Net.HttpStatusCode]::InternalServerError
                    Body       = @{ Results = "Failed to load the policy failure report: $((Get-CippException -Exception $_).NormalizedError)" }
                })
        }
        $Results = @(foreach ($Row in @($Rows)) {
            if (([int64]$Row.NumberOfErrorDevices + [int64]$Row.NumberOfConflictDevices) -le 0) { continue }
            [PSCustomObject]@{
                id                 = $Row.PolicyId
                displayName        = $Row.PolicyName
                PolicyTypeName     = $Row.UnifiedPolicyType_loc ?? $Row.UnifiedPolicyType
                platform           = $Row.UnifiedPolicyPlatformType_loc ?? $Row.UnifiedPolicyPlatformType
                errorDevices       = [int64]$Row.NumberOfErrorDevices
                conflictDevices    = [int64]$Row.NumberOfConflictDevices
                compliantDevices   = [int64]$Row.NumberOfCompliantDevices
                PolicyBaseTypeName = $Row.PolicyBaseTypeName
                URLName            = $URLNames[[string]$Row.PolicyBaseTypeName]
            }
        })
        return ([HttpResponseContext]@{
                StatusCode = [System.Net.HttpStatusCode]::OK
                Body       = @{ Results = @($Results) }
            })
    }

    # The id goes into an OData filter, so only a bare GUID is accepted
    $ParsedId = [guid]::Empty
    if (-not [guid]::TryParse("$PolicyId", [ref]$ParsedId)) {
        return ([HttpResponseContext]@{
                StatusCode = [System.Net.HttpStatusCode]::BadRequest
                Body       = @{ Results = 'policyId must be an Intune policy id.' }
            })
    }
    $PolicyGuid = $ParsedId.ToString()
    $Errors = [ordered]@{}

    $Devices = @()
    try {
        # The helper hands back its rows as one array object, so assign before filtering
        $DeviceRows = Get-CIPPIntuneReportRows -TenantFilter $TenantFilter -Uri "$ReportBase/getConfigurationPolicyNonComplianceReport" -Filter "(PolicyId eq '$PolicyGuid')" -OrderBy @('DeviceName')
        # PolicyStatusEnum comes back as a numeric code; ReportStatus carries the word, as on the device page
        $Devices = @(@($DeviceRows) | Where-Object { $_.ReportStatus -in @('Error', 'Conflict') })
    } catch {
        $Errors['devices'] = "Failed to load devices for policy $($PolicyGuid): $((Get-CippException -Exception $_).NormalizedError)"
    }

    $Settings = [ordered]@{}
    try {
        $SettingRows = Get-CIPPIntuneReportRows -TenantFilter $TenantFilter -Uri "$ReportBase/getConfigurationPolicySettingsDeviceSummaryReport" -Filter "(PolicyId eq '$PolicyGuid')" -OrderBy @('SettingName')
        foreach ($Row in @($SettingRows)) {
            if (([int64]$Row.NumberOfErrorDevices + [int64]$Row.NumberOfConflictDevices) -le 0) { continue }
            $Settings[[string]$Row.SettingName] = [PSCustomObject]@{
                settingName         = $Row.SettingName
                settingId           = $Row.SettingId
                errorDevices        = [int64]$Row.NumberOfErrorDevices
                conflictDevices     = [int64]$Row.NumberOfConflictDevices
                conflictingPolicies = [System.Collections.Generic.List[string]]::new()
            }
        }
    } catch {
        $Errors['settings'] = "Failed to load setting status for policy $($PolicyGuid): $((Get-CippException -Exception $_).NormalizedError)"
    }

    $AddConflict = {
        param($SettingName, $PolicyNames, [switch]$CountDevice)
        if (-not $Settings.Contains([string]$SettingName)) {
            $Settings[[string]$SettingName] = [PSCustomObject]@{
                settingName         = $SettingName
                settingId           = $null
                errorDevices        = 0
                conflictDevices     = 0
                conflictingPolicies = [System.Collections.Generic.List[string]]::new()
            }
        }
        # The setting report has no rows for classic profiles, so their per-device states supply the count
        if ($CountDevice -and -not $Settings[[string]$SettingName].settingId) { $Settings[[string]$SettingName].conflictDevices++ }
        foreach ($Name in @($PolicyNames)) {
            if ($Name -and $Settings[[string]$SettingName].conflictingPolicies -notcontains $Name) {
                $Settings[[string]$SettingName].conflictingPolicies.Add([string]$Name)
            }
        }
    }

    $ConflictDevices = @($Devices | Where-Object { $_.ReportStatus -eq 'Conflict' })
    if ($ConflictDevices.Count -gt 0) {
        # Bulk lookups that Graph refused; reported in errors instead of silently leaving conflicts unpaired
        $FailedLookups = [System.Collections.Generic.List[string]]::new()
        try {
            if ($PolicyBaseTypeName -eq $ClassicType) {
                # Classic profiles: settingStates.sources only names the policy itself, so pair by the other
                # profiles in conflict on the same device that report a conflict on the same setting path
                # The report repeats a device per user context; its states are per device
                $StateRequests = foreach ($DeviceId in @($ConflictDevices.IntuneDeviceId | Sort-Object -Unique)) {
                    [PSCustomObject]@{ id = $DeviceId; method = 'GET'; url = "/deviceManagement/managedDevices/$DeviceId/deviceConfigurationStates" }
                }
                $OtherNames = @{}
                $Requests = [System.Collections.Generic.List[object]]::new()
                foreach ($Response in @(New-GraphBulkRequest -tenantid $TenantFilter -Requests @($StateRequests))) {
                    if ([int]$Response.status -ge 300) { $FailedLookups.Add("$($Response.id): $($Response.body.error.message)"); continue }
                    $PolicyIds = [System.Collections.Generic.List[string]]::new()
                    $PolicyIds.Add($PolicyGuid)
                    foreach ($State in @($Response.body.value | Where-Object { $_.state -eq 'conflict' -and $_.id -ne $PolicyGuid })) {
                        $OtherNames[[string]$State.id] = $State.displayName
                        $PolicyIds.Add([string]$State.id)
                    }
                    foreach ($Id in $PolicyIds) {
                        $Requests.Add([PSCustomObject]@{
                                id     = "$($Response.id)/$Id"
                                method = 'GET'
                                url    = "/deviceManagement/managedDevices/$($Response.id)/deviceConfigurationStates/$Id/settingStates"
                            })
                    }
                }
                $SettingResponses = foreach ($Response in @(New-GraphBulkRequest -tenantid $TenantFilter -Requests @($Requests))) {
                    if ([int]$Response.status -ge 300) { $FailedLookups.Add("$($Response.id): $($Response.body.error.message)"); continue }
                    $Response
                }
                foreach ($Device in @($SettingResponses | Group-Object -Property { ([string]$_.id -split '/')[0] })) {
                    $Own = @($Device.Group | Where-Object { $_.id -eq "$($Device.Name)/$PolicyGuid" } | ForEach-Object { $_.body.value } | Where-Object { $_.state -eq 'conflict' } | Sort-Object -Property setting -Unique)
                    foreach ($State in $Own) {
                        $Partners = foreach ($Response in @($Device.Group | Where-Object { $_.id -ne "$($Device.Name)/$PolicyGuid" })) {
                            if (@($Response.body.value | Where-Object { $_.state -eq 'conflict' -and $_.setting -eq $State.setting }).Count -gt 0) {
                                $OtherNames[([string]$Response.id -split '/')[1]]
                            }
                        }
                        # settingName reads Windows10GeneralConfiguration.DefenderScanMaxCpu; keep the setting part
                        $SettingName = if ($State.settingName) { $State.settingName -replace '^.*\.', '' } else { $State.setting }
                        & $AddConflict $SettingName @($Partners) -CountDevice
                    }
                }
            } elseif ($PolicyBaseTypeName -eq $CatalogType) {
                # Settings catalog: no source list from Intune. Pair by the other catalog policies applied to the
                # device whose settings use the same definition as a failing setting of this policy.
                # ponytail: exact for catalog-vs-catalog only; a collision with a classic profile stays unpaired.
                $PolicySettings = @{}
                $GetDefinitionIds = {
                    param($Ids)
                    $Missing = @($Ids | Where-Object { -not $PolicySettings.ContainsKey([string]$_) })
                    if ($Missing.Count -gt 0) {
                        $Requests = foreach ($Id in $Missing) {
                            [PSCustomObject]@{ id = $Id; method = 'GET'; url = "/deviceManagement/configurationPolicies('$Id')?`$expand=settings(`$expand=settingDefinitions)&`$select=id,name" }
                        }
                        foreach ($Response in @(New-GraphBulkRequest -tenantid $TenantFilter -Requests @($Requests))) {
                            if ([int]$Response.status -ge 300) { $FailedLookups.Add("$($Response.id): $($Response.body.error.message)"); continue }
                            # The setting report names settings by their definition display name
                            $DisplayNames = @{}
                            foreach ($Definition in @($Response.body.settings.settingDefinitions)) {
                                $DisplayNames[[string]$Definition.id] = $Definition.displayName
                            }
                            $PolicySettings[[string]$Response.id] = [PSCustomObject]@{
                                name          = $Response.body.name
                                definitionIds = @($Response.body.settings | ForEach-Object { $_.settingInstance.settingDefinitionId })
                                displayNames  = $DisplayNames
                            }
                        }
                    }
                }
                & $GetDefinitionIds @($PolicyGuid)
                $OwnDefinitions = @($PolicySettings[$PolicyGuid].definitionIds)

                foreach ($Device in $ConflictDevices) {
                    $FailingRows = Get-CIPPIntuneReportRows -TenantFilter $TenantFilter -Uri "$ReportBase/getConfigurationSettingNonComplianceReport" -Filter "(PolicyId eq '$PolicyGuid') and (DeviceId eq '$($Device.IntuneDeviceId)') and (UserId eq '$($Device.UserId)')" -OrderBy @('SettingName')
                    $FailingNames = @(@($FailingRows) | ForEach-Object { [string]$_.SettingName })
                    $AppliedRows = Get-CIPPIntuneReportRows -TenantFilter $TenantFilter -Uri "$ReportBase/getConfigurationPoliciesReportForDevice" -Filter "(PolicyBaseTypeName eq '$CatalogType') and (IntuneDeviceId eq '$($Device.IntuneDeviceId)')"
                    $Applied = @(@($AppliedRows) | ForEach-Object { [string]$_.PolicyId } | Where-Object { $_ -and $_ -ne $PolicyGuid } | Select-Object -Unique)
                    & $GetDefinitionIds $Applied
                    foreach ($OtherId in $Applied) {
                        $Other = $PolicySettings[$OtherId]
                        if (-not $Other) { continue }
                        foreach ($Shared in @($OwnDefinitions | Where-Object { $_ -in $Other.definitionIds })) {
                            # the report names the setting by its definition display name; fall back to the id itself
                            $DisplayName = $PolicySettings[$PolicyGuid].displayNames[[string]$Shared]
                            $Name = @($FailingNames | Where-Object { $_ -eq $DisplayName -or $_ -eq $Shared }) | Select-Object -First 1
                            & $AddConflict ($Name ?? $DisplayName ?? $Shared) @($Other.name)
                        }
                    }
                }
            }
        } catch {
            $Errors['conflicts'] = "Failed to resolve conflicting policies: $((Get-CippException -Exception $_).NormalizedError)"
        }
        if ($FailedLookups.Count -gt 0 -and -not $Errors.Contains('conflicts')) {
            $Errors['conflicts'] = "Failed $($FailedLookups.Count) conflict lookup(s): $(@($FailedLookups | Select-Object -First 3) -join '; ')"
        }
    }

    $StatusCode = Get-CippBulkStatusCode -Total 3 -Failed $Errors.Count
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{
                Results = [ordered]@{
                    settings = @($Settings.Values)
                    devices  = @($Devices)
                    errors   = $Errors
                }
            }
        })
}
