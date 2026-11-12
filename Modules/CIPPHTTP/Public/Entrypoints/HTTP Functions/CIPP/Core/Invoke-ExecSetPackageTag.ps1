function Invoke-ExecSetPackageTag {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $Table = Get-CippTable -tablename 'templates'

    $StatusCode = [HttpStatusCode]::OK
    try {
        $GUIDS = $Request.body.GUID
        $Remove = $Request.body.Remove

        if ($Remove -eq $true) {
            # Remove package tag by setting it to null/empty
            $PackageValue = $null
            $LogMessage = 'Successfully removed package tag from template with GUID'
            $SuccessMessage = 'Successfully removed package tag from template(s)'
        } else {
            # Add package tag (existing logic)
            $PackageValue = [string]($Request.body.Package | Select-Object -First 1)
            $LogMessage = 'Successfully updated template with GUID'
            $SuccessMessage = "Successfully updated template(s) with package tag: $PackageValue"
        }

        # Packages are only read for these types, and a tag decides what a standard deploys.
        $TypePermission = @{ CATemplate = 'Tenant.ConditionalAccess.ReadWrite'; IntuneTemplate = 'Endpoint.MEM.ReadWrite' }
        $Templates = foreach ($GUID in $GUIDS) {
            $SafeGUID = ConvertTo-CIPPODataFilterValue -Value $GUID -Type String
            $Template = Get-CIPPAzDataTableEntity @Table -Filter "(PartitionKey eq 'CATemplate' or PartitionKey eq 'IntuneTemplate') and RowKey eq '$SafeGUID'" | Select-Object -First 1
            if (-not $Template) { throw [System.Management.Automation.ItemNotFoundException]::new("Template $GUID not found") }
            if (-not (Test-CippTemplateWriteAccess -Permission $TypePermission[$Template.PartitionKey])) {
                throw [System.UnauthorizedAccessException]::new("Changing package tags needs $($TypePermission[$Template.PartitionKey]) and a role that is not limited to specific tenants.")
            }
            $Template
        }

        foreach ($Template in $Templates) {
            $GUID = $Template.RowKey
            $Entity = @{
                JSON         = $Template.JSON
                RowKey       = "$GUID"
                PartitionKey = $Template.PartitionKey
                GUID         = "$GUID"
                Package      = $PackageValue
                SHA          = $Template.SHA ?? $null
                Source       = $Template.Source ?? $null
            }

            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force

            if ($Remove -eq $true) {
                Write-LogMessage -headers $Headers -API $APIName -message "$LogMessage $GUID" -Sev 'Info'
            } else {
                Write-LogMessage -headers $Headers -API $APIName -message "$LogMessage $GUID with package tag: $PackageValue" -Sev 'Info'
            }
        }

        $body = [pscustomobject]@{ 'Results' = $SuccessMessage }

    } catch {
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
        $ErrorMessage = Get-CippException -Exception $_
        if ($Remove -eq $true) {
            Write-LogMessage -headers $Headers -API $APIName -message "Failed to remove package tag: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
            $body = [pscustomobject]@{'Results' = "Failed to remove package tag: $($ErrorMessage.NormalizedError)" }
        } else {
            Write-LogMessage -headers $Headers -API $APIName -message "Failed to set package tag: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
            $body = [pscustomobject]@{'Results' = "Failed to set package tag: $($ErrorMessage.NormalizedError)" }
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })
}
