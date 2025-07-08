using namespace System.Net

Function Invoke-ExecEditTemplate {
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
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        $Table = Get-CippTable -tablename 'templates'
        $guid = $request.body.guid
        $JSON = ConvertTo-Json -Compress -Depth 100 -InputObject ($request.body | Select-Object * -ExcludeProperty GUID)
        $Type = $request.Body.Type

        if ($Type -eq 'IntuneTemplate') {
            Write-Host 'Intune Template'
            $OriginalTemplate = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'IntuneTemplate' and RowKey eq '$GUID'"
            $OriginalTemplate = ($OriginalTemplate.JSON | ConvertFrom-Json -Depth 100)
            $RawJSON = $OriginalTemplate.RAWJson
            Set-CIPPIntuneTemplate -RawJSON $RawJSON -GUID $GUID -DisplayName $Request.body.displayName -Description $Request.body.description -templateType $OriginalTemplate.Type -Headers $Request.Headers
        } else {
            $Table.Force = $true

            Add-CIPPAzDataTableEntity @Table -Entity @{
                JSON         = "$JSON"
                RowKey       = "$GUID"
                PartitionKey = "$Type"
                GUID         = "$GUID"
            }
            Write-LogMessage -headers $Request.Headers -API $APINAME -message "Edited template $($Request.body.name) with GUID $GUID" -Sev 'Debug'
        }
        $body = [pscustomobject]@{ 'Results' = 'Successfully saved the template' }

    } catch {
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "Failed to edit template: $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Editing template failed: $($_.Exception.Message)" }
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
