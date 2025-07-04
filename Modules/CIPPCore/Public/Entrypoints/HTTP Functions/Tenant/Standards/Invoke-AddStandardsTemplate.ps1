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
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $GUID = $Request.Body.GUID ? $Request.Body.GUID : (New-Guid).GUID
    #updatedBy    = $request.headers.'x-ms-client-principal'
    #updatedAt    = (Get-Date).ToUniversalTime()
    $Request.Body | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $GUID -Force
    $Request.Body | Add-Member -NotePropertyName 'createdAt' -NotePropertyValue ($Request.Body.createdAt ? $Request.Body.createdAt : (Get-Date).ToUniversalTime()) -Force
    $Request.Body | Add-Member -NotePropertyName 'updatedBy' -NotePropertyValue ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails -Force
    $Request.Body | Add-Member -NotePropertyName 'updatedAt' -NotePropertyValue (Get-Date).ToUniversalTime() -Force
    $JSON = (ConvertTo-Json -Compress -Depth 100 -InputObject ($Request.Body))
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

    $Result = "Standards Template $($Request.Body.templateName) with GUID $GUID added/edited."
    $StatusCode = [HttpStatusCode]::OK
    Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info'

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = $Result; Metadata = @{ id = $GUID } }
    }
}
