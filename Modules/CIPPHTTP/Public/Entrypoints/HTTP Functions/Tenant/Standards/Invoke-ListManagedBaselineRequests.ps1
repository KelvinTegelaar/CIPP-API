function Invoke-ListManagedBaselineRequests {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Baselines.Read
    .DESCRIPTION
        Lists the custom baselines requested from CyberDrain through the Managed Baselines integration, with their status. With requestId it returns exactly what was sent to CyberDrain for that request. With requestId and includeBaseline it returns the baseline CyberDrain delivered, in the shape the baseline editor loads.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    try {
        $Table = Get-CippTable -tablename 'ManagedBaselineRequests'
        $RequestId = "$($Request.Query.requestId)"

        if ($RequestId) {
            $SafeId = ConvertTo-CIPPODataFilterValue -Value $RequestId
            $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'request' and RowKey eq '$SafeId'" |
                Select-CippAllowedTenantData -TenantProperty 'TenantFilter' | Select-Object -First 1
            if (-not $Row) { throw [System.Management.Automation.ItemNotFoundException]::new('That request was not found.') }

            if ("$($Request.Query.includeBaseline)" -eq 'true') {
                $Package = (Invoke-ManagedBaselinesRequest -Path 'PartnerRequest' -Query @{ requestId = $RequestId }).package
                if (-not $Package.Baseline) {
                    throw [System.ArgumentException]::new('CyberDrain has not delivered a baseline for this request yet.')
                }
                $Tenant = Get-Tenants -TenantFilter $Row.TenantFilter | Select-Object -First 1
                $TenantLabel = "$($Row.TenantFilter)"
                if ($Tenant.displayName) { $TenantLabel = '{0} ({1})' -f $Tenant.displayName, $Row.TenantFilter }
                $TenantOption = [PSCustomObject]@{ value = "$($Row.TenantFilter)"; label = $TenantLabel; type = 'Tenant' }

                # Aligning nothing with the delivery gives the same cleaned stages an Align would write.
                $Definitions = @(Get-CIPPBaselineDefinition)
                $Start = [PSCustomObject]@{
                    templateName = "$($Package.Baseline.templateName)"
                    description  = "$($Package.Baseline.description)"
                    assignments  = @($TenantOption)
                    stages       = @()
                }
                $Plan = Merge-CIPPManagedBaseline -Local $Start -Remote $Package.Baseline -Mode 'align' -Definitions $Definitions

                # The editor shows a template picker by its label; the name travels with the delivery.
                $TemplateNames = @{}
                foreach ($Reference in @($Package.Baseline.referencedTemplates)) {
                    if ($Reference.guid) { $TemplateNames["$($Reference.guid)"] = "$($Reference.displayName ?? $Reference.guid)" }
                }
                $PickerVariables = @{}
                foreach ($Definition in $Definitions) {
                    if ($Definition.instanceIdentity -and "$($Definition.variables.$($Definition.instanceIdentity).type)" -in @('autoComplete', 'select')) {
                        $PickerVariables["$($Definition.name)"] = "$($Definition.instanceIdentity)"
                    }
                }
                $Stages = foreach ($Stage in @($Plan.Payload.stages)) {
                    $Configs = foreach ($Config in @($Stage.standards)) {
                        $Variable = $PickerVariables["$($Config.standard)"]
                        if ($Variable -and $Config.variables.PSObject.Properties[$Variable]) {
                            $TemplateId = "$($Config.variables.$Variable.value ?? $Config.variables.$Variable)"
                            if ($TemplateId) {
                                $Config.variables.$Variable = [PSCustomObject]@{ label = ($TemplateNames[$TemplateId] ?? $TemplateId); value = $TemplateId }
                            }
                        }
                        $Config
                    }
                    [PSCustomObject]@{
                        name            = $Stage.name
                        logic           = $Stage.logic
                        conditions      = @($Stage.conditions)
                        conditionGroups = @($Stage.conditionGroups)
                        standards       = @(foreach ($Config in @($Configs)) { $Config.instance })
                        standardsConfig = @($Configs)
                    }
                }
                $Body = @{
                    Results = [PSCustomObject]@{
                        GUID                 = "managed-request-$RequestId"
                        templateName         = $Start.templateName
                        description          = $Start.description
                        assignments          = @($TenantOption)
                        assignedTenants      = @("$($Row.TenantFilter)")
                        exclusions           = @()
                        excludedTenants      = @()
                        alertEmails          = ''
                        alertWebhookUrl      = ''
                        disableAlerts        = $false
                        disableScheduledRuns = $false
                        stages               = @($Stages)
                        managedRequestId     = $RequestId
                        managedVersion       = "$($Package.version)"
                    }
                }
            } else {
                $Body = @{ Results = (Get-CIPPManagedBaselineRequestBody -Row $Row) }
            }
        } else {
            $Rows = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'request'" | Select-CippAllowedTenantData -TenantProperty 'TenantFilter')
            $Baselines = @{}
            if ($Rows.Count -gt 0) {
                $RolloutTable = Get-CippTable -tablename 'BaselineRollouts'
                foreach ($Rollout in (Get-CIPPAzDataTableEntity @RolloutTable -Filter "PartitionKey eq 'rollout'")) {
                    if ($Rollout.ManagedRequestId) { $Baselines["$($Rollout.ManagedRequestId)"] = $Rollout }
                }
            }
            $CollectionTable = Get-CippTable -tablename 'ManagedBaselineCollection'
            $Results = foreach ($Row in ($Rows | Sort-Object -Property { [int64]($_.CreatedAt ?? 0) } -Descending)) {
                $Baseline = $Baselines["$($Row.RowKey)"]
                $Status = [System.Collections.Generic.List[string]]::new()
                $Status.Add("$($Row.Status)")
                if ($Baseline -and $Row.RemoteVersion -and "$($Baseline.ManagedVersion)" -ne "$($Row.RemoteVersion)") {
                    $Status.Add('Update available')
                }
                $Collected = $null
                if ("$($Row.Status)" -eq 'Waiting on data collection') {
                    $SafeRow = ConvertTo-CIPPODataFilterValue -Value $Row.RowKey
                    $Collected = @(Get-CIPPAzDataTableEntity @CollectionTable -Filter "PartitionKey eq '$SafeRow'" -Property RowKey).Count
                }
                $Frameworks = @()
                if ($Row.Frameworks) {
                    try { $Frameworks = @(ConvertFrom-Json -InputObject "$($Row.Frameworks)" -ErrorAction Stop) } catch { $Frameworks = @() }
                }
                [PSCustomObject]@{
                    requestId           = $Row.RowKey
                    tenantFilter        = $Row.TenantFilter
                    requestedDateTime   = $Row.CreatedAt
                    requestedBy         = $Row.CreatedBy
                    industry            = $Row.Industry
                    clientSize          = $Row.ClientSize
                    wants               = $Row.Wants
                    exceptions          = $Row.Exceptions
                    frameworks          = $Frameworks
                    comments            = $Row.Comments
                    status              = @($Status)
                    ready               = ("$($Row.Status)" -eq 'Completed - ready to confirm')
                    sentDateTime        = $Row.SubmittedAt
                    lastCheckedDateTime = $Row.LastChecked
                    engineerNotes       = $Row.EngineerNotes
                    error               = $Row.Error
                    collected           = $Collected
                    total               = $Row.Total
                    baselineGuid        = $Baseline.RowKey
                    baselineName        = $Baseline.templateName
                }
            }
            $Body = @{
                Results = @($Results)
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to list managed baseline requests: $($_.Exception.Message)" -Sev 'Error'
        $Body = @{ Results = "Failed to list managed baseline requests: $($_.Exception.Message)" }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
