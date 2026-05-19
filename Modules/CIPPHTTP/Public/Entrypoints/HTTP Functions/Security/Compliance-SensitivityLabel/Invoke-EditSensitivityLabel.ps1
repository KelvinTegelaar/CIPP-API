Function Invoke-EditSensitivityLabel {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.SensitivityLabel.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $Identity = $Request.Query.Identity ?? $Request.Body.Identity ?? $Request.Body.Name

    try {
        $Params = @{
            Identity = $Identity
        }

        if ($Request.Body.parameters) {
            $Request.Body.parameters.PSObject.Properties | ForEach-Object {
                if ($_.Name -ne 'Identity') { $Params[$_.Name] = $_.Value }
            }
        }

        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Label' -cmdParams $Params -Compliance -useSystemMailbox $true
        $Result = "Updated sensitivity label $Identity"
        Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed updating sensitivity label $Identity. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })

}
