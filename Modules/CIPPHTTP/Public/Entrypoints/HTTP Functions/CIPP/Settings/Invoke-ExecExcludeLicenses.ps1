function Invoke-ExecExcludeLicenses {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Table = Get-CIPPTable -TableName ExcludedLicenses

    # Interact with query parameters or the body of the request.
    try {
        $Action = $Request.Body.Action
        $GUID = $Request.Body.GUID
        $DisplayName = $Request.Body.SKUName

        switch ($Action) {
            'AddExclusion' {
                $AddObject = @{
                    PartitionKey           = 'License'
                    RowKey                 = $GUID
                    'GUID'                 = $GUID
                    'Product_Display_Name' = $DisplayName
                }
                Add-CIPPAzDataTableEntity @Table -Entity $AddObject -Force
                $Result = "Success. Added $DisplayName($GUID) to the excluded licenses list."
                Write-LogMessage -API $APIName -headers $Headers -message $Result -Sev 'Info'

            }
            'RemoveExclusion' {
                $Filter = "RowKey eq '{0}' and PartitionKey eq 'License'" -f $GUID
                $Entity = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey
                Remove-AzDataTableEntity -Force @Table -Entity $Entity
                $Result = "Success. Removed $DisplayName($GUID) from the excluded licenses list."
                Write-LogMessage -API $APIName -headers $Headers -message $Result -Sev 'Info'

            }
            'RestoreDefaults' {
                $FullReset = [bool]$Request.Body.FullReset
                if ($FullReset) {
                    $InitResult = Initialize-CIPPExcludedLicenses -Force -Headers $Headers -APIName $APIName
                } else {
                    $InitResult = Initialize-CIPPExcludedLicenses -Headers $Headers -APIName $APIName
                }
                $Result = $InitResult.Message

            }
            default {
                $StatusCode = [HttpStatusCode]::BadRequest
                $Result = "Invalid action specified: $Action"
            }
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Result = "Failed to process exclusion request. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API $APIName -headers $Headers -message $Result -Sev 'Error' -LogData $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode ?? [HttpStatusCode]::OK
            Body       = [pscustomobject]@{ 'Results' = $Result }
        })
}
