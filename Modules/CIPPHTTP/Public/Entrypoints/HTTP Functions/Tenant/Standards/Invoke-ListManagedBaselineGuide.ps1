function Invoke-ListManagedBaselineGuide {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Baselines.Read
    .DESCRIPTION
        Returns the implementation guide CyberDrain ships with a managed baseline: an overview, and per stage the guidance and the communication examples. Ask with id (a published baseline), requestId (a custom baseline request) or GUID (a managed baseline already added to this instance).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    try {
        $Id = "$($Request.Query.id)"
        $RequestId = "$($Request.Query.requestId)"
        $ImportedVersion = $null

        if ($Request.Query.GUID) {
            $RolloutTable = Get-CippTable -tablename 'BaselineRollouts'
            $SafeGuid = ConvertTo-CIPPODataFilterValue -Value "$($Request.Query.GUID)"
            $Row = Get-CIPPAzDataTableEntity @RolloutTable -Filter "PartitionKey eq 'rollout' and RowKey eq '$SafeGuid'" | Select-Object -First 1
            if (-not $Row.ManagedId) {
                throw [System.ArgumentException]::new('This baseline is not managed by CyberDrain.')
            }
            $ImportedVersion = "$($Row.ManagedVersion)"
            if ("$($Row.ManagedKind)" -eq 'custom') { $RequestId = "$($Row.ManagedRequestId)" } else { $Id = "$($Row.ManagedId)" }
        }

        $Package = if ($RequestId) {
            (Invoke-ManagedBaselinesRequest -Path 'PartnerRequest' -Query @{ requestId = $RequestId }).package
        } elseif ($Id) {
            Invoke-ManagedBaselinesRequest -Path 'PartnerTemplate' -Query @{ id = $Id }
        } else {
            throw [System.ArgumentException]::new('Choose a managed baseline to read the guide for.')
        }
        if (-not $Package.Baseline) { throw 'CyberDrain returned no baseline.' }

        # The baseline's own stages set the order; a stage without guidance still shows.
        $StageGuides = @{}
        foreach ($StageGuide in @($Package.Guide.stages)) {
            if ($StageGuide.name) { $StageGuides["$($StageGuide.name)"] = $StageGuide }
        }
        $Stages = foreach ($Stage in @($Package.Baseline.stages)) {
            $StageGuide = $StageGuides["$($Stage.name)"]
            [PSCustomObject]@{
                name           = "$($Stage.name)"
                guide          = "$($StageGuide.guide)"
                communications = @(foreach ($Example in @($StageGuide.communications)) {
                        if (-not $Example.body) { continue }
                        [PSCustomObject]@{
                            title    = "$($Example.title)"
                            audience = "$($Example.audience)"
                            body     = "$($Example.body)"
                        }
                    })
            }
        }

        $Body = @{
            Results  = [PSCustomObject]@{
                name            = "$($Package.Baseline.templateName)"
                version         = "$($Package.version)"
                importedVersion = $ImportedVersion
                overview        = "$($Package.Guide.overview)"
                stages          = @($Stages)
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to read the managed baseline guide: $($_.Exception.Message)" -Sev 'Error'
        $Body = @{ Results = "Failed to read the managed baseline guide: $($_.Exception.Message)" }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
