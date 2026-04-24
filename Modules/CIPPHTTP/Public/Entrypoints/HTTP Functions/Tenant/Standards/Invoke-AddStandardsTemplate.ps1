function Invoke-AddStandardsTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    if ($Request.Body.tenantFilter -eq 'tenantFilter') {
        throw 'Invalid Tenant Selection. A standard must be assigned to at least 1 tenant.'
    }

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

    $AddObject = @{
        PartitionKey = 'InstanceProperties'
        RowKey       = 'CIPPURL'
        Value        = [string]([System.Uri]$Headers.'x-ms-original-url').Host
    }
    $ConfigTable = Get-CIPPTable -tablename 'Config'
    Add-AzDataTableEntity @ConfigTable -Entity $AddObject -Force

    Write-LogMessage -headers $Request.Headers -API $APINAME -message "Standards Template $($Request.body.templateName) with GUID $GUID added/edited." -Sev 'Info'
    $body = [pscustomobject]@{'Results' = 'Successfully added template'; Metadata = @{id = $GUID } }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
