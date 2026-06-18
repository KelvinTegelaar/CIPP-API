Function Invoke-AddSensitivityLabelTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.SensitivityLabel.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # Captured labels (Get-Label output) and manual JSON are stored as-is; the read shape (LabelActions etc.)
    # is normalized to deploy parameters at deploy time by Set-CIPPSensitivityLabel. We only keep the fields
    # that matter for re-deployment and drop read-only Get-Label metadata (Guid, ImmutableId, WhenCreated...).
    $KeepFields = @(Get-CIPPSensitivityLabelField) + @('LabelActions', 'PolicyParams', 'Disabled', 'comments')

    try {
        $GUID = (New-Guid).GUID

        $Source = if ($Request.Body.PowerShellCommand) {
            $Request.Body.PowerShellCommand | ConvertFrom-Json
        } else {
            [pscustomobject]$Request.Body
        }

        $DisplayName = $Source.DisplayName ?? $Source.Name ?? $Source.name
        $Ordered = [ordered]@{
            DisplayName = $DisplayName
            Name        = $Source.Name ?? $Source.name
            Comment     = $Source.Comment ?? $Source.comments
        }
        foreach ($Prop in $Source.PSObject.Properties) {
            if ($Prop.Name -notin $KeepFields) { continue }
            if ($Ordered.Contains($Prop.Name)) { continue }
            $Ordered[$Prop.Name] = $Prop.Value
        }

        $JSON = ([pscustomobject]$Ordered | ConvertTo-Json -Depth 10)
        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$JSON"
            RowKey       = "$GUID"
            PartitionKey = 'SensitivityLabelTemplate'
        }
        $Result = "Successfully created Sensitivity Label Template: $DisplayName with GUID $GUID"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Debug'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create Sensitivity Label Template: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })

}
