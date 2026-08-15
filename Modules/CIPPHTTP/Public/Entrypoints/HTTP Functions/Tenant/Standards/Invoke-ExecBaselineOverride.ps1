function Invoke-ExecBaselineOverride {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Baselines.ReadWrite
    .DESCRIPTION
        Creates or removes a tenant-scoped delta (design doc §4.1) overriding one standard for
        one tenant. Presence is the override: the delta's expectedValue (the configured variable
        values) fully replaces what the baselines apply. The resolved row's §4.2 columns are
        updated immediately so the UI reflects the new effective configuration; the engine
        enforces it on the next run.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    try {
        $Action = $Request.Body.action
        $TenantFilter = $Request.Body.tenantFilter
        $Standard = $Request.Body.standard
        if (-not ($Action -and $TenantFilter -and $Standard)) {
            throw 'Provide action, tenantFilter, and standard.'
        }

        $User = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
        $DeltaTable = Get-CippTable -tablename 'Baselines'
        $ResolvedTable = Get-CippTable -tablename 'BaselineAlignment'
        $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter
        $SafeStandard = ConvertTo-CIPPODataFilterValue -Value $Standard
        # Ad-hoc tenant delta: templateId is empty per the design doc; the RK's last segment
        # is the literal 'adhoc'. '#' is not legal in Azure Table keys.
        $DeltaRowKey = 'tenant_{0}-{1}-adhoc' -f $TenantFilter, ($Standard -replace '#', '~')

        $ResolvedEntity = Get-CIPPAzDataTableEntity @ResolvedTable -Filter "PartitionKey eq '$SafeTenant' and StandardName eq '$SafeStandard'"
        if (-not $ResolvedEntity) {
            $ResolvedEntity = Get-CIPPAzDataTableEntity @ResolvedTable -Filter "PartitionKey eq '$SafeTenant' and RowKey eq '$SafeStandard'"
        }
        $ResolvedEntity = $ResolvedEntity | Select-Object -First 1
        $Set = { param($Name, $Value) $ResolvedEntity | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }

        switch ($Action) {
            'createOverride' {
                $Variables = $Request.Body.variables ?? [PSCustomObject]@{}
                $DeltaTable.Force = $true
                Add-CIPPAzDataTableEntity @DeltaTable -Entity @{
                    PartitionKey     = 'standardItem'
                    RowKey           = "$DeltaRowKey"
                    standardName     = "$Standard"
                    templateId       = ''
                    scope            = 'tenant'
                    scopeId          = "$TenantFilter"
                    stage            = 1
                    expectedValue    = (ConvertTo-Json -Compress -Depth 100 -InputObject $Variables)
                    remediateEnabled = $true
                    alertEnabled     = $true
                    alertOnRemediate = $false
                    rolloutId        = ''
                    updatedBy        = "$User"
                    updatedAt        = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())
                }

                # Reflect the override on the resolved row right away. The definition's
                # expected template renders by splicing the override's variable values into
                # the serialized template ("%var%" as an exact JSON value keeps its type),
                # then Get-CIPPTextReplacement resolves tenant tokens - one %var% syntax.
                if ($ResolvedEntity) {
                    $Definition = Get-CIPPBaselineDefinition -Name (($Standard -split '#')[0])
                    $Expected = if ($Definition.expected) {
                        $ExpectedJson = ConvertTo-Json -Compress -Depth 100 -InputObject $Definition.expected
                        foreach ($Variable in $Variables.PSObject.Properties) {
                            $Token = '%{0}%' -f $Variable.Name
                            $EncodedValue = ConvertTo-Json -Compress -Depth 100 -InputObject $Variable.Value
                            $ExpectedJson = $ExpectedJson.Replace(('"{0}"' -f $Token), $EncodedValue)
                            $ExpectedJson = $ExpectedJson.Replace($Token, "$($Variable.Value)")
                        }
                        $ExpectedJson = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $ExpectedJson -EscapeForJson
                        $ExpectedJson | ConvertFrom-Json
                    } elseif ($ResolvedEntity.ExpectedValue) {
                        $ResolvedEntity.ExpectedValue | ConvertFrom-Json
                    } else { $null }
                    $Inheritance = @()
                    if ($ResolvedEntity.Inheritance) {
                        $Inheritance = @(($ResolvedEntity.Inheritance | ConvertFrom-Json) | Where-Object { $_ -and $_.templateName -ne 'Tenant Override' } | ForEach-Object {
                                $_.effective = $false; $_
                            })
                    }
                    $Inheritance += [PSCustomObject]@{
                        templateName = 'Tenant Override'
                        assignedTo   = $TenantFilter
                        value        = $Expected
                        effective    = $true
                    }
                    & $Set 'ExpectedValue' (ConvertTo-Json -Compress -Depth 100 -InputObject $Expected)
                    & $Set 'SourceScope' 'tenant'
                    & $Set 'SourceTemplate' 'Tenant Override'
                    & $Set 'Inheritance' (ConvertTo-Json -Compress -Depth 100 -InputObject $Inheritance)
                    $ResolvedTable.Force = $true
                    Add-CIPPAzDataTableEntity @ResolvedTable -Entity $ResolvedEntity
                }
                $Message = "Created a tenant override of $Standard for $TenantFilter."
                $null = Add-CIPPBaselineHistoryEvent -TenantFilter $TenantFilter -Standard $Standard -Mode 'triage' -TriggeredBy $User -Outcome 'Override Created' -Detail 'Created a tenant override - its configured values replace what the baselines apply'
            }
            'deleteOverride' {
                $SafeDeltaRowKey = ConvertTo-CIPPODataFilterValue -Value $DeltaRowKey
                $DeltaEntity = Get-CIPPAzDataTableEntity @DeltaTable -Filter "PartitionKey eq 'standardItem' and RowKey eq '$SafeDeltaRowKey'"
                if ($DeltaEntity) {
                    Remove-CIPPAzDataTableEntity -Force @DeltaTable -Entity $DeltaEntity
                }

                # An ad-hoc-only resolved row (empty TemplateId) has nothing to fall back to -
                # delete it so the standard disappears from the view with its override.
                if ($ResolvedEntity -and -not $ResolvedEntity.TemplateId) {
                    Remove-CIPPAzDataTableEntity -Force @ResolvedTable -Entity $ResolvedEntity
                    $ResolvedEntity = $null
                }
                # Fall back to the widest remaining tier on the resolved row.
                if ($ResolvedEntity -and $ResolvedEntity.Inheritance) {
                    $Inheritance = @(($ResolvedEntity.Inheritance | ConvertFrom-Json) | Where-Object { $_ -and $_.templateName -ne 'Tenant Override' })
                    if ($Inheritance.Count -gt 0) {
                        foreach ($Tier in $Inheritance) { $Tier.effective = $false }
                        $Inheritance[-1].effective = $true
                        & $Set 'ExpectedValue' (ConvertTo-Json -Compress -Depth 100 -InputObject $Inheritance[-1].value)
                        & $Set 'SourceScope' $(if ($Inheritance.Count -gt 1) { 'group' } else { 'allTenants' })
                        & $Set 'SourceTemplate' "$($Inheritance[-1].templateName)"
                        & $Set 'Inheritance' (ConvertTo-Json -Compress -Depth 100 -InputObject $Inheritance)
                        $ResolvedTable.Force = $true
                        Add-CIPPAzDataTableEntity @ResolvedTable -Entity $ResolvedEntity
                    }
                }
                $Message = "Removed the tenant override of $Standard for $TenantFilter - it falls back to the inherited configuration."
                $null = Add-CIPPBaselineHistoryEvent -TenantFilter $TenantFilter -Standard $Standard -Mode 'triage' -TriggeredBy $User -Outcome 'Override Removed' -Detail 'Removed the tenant override - the standard falls back to the inherited configuration'
            }
            default {
                throw "Unknown action '$Action'. Use createOverride or deleteOverride."
            }
        }

        Write-LogMessage -headers $Request.Headers -API $APIName -message $Message -Sev 'Info'
        $Results = [pscustomobject]@{ Results = $Message }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to update override: $($_.Exception.Message)" -Sev 'Error'
        $Results = [pscustomobject]@{ Results = "Failed to update override: $($_.Exception.Message)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
