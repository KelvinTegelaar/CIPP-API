function Invoke-ExecCompareCAPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.ConditionalAccess.Read
    .DESCRIPTION
        Compares a Conditional Access policy against another policy or a stored CA template and returns the differences setting by setting. Users, groups and locations are compared by display name, the same way the Conditional Access drift standard compares them.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $SourceA = $Request.Body.sourceA
    $SourceB = $Request.Body.sourceB

    if (-not $SourceA -or -not $SourceB) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Failed to compare policies: Both sourceA and sourceB are required' }
            })
    }

    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
    if ($AllowedTenants -notcontains 'AllTenants') {
        foreach ($SourceTenant in @($SourceA.tenantFilter, $SourceB.tenantFilter)) {
            if ($SourceTenant -and -not (Get-Tenants -TenantFilter $SourceTenant)) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::Forbidden
                        Body       = @{ Results = 'Failed to compare policies: Access to this tenant is not allowed' }
                    })
            }
        }
    }

    try {
        $Resolved = foreach ($Entry in @(@{ Label = 'Source A'; Source = $SourceA }, @{ Label = 'Source B'; Source = $SourceB })) {
            $Label = $Entry.Label
            $Source = $Entry.Source
            if ($Source.type -eq 'template') {
                if (-not $Source.templateGuid) {
                    throw [System.ArgumentException]::new("$Label : templateGuid is required for template sources")
                }
                $Table = Get-CippTable -tablename 'templates'
                $SafeGuid = ConvertTo-CIPPODataFilterValue -Value $Source.templateGuid -Type String
                $JSON = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CATemplate' and (RowKey eq '$SafeGuid' or GUID eq '$SafeGuid')")[0].JSON
                if (-not $JSON) {
                    throw [System.Management.Automation.ItemNotFoundException]::new("$Label : CA template '$($Source.templateGuid)' no longer exists in the template library")
                }
                # Resolved for the tenant on the other side, so %variables% are not reported as differences.
                if ($Source.tenantFilter) { $JSON = Get-CIPPTextReplacement -TenantFilter $Source.tenantFilter -Text $JSON -EscapeForJson }
                $Policy = $JSON | ConvertFrom-Json -Depth 100

                # Templates hold the source tenant's location ids; the template's own LocationInfo names them.
                if ($Policy.conditions.locations) {
                    $LocNameById = @{}
                    foreach ($Location in @($Policy.LocationInfo)) { if ($Location.id -and $Location.displayName) { $LocNameById[$Location.id] = $Location.displayName } }
                    foreach ($LocDir in 'includeLocations', 'excludeLocations') {
                        if ($Policy.conditions.locations.$LocDir) {
                            $Policy.conditions.locations.$LocDir = @(foreach ($Id in $Policy.conditions.locations.$LocDir) { $LocNameById[$Id] ?? $Id })
                        }
                    }
                }
                @{ Object = $Policy; Label = "$($Policy.displayName) (Template)" }

            } elseif ($Source.type -eq 'tenantPolicy') {
                if (-not $Source.tenantFilter -or -not $Source.policyId) {
                    throw [System.ArgumentException]::new("$Label : tenantFilter and policyId are required for tenant policy sources")
                }
                $SafeId = [uri]::EscapeDataString($Source.policyId)
                try {
                    $Policy = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$SafeId" -tenantid $Source.tenantFilter
                } catch {
                    if ($_.Exception.Message -match 'NotFound|does not exist') {
                        throw [System.Management.Automation.ItemNotFoundException]::new("$Label : Policy '$($Source.policyId)' not found in tenant '$($Source.tenantFilter)'")
                    }
                    throw
                }
                # The same conversion the drift standard runs, so ids become display names on both sides.
                $Object = New-CIPPCATemplate -TenantFilter $Source.tenantFilter -JSON $Policy -Headers $Headers -APIName $APIName | ConvertFrom-Json -Depth 100
                @{ Object = $Object; Label = "$($Policy.displayName) ($($Source.tenantFilter))" }

            } else {
                throw [System.ArgumentException]::new("$Label : Invalid source type '$($Source.type)'. Must be 'template' or 'tenantPolicy'")
            }
        }

        $ComparisonResults = @(Compare-CIPPIntuneObject -ReferenceObject $Resolved[0].Object -DifferenceObject $Resolved[1].Object -CompareType 'ca' | Where-Object { $null -ne $_ })

        Write-LogMessage -headers $Headers -API $APIName -message "Compared Conditional Access policies: $($Resolved[0].Label) vs $($Resolved[1].Label) - $($ComparisonResults.Count) differences found" -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
        $Body = @{
            Results      = $ComparisonResults
            sourceALabel = $Resolved[0].Label
            sourceBLabel = $Resolved[1].Label
            sourceAData  = $Resolved[0].Object
            sourceBData  = $Resolved[1].Object
            identical    = ($ComparisonResults.Count -eq 0)
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to compare Conditional Access policies: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
        $Body = @{ Results = "Failed to compare policies: $($ErrorMessage.NormalizedError)" }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = ConvertTo-Json -Depth 100 -InputObject $Body
        })
}
