Function Invoke-AddDlpCompliancePolicyTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.DlpCompliancePolicy.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $GUID = (New-Guid).GUID
        $JSON = if ($Request.Body.PowerShellCommand) {
            $Request.Body.PowerShellCommand | ConvertFrom-Json
        } else {
            ([pscustomobject]$Request.Body | Select-Object Name, Comment, Mode, Workload, Enabled, ExchangeLocation, ExchangeSenderMemberOf, ExchangeSenderMemberOfException, SharePointLocation, SharePointLocationException, OneDriveLocation, OneDriveLocationException, TeamsLocation, TeamsLocationException, EndpointDlpLocation, EndpointDlpLocationException, OnPremisesScannerDlpLocation, OnPremisesScannerDlpLocationException, ThirdPartyAppDlpLocation, ThirdPartyAppDlpLocationException, PowerBIDlpLocation, PowerBIDlpLocationException, RuleParams) | ForEach-Object {
                $NonEmptyProperties = $_.PSObject.Properties | Where-Object { $null -ne $_.Value } | Select-Object -ExpandProperty Name
                $_ | Select-Object -Property $NonEmptyProperties
            }
        }

        # Allow Name to be sourced from displayName/name fields and ensure templated comments preserved
        $JSON = ($JSON | Select-Object @{n = 'name'; e = { $_.Name ?? $_.name } }, @{n = 'comments'; e = { $_.Comment ?? $_.comments } }, * | ConvertTo-Json -Depth 10)
        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$JSON"
            RowKey       = "$GUID"
            PartitionKey = 'DlpCompliancePolicyTemplate'
        }
        $Result = "Successfully created DLP Compliance Policy Template: $($Request.Body.Name ?? $Request.Body.name) with GUID $GUID"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Debug'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create DLP Compliance Policy Template: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })

}
