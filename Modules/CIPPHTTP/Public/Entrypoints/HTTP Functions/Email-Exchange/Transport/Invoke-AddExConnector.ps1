function Invoke-AddExConnector {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Exchange.Connector.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers



    $ConnectorType = ($Request.Body.PowerShellCommand | ConvertFrom-Json).cippConnectorType
    $RequestParams = $Request.Body.PowerShellCommand | ConvertFrom-Json | Select-Object -Property * -ExcludeProperty GUID, cippConnectorType, SenderRewritingEnabled
    if (-not $RequestParams.comment) { $RequestParams | Add-Member -NotePropertyValue 'no comment' -NotePropertyName comment -Force }
    $Tenants = ($Request.Body.selectedTenants).value

    $AllowedTenants = Test-CippAccess -Request $Request -TenantList

    if ($AllowedTenants -ne 'AllTenants') {
        $AllTenants = Get-Tenants -IncludeErrors
        $AllowedTenantList = $AllTenants | Where-Object { $_.customerId -in $AllowedTenants }
        $Tenants = $Tenants | Where-Object { $_ -in $AllowedTenantList.defaultDomainName }
    }

    $Result = foreach ($TenantFilter in $Tenants) {
        try {
            # Copy per tenant so one tenant's resolved %variable% values never feed the next tenant's replacement.
            $CmdParams = $RequestParams | Select-Object -Property *
            if ($CmdParams.comment -match '%') {
                $CmdParams.comment = Get-CIPPTextReplacement -Text $CmdParams.comment -TenantFilter $TenantFilter
            }
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet "New-$($ConnectorType)connector" -cmdParams $CmdParams
            "Successfully created Connector for $TenantFilter."
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Successfully created Connector for $TenantFilter." -sev 'Info'
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            "Could not create Connector for $($TenantFilter): $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Could not create Connector for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev 'Error'
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = @($Result) }
        })

}
