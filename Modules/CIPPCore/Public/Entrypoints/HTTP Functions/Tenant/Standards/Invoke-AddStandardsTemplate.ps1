using namespace System.Net

function Invoke-AddStandardsTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Standards.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $GUID = $Request.body.GUID ? $request.body.GUID : (New-Guid).GUID
    #updatedBy    = $request.headers.'x-ms-client-principal'
    #updatedAt    = (Get-Date).ToUniversalTime()
    $request.body | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $GUID -Force
    $request.body | Add-Member -NotePropertyName 'createdAt' -NotePropertyValue ($Request.body.createdAt ? $Request.body.createdAt : (Get-Date).ToUniversalTime()) -Force
    $Request.body | Add-Member -NotePropertyName 'updatedBy' -NotePropertyValue ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($request.headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails -Force
    $Request.body | Add-Member -NotePropertyName 'updatedAt' -NotePropertyValue (Get-Date).ToUniversalTime() -Force
    $JSON = (ConvertTo-Json -Compress -Depth 100 -InputObject ($Request.body))
    $Table = Get-CippTable -tablename 'templates'
    $Table.Force = $true
    Add-CIPPAzDataTableEntity @Table -Entity @{
        JSON         = "$JSON"
        RowKey       = "$GUID"
        PartitionKey = 'StandardsTemplateV2'
        GUID         = "$GUID"

    }
    Write-LogMessage -headers $Request.Headers -API $APINAME -message "Created CA Template $($Request.body.name) with GUID $GUID" -Sev 'Debug'
    $body = [pscustomobject]@{'Results' = 'Successfully added template'; Metadata = @{id = $GUID } }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
