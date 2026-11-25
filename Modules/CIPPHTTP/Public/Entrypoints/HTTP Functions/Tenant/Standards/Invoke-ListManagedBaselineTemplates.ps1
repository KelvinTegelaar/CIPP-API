function Invoke-ListManagedBaselineTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Baselines.Read
    .DESCRIPTION
        Lists the baselines CyberDrain publishes through the Managed Baselines integration, marking the ones already added to this instance and the ones CyberDrain has updated since.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    try {
        # Invoke-RestMethod hands a JSON array over as one object; assigning it first unwraps it.
        $Reply = Invoke-ManagedBaselinesRequest -Path 'templates'
        $Catalog = @($Reply)

        $Added = @{}
        $RolloutTable = Get-CippTable -tablename 'BaselineRollouts'
        foreach ($Row in (Get-CIPPAzDataTableEntity @RolloutTable -Filter "PartitionKey eq 'rollout'")) {
            if ($Row.ManagedId -and "$($Row.ManagedKind)" -ne 'custom') { $Added["$($Row.ManagedId)"] = $Row }
        }
        $Labels = @{}
        foreach ($Definition in @(Get-CIPPBaselineDefinition)) {
            if ($Definition.name) { $Labels["$($Definition.name)"] = "$($Definition.label ?? $Definition.name)" }
        }

        $Rows = foreach ($Entry in $Catalog) {
            $Existing = $Added["$($Entry.id)"]
            $Status = [System.Collections.Generic.List[string]]::new()
            if ($Existing) {
                $Status.Add('Imported')
                if ("$($Existing.ManagedVersion)" -ne "$($Entry.version)") { $Status.Add('Update available') }
            }
            [PSCustomObject]@{
                id              = $Entry.id
                name            = $Entry.name
                description     = $Entry.description
                tags            = @($Entry.tags)
                standardsCount  = $Entry.standardsCount
                version         = $Entry.version
                updatedAt       = $Entry.updatedAt
                status          = @($Status)
                imported        = [bool]$Existing
                baselineGuid    = $Existing.RowKey
                importedVersion = $Existing.ManagedVersion
                stages          = @(foreach ($Stage in @($Entry.stages)) {
                        [PSCustomObject]@{
                            name      = $Stage.name
                            standards = @(foreach ($Standard in @($Stage.standards)) { $Labels["$Standard"] ?? "$Standard" })
                        }
                    })
            }
        }
        $Body = @{
            Results = @($Rows)
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to list managed baselines: $($_.Exception.Message)" -Sev 'Error'
        $Body = @{ Results = "Failed to list managed baselines: $($_.Exception.Message)" }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
