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
    try {

        if ($Request.Query.List) {
            $Rows = Get-CIPPAzDataTableEntity @Table

            # If no excluded licenses exist, initialize from config file
            if ($Rows.Count -lt 1) {
                Write-Information "Excluded licenses count is low ($($Rows.Count)). Initializing from config file."
                $CIPPCoreModuleRoot = Get-Module -Name CIPPCore | Select-Object -ExpandProperty ModuleBase
                $CIPPRoot = (Get-Item $CIPPCoreModuleRoot).Parent.Parent
                $TableBaseData = Get-Content -Path (Join-Path $CIPPRoot 'Config\ExcludeSkuList.JSON') -Raw | ConvertFrom-Json -AsHashtable -Depth 10
                $null = foreach ($Row in $TableBaseData) {
                    $Row.PartitionKey = 'License'
                    $Row.RowKey = $Row.GUID

                    Add-CIPPAzDataTableEntity @Table -Entity ([pscustomobject]$Row) -Force | Out-Null
                }

                $Rows = Get-CIPPAzDataTableEntity @Table

                Write-LogMessage -API $APIName -headers $Headers -message "Initialized $($TableBaseData.Count) excluded licenses from config file" -Sev 'Info'
            }
            $body = @($Rows)
        }

        # Interact with query parameters or the body of the request.
        $GUID = $Request.Body.GUID
        $DisplayName = $Request.Body.SKUName
        if ($Request.Query.AddExclusion) {
            $AddObject = @{
                PartitionKey           = 'License'
                RowKey                 = $GUID
                'GUID'                 = $GUID
                'Product_Display_Name' = $DisplayName
            }
            Add-CIPPAzDataTableEntity @Table -Entity $AddObject -Force

            Write-LogMessage -API $APIName -headers $Headers -message "Added exclusion $DisplayName" -Sev 'Info'
            $body = [pscustomobject]@{'Results' = "Success. We've added $DisplayName to the excluded list." }
        }

        if ($Request.Query.RemoveExclusion) {
            $Filter = "RowKey eq '{0}' and PartitionKey eq 'License'" -f $GUID
            $Entity = Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property PartitionKey, RowKey
            Remove-AzDataTableEntity -Force @Table -Entity $Entity
            Write-LogMessage -API $APIName -headers $Headers -message "Removed exclusion $GUID" -Sev 'Info'
            $body = [pscustomobject]@{'Results' = "Success. We've removed $GUID from the excluded list." }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Result = "Failed to process exclusion request. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API $APIName -headers $Headers -message $Result -Sev 'Error' -LogData $ErrorMessage
        $body = [pscustomobject]@{'Results' = $Result }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode ?? [HttpStatusCode]::OK
            Body       = $body
        })

}
