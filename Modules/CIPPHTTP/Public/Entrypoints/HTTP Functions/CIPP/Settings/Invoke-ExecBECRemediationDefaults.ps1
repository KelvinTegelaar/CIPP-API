function Invoke-ExecBECRemediationDefaults {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    .SYNOPSIS
        Gets or sets which BEC containment actions are selected by default.
    .DESCRIPTION
        GET with List=true returns the containment catalog (Id, Label, Description, Impact, DefaultSelected) with the instance-wide defaults applied. POST with DefaultActions saves the action ids that start selected in the BEC containment drawer and run when ExecBECRemediate is called without Actions.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $StatusCode = [HttpStatusCode]::OK

    try {
        $Catalog = Get-CIPPBecContainmentActions
        if ($Request.Query.List) {
            $Results = @($Catalog | Select-Object Id, Label, Description, Impact, DefaultSelected)
        } else {
            # Containment action ids (ListBECRemediationActions) that start selected
            $DefaultActions = @($Request.Body.DefaultActions | ForEach-Object { if ($_ -and $_.PSObject.Properties['value']) { $_.value } else { $_ } } | Where-Object { $_ })
            if ($DefaultActions.Count -eq 0) {
                $StatusCode = [HttpStatusCode]::BadRequest
                throw 'Select at least one default action'
            }
            $Unknown = @($DefaultActions | Where-Object { $_ -notin $Catalog.Id })
            if ($Unknown.Count -gt 0) {
                $StatusCode = [HttpStatusCode]::BadRequest
                throw "Unknown containment action(s): $($Unknown -join ', ')"
            }
            $Table = Get-CIPPTable -TableName Settings
            Add-CIPPAzDataTableEntity @Table -Entity @{
                PartitionKey   = 'BecRemediation'
                RowKey         = 'Defaults'
                DefaultActions = [string](ConvertTo-Json -InputObject @($DefaultActions) -Compress)
            } -Force | Out-Null
            Write-LogMessage -headers $Headers -API $APIName -message "Set BEC remediation defaults: $($DefaultActions -join ', ')" -Sev 'Info'
            $Results = 'Saved the BEC remediation defaults'
        }
    } catch {
        if ($StatusCode -eq [HttpStatusCode]::OK) { $StatusCode = [HttpStatusCode]::InternalServerError }
        $Results = "Failed to set BEC remediation defaults: $($_.Exception.Message)"
        Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Error'
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Results }
        })
}
