using namespace System.Net

Function Invoke-AddExConnector {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Connector.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    $ConnectorType = ($Request.Body.PowerShellCommand | ConvertFrom-Json).cippConnectorType
    $RequestParams = $Request.Body.PowerShellCommand | ConvertFrom-Json | Select-Object -Property * -ExcludeProperty GUID, cippConnectorType, SenderRewritingEnabled
    if ($RequestParams.comment) { $RequestParams.comment = Get-CIPPTextReplacement -Text $RequestParams.comment -TenantFilter $Tenant } else { $RequestParams | Add-Member -NotePropertyValue 'no comment' -NotePropertyName comment -Force }
    $Tenants = ($Request.Body.selectedTenants).value
    $Result = foreach ($TenantFilter in $Tenants) {
        try {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet "New-$($ConnectorType)connector" -cmdParams $RequestParams
            "Successfully created Connector for $TenantFilter."
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Successfully created Connector for $TenantFilter." -sev 'Info'
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            "Could not create Connector for $($TenantFilter): $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Could not create Connector for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev 'Error'
        }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = @($Result) }
        })

}
