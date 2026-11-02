function Invoke-ListPushSubscriptions {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Lists the signed-in user's registered push notification devices and the instance's VAPID public key.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails

    try {
        $Table = Get-CIPPTable -tablename 'PushSubscriptions'
        $Devices = foreach ($Row in (Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$Username'")) {
            [pscustomobject]@{
                RowKey     = $Row.RowKey
                DeviceName = $Row.DeviceName
                Endpoint   = $Row.Endpoint
                Created    = $Row.Timestamp.DateTime
            }
        }
        $Results = @{
            PublicKey = (Get-CIPPVapidKeys -PublicOnly).PublicKey
            Devices   = @($Devices)
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Results = "Function Error: $($_.Exception.Message)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
